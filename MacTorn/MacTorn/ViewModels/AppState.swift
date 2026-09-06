import Foundation
import Combine
import SwiftUI
import Observation
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

// MARK: - Appearance
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
@Observable
class AppState {
    private static let appLogger = Logger(subsystem: TornConstants.logSubsystem, category: "AppState")
    var logger: Logger { Self.appLogger }

    // MARK: - Persisted
    var apiKey: String {
        get { accountSession.apiKey }
        set {
            guard accountSession.updateAPIKey(newValue) else { return }
            resetAccountScopedState()
            // Dedup latches are per-account facts (this chain already alerted, this OC
            // was already announced). Switching accounts must forget them. This is done
            // here rather than in `resetAccountScopedState()` on purpose: that method is
            // also called on a transient permanent-key error, where clearing the latches
            // would re-fire alerts the user has already seen. (Audit finding C-03.)
            notificationCoordinator.reset()
            notifiedBountyKeys = []
            if newValue.isEmpty {
                stopPolling()
                stopForumPolling()
            }
            keyValidation = .idle
            keyInfo = nil
        }
    }

    /// True after a permanent key error (Torn codes 1/2/18) halted polling.
    /// Blocks auto-restart (e.g. on MenuBarExtra open) until the user changes the key.
    /// `internal` for `@testable`.
    var keyHalted: Bool {
        get { accountSession.isHalted }
        set { accountSession.isHalted = newValue }
    }

    // MARK: - Key validation (Etap C, ISC-16)
    /// Onboarding "Test Connection" state. Drives the SettingsView result panel.
    var keyValidation: KeyValidationState = .idle
    /// The last successfully-decoded key info. `nil` until validated / after a key change.
    /// PII (player id) lives here for display only — never logged or put in a report.
    var keyInfo: TornKeyInfo?

    // Was @AppStorage; replaced with stored property + didSet write-through to
    // UserDefaults so @Observable change tracking sees it. Initial value is
    // populated from UserDefaults in init().
    var refreshInterval: Int = 30 {
        didSet {
            guard refreshInterval != oldValue else { return }
            guard Self.allowedRefreshIntervals.contains(refreshInterval) else {
                refreshInterval = 30
                return
            }
            defaults.set(refreshInterval, forKey: "refreshInterval")
            // The notification dedup measures "how stale is the previous observation" in
            // multiples of the poll cadence, so it has to hear about a cadence change.
            notificationCoordinator.refreshInterval = TimeInterval(refreshInterval)
        }
    }
    var appearanceMode: String = AppearanceMode.system.rawValue {
        didSet {
            guard appearanceMode != oldValue else { return }
            defaults.set(appearanceMode, forKey: "appearanceMode")
        }
    }

    // MARK: - Observable State
    var widgetStore: WidgetSnapshotStore?
    var data: TornResponse?
    var lastUpdated: Date?
    var errorMsg: String?
    var isLoading: Bool = false
    var notificationRules: [NotificationRule] = []
    var travelNotificationSettings: [TravelNotificationSetting] = []

    // MARK: - New Data Sources
    var moneyData: MoneyData?
    var battleStats: BattleStats?
    var recentAttacks: [AttackResult]?
    // Row-based, display-only data pulled on a slow cadence (see fetchActivityData).
    // Kept as dedicated properties (not on `data`) so the fast poll — which no longer
    // requests events/messages — never clobbers them.
    var activityEvents: [TornEvent] = []
    var unreadMessages: Int = 0
    var factionData: FactionData? {
        factionService.basic
    }

