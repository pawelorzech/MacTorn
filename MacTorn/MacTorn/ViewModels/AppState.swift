import Foundation
import Combine
import SwiftUI
import Observation
import WidgetKit
import os.log

/// Runs an async operation over a snapshot of inputs without ever having more than
/// `limit` child tasks in flight. Cancellation prevents queued inputs from starting and
/// is also propagated to the currently-running children.
enum BoundedTaskQueue {
    static func run<Element: Sendable>(
        _ elements: [Element],
        limit: Int,
        operation: @escaping @Sendable (Element) async -> Void
    ) async {
        precondition(limit > 0)
        guard !elements.isEmpty, !Task.isCancelled else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = elements.makeIterator()

            for _ in 0..<min(limit, elements.count) {
                guard !Task.isCancelled, let element = iterator.next() else { break }
                group.addTask {
                    guard !Task.isCancelled else { return }
                    await operation(element)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                guard let element = iterator.next() else { continue }
                group.addTask {
                    guard !Task.isCancelled else { return }
                    await operation(element)
                }
            }
        }
    }
}

@MainActor
@Observable
class AppState {
    private static let appLogger = Logger(subsystem: TornConstants.logSubsystem, category: "AppState")
    var logger: Logger { Self.appLogger }
    let companion: CompanionStore
    /// Torn data for the signed-in account. Replaced wholesale on an account change.
    var player = PlayerState()

    // MARK: - Persisted
    var apiKey: String {
        get { accountSession.apiKey }
        set {
            guard accountSession.updateAPIKey(newValue) else { return }
            resetAccountScopedState()
            // Dedup latches are per-account facts (this chain already alerted, this OC was announced, this
            // bounty was reported), so switching accounts must forget them. Done here rather than in
            // `resetAccountScopedState()` on purpose: that method also runs on a transient permanent-key
            // error, where clearing the latches would re-fire alerts the user has already seen.
            notificationCoordinator.reset()
            if newValue.isEmpty {
                stopPolling()
                stopForumPolling()
            }
            keyValidation = .idle
        }
    }

    /// True after a permanent key error (Torn codes 1/2/18) halted polling.
    /// Blocks auto-restart (e.g. on MenuBarExtra open) until the user changes the key.
    /// `internal` for `@testable`.
    var keyHalted: Bool {
        get { accountSession.isHalted }
        set { accountSession.isHalted = newValue }
    }

    // MARK: - Key validation
    /// Onboarding "Test Connection" state. Drives the SettingsView result panel.
    var keyValidation: KeyValidationState = .idle {
        didSet {
            // Editing Settings invalidates an in-flight test as well as its displayed result.
            if keyValidation == .idle { keyValidationGeneration &+= 1 }
        }
    }
    @ObservationIgnored var keyValidationGeneration: UInt = 0

    // A stored property with a `didSet` write-through to UserDefaults (not `@AppStorage`), so
    // `@Observable` change tracking sees it. The initial value is loaded in `init()`.
    var refreshInterval: Int = 30 {
        didSet {
            guard refreshInterval != oldValue else { return }
            guard Self.refreshIntervals.contains(refreshInterval) else {
                refreshInterval = 30
                return
            }
            defaults.set(refreshInterval, forKey: "refreshInterval")
            // The notification dedup measures "how stale is the previous observation" in
            // multiples of the poll cadence, so it has to hear about a cadence change.
            notificationCoordinator.refreshInterval = TimeInterval(refreshInterval)
            // A running timer keeps the cadence it was installed with and `startPolling` returns early while
            // one runs, so the change has to reinstall it.
            if pollTimer.isRunning { installPollingTimer() }
        }
    }

    // MARK: - Observable State
    var widgetStore: WidgetSnapshotStore?
    @ObservationIgnored var widgetPublicationTask: Task<Void, Never>?
    @ObservationIgnored var reloadWidgetTimelines: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    var errorMsg: String?
    var isLoading: Bool = false
    var notificationRules: [NotificationRule] = []
    var travelNotificationSettings: [TravelNotificationSetting] = []

    // MARK: - New Data Sources
    // Row-based, display-only data pulled on a slow cadence (see fetchActivityData). Kept off `data`
    // so the fast poll, which does not request events/messages, never clobbers it.
    var factionData: FactionData? {
        faction.basic
    }