    /// The live chain — sourced from the **faction** endpoint, which is the only place
    /// Torn actually returns it.
    ///
    /// The chain alert, the Next Action entry and the Status card all used to read
    /// `data?.chain` (the *user* snapshot). Torn's v1 `user` endpoint has no `chain`
    /// selection and `user.fast` never requested one, so that field was permanently
    /// `nil` in production and all three surfaces were dead. Only the DEBUG UI-test
    /// fixture ever populated it, which is why the tests stayed green. See audit
    /// finding C-01 (2026-08-01).
    ///
    /// Both `Chain.timeout` and `FactionChain.timeout` are absolute Unix timestamps,
    /// so the mapping is a straight field copy — no unit conversion.
    var liveChain: Chain? {
        guard let chain = factionService.basic?.chain else { return nil }
        return Chain(current: chain.current,
                     maximum: chain.max,
                     timeout: chain.timeout,
                     cooldown: chain.cooldown)
    }
    var propertiesData: [PropertyInfo]?
    var stocksData: [StockHolding] = []
    var stocksMetadata: [Int: StockMetadata] = [:]
    /// Torn's global item catalogue, id → name. Empty until the first successful fetch;
    /// everything that reads it degrades to `Item #id` rather than waiting on it.
    var itemCatalog: [Int: String] = [:]
    var watchlistItems: [WatchlistItem] {
        get { marketWatchService.items }
        set { marketWatchService.items = newValue }
    }
    // MARK: - API v2 user state (organized crime, refills, education, bounties)
    var organizedCrime: OrganizedCrime2?
    var refills: Refills?
    var education: EducationStatus?
    var bountiesOnMe: [Bounty] = []
    /// Unread messages / events / awards / competition, from the point-in-time
    /// `notifications` selection. Cheap enough to refresh on every poll.
    var notificationCounts: TornNotifications?
    /// The virus currently being written, if any. Read rarely — see `fetchVirusIfNeeded`.
    var virus: VirusProgramming?
    // MARK: - Faction v2 state (ranked wars, news)
    var rankedWars: [RankedWar] {
        factionService.wars
    }
    var factionNews: [FactionNews] {
        factionService.news
    }
    var watchedThreads: [WatchedThread] {
        get { forumWatchService.threads }
        set { forumWatchService.threads = newValue }
    }
    var forumWatchConfig: ForumWatchConfig {
        get { forumWatchService.config }
        set { forumWatchService.config = newValue }
    }

    // MARK: - Update State
    var updateAvailable: GitHubRelease?

    // MARK: - Feedback State
    var feedbackState: AppFeedbackState?
    var showFeedbackPrompt: Bool = false
    static let feedbackThresholds: [TimeInterval] = [3600, 7 * 86400, 30 * 86400]

    // MARK: - Fetch Time (for live countdown calculations)
    var lastFetchTime: Date = Date()

    /// Mac↔Torn clock skew, re-derived from `server_time` on every successful snapshot
    /// (issue #46). Every countdown in the app — travel, hospital, jail, chain, OC,
    /// cooldowns, bars — is measured through this, so the whole window agrees on one
    /// clock. Absent or implausible anchors leave it `.synchronized`, i.e. the plain
    /// local clock.
    var serverClock: ServerClock = .synchronized

    /// "Now" on Torn's clock. The only `now` any countdown should compare against.
    var serverNow: Date { serverClock.serverNow(time.now) }

    /// The instant of the last successful fetch, expressed on Torn's clock. Pair it with
    /// `serverNow` whenever a duration is relative to the response (`travel.time_left`,
    /// `bar.fulltime`) so the elapsed time is a same-clock subtraction.
    var serverFetchTime: Date { serverClock.serverNow(lastFetchTime) }

    /// Absolute end-timestamps for active cooldowns, derived at fetch time from
    /// the server's response timestamp. The single source of truth that keeps
    /// the menu-bar and Status tab cooldown countdowns matching torn.com.
    var cooldownEnds: CooldownEnds?

    // MARK: - Next Action (Etap J)
    /// Categories the user has hidden from the Next Action timeline. Persisted.
    var hiddenNextActionCategories: Set<NextActionCategory> = [] {
        didSet {
            guard hiddenNextActionCategories != oldValue else { return }
            saveHiddenNextActionCategories()
        }
    }

    // MARK: - Live Travel Countdown
    var travelSecondsRemaining: Int = 0
    var menuBarDisplay: MenuBarDisplay = .fallbackIcon
    @ObservationIgnored var liveTimerCancellable: AnyCancellable?

    // MARK: - Managers
    @ObservationIgnored let launchAtLogin = LaunchAtLoginManager()
    @ObservationIgnored let shortcutsManager = ShortcutsManager()
    @ObservationIgnored let updateManager = UpdateManager.shared
    /// Handle for the in-flight (if any) update-check `Task` started by
    /// `checkForAppUpdates()`. Cancelled alongside polling teardown (issue #56) so an
    /// in-flight GitHub request doesn't outlive the `AppState` that started it.
    @ObservationIgnored var updateCheckTask: Task<Void, Never>?

    // MARK: - Networking (Dependency Injection for Testing)
    @ObservationIgnored let session: NetworkSession
    @ObservationIgnored let connectivity: NetworkConnectivity
    @ObservationIgnored let accountSession: AccountSessionStore
    @ObservationIgnored let userSnapshotService: UserSnapshotServicing
    @ObservationIgnored let factionService: FactionServicing
    @ObservationIgnored let marketWatchService: MarketWatchServicing
    @ObservationIgnored let forumWatchService: ForumWatchServicing