    /// The live chain, sourced from the **faction** endpoint, the only place Torn returns it: the v1
    /// `user` endpoint has no `chain` selection, so `data?.chain` is never populated in production.
    ///
    /// Both `Chain.timeout` and `FactionChain.timeout` are absolute Unix timestamps, so the mapping is a
    /// straight field copy.
    var liveChain: Chain? {
        guard let chain = faction.basic?.chain else { return nil }
        return Chain(current: chain.current,
                     maximum: chain.max,
                     timeout: chain.timeout,
                     cooldown: chain.cooldown)
    }
    var stocksMetadata: [Int: StockMetadata] = [:]
    /// Torn's global item catalogue, id → name. Empty until the first successful fetch;
    /// everything that reads it degrades to `Item #id` rather than waiting on it.
    var itemCatalog: [Int: String] = [:] {
        didSet {
            guard itemCatalog != oldValue else { return }
            rebuildItemSearchIndex()
        }
    }
    /// Lowercased mirror of `itemCatalog`, used by `searchItems`. Rebuilt only when the catalogue
    /// changes, not on every keystroke.
    @ObservationIgnored var itemSearchIndex: [(id: Int, name: String, lowered: String)] = []
    var watchlistItems: [WatchlistItem] {
        get { watchlist.items }
        set {
            watchlist.items = newValue
            // The Watchlist tab sets and clears thresholds through this setter; the
            // background price-alert timer exists only while one is set.
            syncPriceAlertPolling()
        }
    }
    // MARK: - API v2 user state (organized crime, refills, education, bounties)
    // MARK: - Faction v2 state (ranked wars, news)
    var rankedWars: [RankedWar] {
        faction.wars
    }
    var factionNews: [FactionNews] {
        faction.news
    }
    var watchedThreads: [WatchedThread] {
        get { forumWatch.threads }
        set { forumWatch.threads = newValue }
    }
    var forumWatchConfig: ForumWatchConfig {
        get { forumWatch.config }
        set {
            forumWatch.config = newValue
            // Same as `refreshInterval`: `startForumPolling` returns early while a timer
            // runs, so a new cadence has to reinstall the running timer itself.
            if forumTimer.isRunning,
               forumTimer.interval != Double(forumWatch.config.pollingIntervalSeconds) {
                installForumTimer()
            }
        }
    }

    // MARK: - Update State
    var updateAvailable: GitHubRelease?

    // MARK: - Feedback State
    var feedbackState: AppFeedbackState?
    var showFeedbackPrompt: Bool = false
    static let feedbackThresholds: [TimeInterval] = [3600, 7 * 86400, 30 * 86400]

    // MARK: - Fetch Time (for live countdown calculations)


    /// "Now" on Torn's clock. The only `now` any countdown should compare against.
    var serverNow: Date { player.serverClock.serverNow(time.now) }

    /// The instant of the last successful fetch, expressed on Torn's clock. Pair it with
    /// `serverNow` whenever a duration is relative to the response (`travel.time_left`,
    /// `bar.fulltime`) so the elapsed time is a same-clock subtraction.
    var serverFetchTime: Date { player.serverClock.serverNow(player.lastFetchTime) }


    // MARK: - Next Action
    /// Categories the user has hidden from the Next Action timeline. Persisted.
    var hiddenNextActionCategories: Set<NextActionCategory> = [] {
        didSet {
            guard hiddenNextActionCategories != oldValue else { return }
            saveHiddenNextActionCategories()
        }
    }

    // MARK: - Live Travel Countdown
    @ObservationIgnored let liveTimer = RepeatingTimer()

    // MARK: - Managers
    @ObservationIgnored let updateManager: UpdateManager
    /// Handle for the in-flight (if any) update-check `Task` started by `checkForAppUpdates()`.
    /// Cancelled alongside polling teardown so an in-flight GitHub request doesn't outlive the `AppState`
    /// that started it.
    @ObservationIgnored var updateCheckTask: Task<Void, Never>?

    // MARK: - Networking
    @ObservationIgnored let requester: TornRequester
    @ObservationIgnored let notifier: Notifying
    @ObservationIgnored let connectivity: NetworkConnectivity
    @ObservationIgnored let accountSession: AccountSessionStore
    @ObservationIgnored let userSnapshotService: UserSnapshotServicing
    @ObservationIgnored let faction: FactionStore
    @ObservationIgnored let watchlist: MarketWatchService
    @ObservationIgnored let forumWatch: ForumWatchService

    // MARK: - Timer
    @ObservationIgnored let pollTimer = RepeatingTimer()
    @ObservationIgnored let forumTimer = RepeatingTimer()
    /// Runs only while polling does and at least one watchlist item has a threshold.
    @ObservationIgnored let priceAlertTimer = RepeatingTimer()
    @ObservationIgnored var lastForumFetchAt: Date?

    /// Monotonic identity for accepted user snapshot polls. Deferred cleanup from an
    /// older, cancelled poll must never mutate the loading state owned by a newer one.
    @ObservationIgnored var pollSequence: UInt = 0

    /// Manual refresh debounce is account-generation scoped: saving a different API
    /// key must be able to fetch immediately even if the previous account just did.
    @ObservationIgnored var lastManualRefreshAt: Date?
    @ObservationIgnored var lastManualRefreshGeneration: UInt?
    static let manualRefreshMinInterval: TimeInterval = 3

    @ObservationIgnored var stocksBackoff = RetryBackoff()
    @ObservationIgnored var itemCatalogBackoff = RetryBackoff()
    /// In-memory staleness anchor, seeded from `UserDefaults` once at launch and refreshed on every
    /// successful fetch, so `itemCatalogIsStale` reads only these fields instead of decoding the cached
    /// blob on every poll.
    @ObservationIgnored var itemCatalogFetchedAt: Date?
    ///
    /// True once an *expanded* (`[Int: CachedCatalogItem]`) cache was decoded. A legacy name-only cache
    /// leaves this false so the catalogue is refreshed into the expanded shape.
    @ObservationIgnored var itemCatalogCacheExpanded = false

    /// Non-secret persistence store. Injected so tests get an isolated `UserDefaults` suite instead of
    /// the process-wide `.standard`, which under parallel testing races across test classes on shared
    /// keys (e.g. "watchlist"). Production always passes `.standard`.
    @ObservationIgnored let defaults: UserDefaults

    /// Persistent notification de-duplication. Built from the same injected `defaults`, so tests get
    /// isolated dedup state alongside isolated persistence.
    @ObservationIgnored let notificationCoordinator: NotificationCoordinator

    /// Shared clock (injected). Used for the daily-row-limit pause windows below.
    @ObservationIgnored let time: TimeSource

    /// In-flight background `/key/info` load (see `loadKeyInfoIfNeeded`). Held so a
    /// burst of poll ticks cannot start several at once.
    @ObservationIgnored var keyInfoTask: Task<Void, Never>?

    /// The first poll of a session, ordered behind the key-capabilities load. Held so an
    /// account change can cancel a fetch that is still waiting on `/key/info`.
    @ObservationIgnored var firstFetchTask: Task<Void, Never>?

    /// Monotonic id for first-fetch attempts, so a superseded one cannot clear the window
    /// a newer one opened.
    @ObservationIgnored var firstFetchGeneration: UInt = 0

    /// True while the first poll of a session is waiting on `/key/info`.
    ///
    /// Holds back the timer and manual refresh for that window, so neither can issue the
    /// un-narrowed request the wait exists to prevent.
    @ObservationIgnored var awaitingFirstKeyInfo = false

    /// How long a `/key/info` answer is trusted before it is read again.
    ///
    /// The gate refuses requests on the strength of this snapshot, so a stale one is not
    /// merely out of date: it keeps a working endpoint switched off. An hour is short
    /// enough that joining a faction or widening a key recovers within a sitting, and long
    /// enough that the extra call is invisible against the poll cadence.
    static let keyInfoMaxAge: TimeInterval = 3_600

    /// Scheduled resume after a recoverable key error (federal jail, key cooldown, IP
    /// block). Held so a newer error, or an account change, can cancel the old wake-up.
    @ObservationIgnored var keyResumeTask: Task<Void, Never>?