    // MARK: - State Comparison
    @ObservationIgnored var previousTravel: Travel?
    @ObservationIgnored var notifiedBountyKeys: Set<String> = []
    /// Throttle for the heavy, slow-changing faction v2 overlays (ranked wars + news).
    /// `news` is a row-based cloud category, so this doubles as its rate control:
    /// 5 min → ≤288 calls/day × 25-row limit ≈ 7,200 rows/day, well under the 50k cap.
    @ObservationIgnored var lastFactionV2Fetch: Date?

    /// Throttle for the virus read. The response is an absolute finish timestamp, so
    /// between reads the countdown runs locally and the endpoint only needs re-reading
    /// once that timestamp has passed.
    @ObservationIgnored var lastVirusFetch: Date?

    /// Throttle for the row-based user activity call (events + attacks).
    /// Same 50k-rows/day-per-category budget as faction news — keep the cadence slow.
    @ObservationIgnored var lastActivityFetch: Date?

    // MARK: - Timer
    @ObservationIgnored var timerCancellable: AnyCancellable?
    @ObservationIgnored var forumTimerCancellable: AnyCancellable?
    @ObservationIgnored var lastForumFetchAt: Date?
    @ObservationIgnored var pendingPriceAlerts: [(name: String, price: Int)] = []

    /// Monotonic identity for accepted user snapshot polls. Deferred cleanup from an
    /// older, cancelled poll must never mutate the loading state owned by a newer one.
    @ObservationIgnored var pollSequence: UInt = 0

    /// Manual refresh debounce is account-generation scoped: saving a different API
    /// key must be able to fetch immediately even if the previous account just did.
    @ObservationIgnored var lastManualRefreshAt: Date?
    @ObservationIgnored var lastManualRefreshGeneration: UInt?
    static let manualRefreshMinInterval: TimeInterval = 3

    // Stocks metadata backoff: ladder of seconds applied between retries after failures.
    // Last value is the cap and is used for any further failure beyond the ladder length.
    // Reset to 0 (= no backoff active) on success or when metadata is freshly cached.
    // `internal` (default) so @testable can read these in performance tests.
    var stocksFailureCount = 0
    var stocksNextRetryAfter: Date?

    // Item catalog backoff + in-flight guard, mirroring the stocks metadata ladder above.
    var itemCatalogFailureCount = 0
    var itemCatalogNextRetryAfter: Date?
    @ObservationIgnored var itemCatalogTask: Task<Void, Never>?

    /// Non-secret persistence store. Injected so tests get an isolated
    /// `UserDefaults` suite instead of the process-wide `.standard`, which under
    /// parallel testing races across test classes on shared keys (e.g. "watchlist").
    /// Production always passes `.standard`. See audit finding G-01.
    @ObservationIgnored let defaults: UserDefaults

    /// Persistent notification de-duplication (Etap E). Built from the same injected
    /// `defaults`, so tests get isolated dedup state alongside isolated persistence.
    @ObservationIgnored let notificationCoordinator: NotificationCoordinator

    /// Request/record budget accounting (Etap D). Every request-issuing path records
    /// through it; diagnostics read from it.
    @ObservationIgnored let pollingCoordinator: PollingCoordinator

    /// Per-endpoint last-result/latency/size health (Etap F, Diagnostics).
    @ObservationIgnored let endpointHealth: EndpointHealthTracker

    /// Shared clock (injected). Used for the daily-row-limit pause windows below.
    @ObservationIgnored let time: TimeSource

    /// Decides per endpoint whether a request may be spent at all: live cool-offs after a
    /// self-healing failure, selections the validated key cannot read, faction endpoints
    /// for a factionless player, and the per-category row budget.
    ///
    /// Pauses are keyed by endpoint, never by budget category: `faction.news` and
    /// `faction.basic` share the `faction` budget, but only the row-based `news` can trip
    /// code 14 — pausing it must never stop the point-in-time `faction.basic` chain data
    /// that drives the chain alert.
    @ObservationIgnored let endpointGate: TornEndpointGate

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