    /// Chain timeout (seconds remaining) below which the "Chain Expiring!" alert arms.
    static let chainWarningThreshold = 60

    init(session: NetworkSession = URLSession.shared,
         connectivity: NetworkConnectivity? = nil,
         defaults: UserDefaults = .standard,
         time: TimeSource = SystemTimeSource(),
         pollingCoordinator: PollingCoordinator? = nil,
         accountSession: AccountSessionStore? = nil,
         userSnapshotService: UserSnapshotServicing? = nil,
         notifier: Notifying = SilentNotifier()) {
        self.companion = CompanionStore(defaults: defaults, notifier: notifier)
        self.notifier = notifier
        self.updateManager = UpdateManager(session: session)
        self.connectivity = connectivity ?? NetworkMonitor.shared
        self.defaults = defaults
        self.time = time
        self.accountSession = accountSession
            ?? AccountSessionStore(defaults: defaults, credentialStore: InMemoryAPIKeyStore())
        self.userSnapshotService = userSnapshotService ?? UserSnapshotService(session: session)
        self.faction = FactionStore()
        self.watchlist = MarketWatchService(defaults: defaults)
        self.forumWatch = ForumWatchService(defaults: defaults)
        self.notificationCoordinator = NotificationCoordinator(defaults: defaults, time: time)
        self.requester = TornRequester(session: session, time: time, account: self.accountSession,
                                       budget: pollingCoordinator)

        // Seeded by hand from UserDefaults; `didSet` does not fire during `init`, so these assignments do
        // not write back.
        if let stored = defaults.object(forKey: "refreshInterval") as? Int,
           Self.refreshIntervals.contains(stored) {
            self.refreshInterval = stored
        }
        // didSet does not fire on init, so the dedup staleness window is seeded by hand
        // here and kept in step by the didSet from then on.
        self.notificationCoordinator.refreshInterval = TimeInterval(self.refreshInterval)

        loadNotificationRules()
        loadTravelNotificationSettings()
        watchlist.load()
        forumWatch.load()
        loadFeedbackState()
        loadStocksMetadataFromCache()
        loadItemCatalogFromCache()
        loadHiddenNextActionCategories()

        // When the network comes back after an outage, refresh once immediately instead of waiting up to a
        // full refresh interval. `refreshNow` routes through the same throttled, budget-gated path, so this
        // cannot stampede requests. The callback is only invoked on the main actor (NetworkMonitor hops to it).
        self.connectivity.onConnectivityRestored = { [weak self] in
            self?.refreshNow()
        }
        requester.onAccountError = { [weak self] error, endpointID in
            self?.handleAccountError(error, for: endpointID)
        }
    }

    /// The main poll cadences Settings offers, fastest first.
    static let refreshIntervals = [15, 30, 60, 120]

    /// Removes data that belongs to the previously authenticated Torn account. Local
    /// preferences (watchlist, watched threads, appearance) intentionally remain.
    func resetAccountScopedState() {
        keyValidationGeneration &+= 1
        clearWidgets()
        player = PlayerState()
        errorMsg = nil
        isLoading = false
        faction.reset()
        companion.reset()
        // Landing alerts were scheduled for the old account's flight. Left pending, they
        // fire later for an account that is not travelling (or a key that no longer works).
        cancelLandingAlerts()
        // Bounty dedup is deliberately NOT cleared here, for the reason the apiKey setter documents: it is a
        // dedup latch, and a transient permanent-key error routes through this method. It lives in
        // `notificationCoordinator` (persisted), and the setter clears it via
        // `notificationCoordinator.reset()` on a real account change.
        requester.reset()
        keyInfoTask?.cancel()
        keyInfoTask = nil
        firstFetchTask?.cancel()
        firstFetchTask = nil
        awaitingFirstKeyInfo = false
        // The old account's timer must not keep polling under the new account's key. Cancelling it is also
        // what lets `startPolling` run again: its early-return guard reads `timerCancellable` and
        // `lastFetchTime`, which an account change would otherwise leave untouched.
        pollTimer.stop()
        stopPriceAlertPolling()
        accountSession.cancelAllTasks()
        keyResumeTask?.cancel()
        keyResumeTask = nil
        liveTimer.stop()
    }

}