    /// When `keyInfo` was last read. Drives the refresh in `loadKeyInfoIfNeeded`.
    @ObservationIgnored var keyInfoLoadedAt: Date?

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
         factionService: FactionServicing? = nil,
         marketWatchService: MarketWatchServicing? = nil,
         forumWatchService: ForumWatchServicing? = nil) {
        self.session = session
        self.connectivity = connectivity ?? NetworkMonitor.shared
        self.defaults = defaults
        self.time = time
        self.accountSession = accountSession ?? AccountSessionStore(defaults: defaults)
        self.userSnapshotService = userSnapshotService ?? UserSnapshotService(session: session)
        self.factionService = factionService ?? FactionService(session: session)
        self.marketWatchService =
            marketWatchService ?? MarketWatchService(defaults: defaults, session: session)
        self.forumWatchService =
            forumWatchService ?? ForumWatchService(defaults: defaults, session: session)
        self.notificationCoordinator = NotificationCoordinator(defaults: defaults, time: time)
        self.pollingCoordinator = pollingCoordinator ?? PollingCoordinator(time: time)
        self.endpointGate = TornEndpointGate(time: time)
        self.endpointHealth = EndpointHealthTracker(time: time)

        // Was provided by @AppStorage; now manual seed from UserDefaults so the
        // values survive across launches. Note: didSet does NOT fire on init,
        // so this assignment doesn't loop-write back into UserDefaults.
        if let stored = defaults.object(forKey: "refreshInterval") as? Int,
           Self.allowedRefreshIntervals.contains(stored) {
            self.refreshInterval = stored
        }
        // didSet does not fire on init, so the dedup staleness window is seeded by hand
        // here and kept in step by the didSet from then on.
        self.notificationCoordinator.refreshInterval = TimeInterval(self.refreshInterval)
        if let stored = defaults.string(forKey: "appearanceMode") {
            self.appearanceMode = stored
        }

        loadNotificationRules()
        loadTravelNotificationSettings()
        loadWatchlist()
        loadForumWatch()
        loadFeedbackState()
        loadStocksMetadataFromCache()
        loadItemCatalogFromCache()
        loadHiddenNextActionCategories()

        // Etap D: when the network comes back after an outage, refresh once immediately
        // instead of waiting up to a full refresh interval. `refreshNow` routes through
        // the same throttled + budget-gated path, so this can't stampede requests. The
        // callback is only ever invoked on the main actor (NetworkMonitor hops to it).
        self.connectivity.onConnectivityRestored = { [weak self] in
            self?.refreshNow()
        }
        // Polling and permissions moved to onAppear in UI
    }

    private static let allowedRefreshIntervals: Set<Int> = [15, 30, 60, 120]

    /// Removes data that belongs to the previously authenticated Torn account. Local
    /// preferences (watchlist, watched threads, appearance) intentionally remain.
    func resetAccountScopedState() {
        clearWidgets()
        data = nil
        lastUpdated = nil
        errorMsg = nil
        isLoading = false
        moneyData = nil
        battleStats = nil
        recentAttacks = nil
        activityEvents = []
        unreadMessages = 0
        factionService.reset()
        propertiesData = nil
        stocksData = []
        organizedCrime = nil
        refills = nil
        education = nil
        bountiesOnMe = []
        notificationCounts = nil
        virus = nil
        lastVirusFetch = nil
        cooldownEnds = nil
        serverClock = .synchronized
        travelSecondsRemaining = 0
        menuBarDisplay = .fallbackIcon
        previousTravel = nil
        // Deliberately NOT cleared here, for the reason the apiKey setter documents: this
        // is a dedup latch, and a transient permanent-key error routes through this method.
        // Wiping it there re-announced every bounty the user had already been told about
        // the moment polling recovered. The setter clears it on a real account change.
        lastFactionV2Fetch = nil
        lastActivityFetch = nil
        endpointGate.reset()
        keyInfoTask?.cancel()
        keyInfoTask = nil
        keyInfoLoadedAt = nil
        firstFetchTask?.cancel()
        firstFetchTask = nil
        awaitingFirstKeyInfo = false
        // The old account's timer must not keep polling under the new account's key. It
        // also fed `startPolling`'s early-return guard, which reads `timerCancellable` and
        // `lastFetchTime` — neither of which an account change touched — so a switch within
        // half a refresh interval returned early and never established the ordering.
        timerCancellable?.cancel()
        timerCancellable = nil
        itemCatalogTask?.cancel()
        itemCatalogTask = nil
        keyResumeTask?.cancel()
        keyResumeTask = nil
        liveTimerCancellable?.cancel()
        liveTimerCancellable = nil
    }

    func isCurrentAccount(_ key: String, generation: UInt) -> Bool {
        accountSession.isCurrent(AccountIdentity(apiKey: key, generation: generation))
    }

    static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

}

// MARK: - Errors
enum APIError: Error {
    case invalidResponse
    case invalidData
}
