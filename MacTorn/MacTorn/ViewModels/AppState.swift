import Foundation
import Combine
import Security
import SwiftUI
import Observation
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "AppState")

// MARK: - KeychainStore (F-01: replaces @AppStorage for the Torn API key)

/// Minimal generic-password Keychain wrapper for the single Torn API key.
/// Lives here as a file-private enum to avoid touching the .pbxproj — the surface
/// is so small (one item) that a separate file would be over-architected.
///
/// Storage attributes:
/// - `kSecClassGenericPassword` (one item, scoped to this app)
/// - `kSecAttrAccessibleAfterFirstUnlock` (available across reboots once the user
///    has logged in once; matches a menu-bar app's expected runtime)
///
/// Test isolation: when running under XCTest we use a `.tests` service name so
/// the test suite cannot read or overwrite a real production API key.
enum KeychainStore {
    static let account = "apiKey"

    static var service: String {
        // Under XCTest, xcodebuild may spawn multiple parallel xctest worker processes.
        // They share the user's login keychain, so a fixed test-service name causes
        // races: one worker's `set` overwrites another's mid-test. PID-suffix isolates
        // them. Orphan entries are bounded (tearDown deletes them).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "com.mactorn.app.tests.\(ProcessInfo.processInfo.processIdentifier)"
        }
        return "com.mactorn.app"
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func set(_ value: String) {
        guard !value.isEmpty else {
            delete()
            return
        }
        guard let data = value.data(using: .utf8) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery.merge(updateAttrs) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("KeychainStore add failed: OSStatus \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            logger.error("KeychainStore update failed: OSStatus \(updateStatus)")
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
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
    // MARK: - Persisted
    /// Torn API key. Stored in the macOS Keychain (see `KeychainStore` above).
    /// Was previously `@AppStorage("apiKey")` which writes plaintext to
    /// `~/Library/Preferences/com.mactorn.app.plist` — an unprivileged read.
    var apiKey: String = "" {
        didSet {
            // Skip the redundant write that the migration assignment in init would
            // otherwise trigger, and avoid Keychain churn on no-op assignments from
            // SwiftUI's binding lifecycle.
            guard apiKey != oldValue else { return }
            KeychainStore.set(apiKey)
        }
    }

    // Was @AppStorage; replaced with stored property + didSet write-through to
    // UserDefaults so @Observable change tracking sees it. Initial value is
    // populated from UserDefaults in init().
    var refreshInterval: Int = 30 {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        }
    }
    var appearanceMode: String = AppearanceMode.system.rawValue {
        didSet {
            guard appearanceMode != oldValue else { return }
            UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode")
        }
    }

    // MARK: - Observable State
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
    var factionData: FactionData?
    var propertiesData: [PropertyInfo]?
    var stocksData: [StockHolding] = []
    var stocksMetadata: [Int: StockMetadata] = [:]
    var watchlistItems: [WatchlistItem] = []
    // MARK: - API v2 user state (organized crime, refills, education, bounties)
    var organizedCrime: OrganizedCrime2?
    var refills: Refills?
    var education: EducationStatus?
    var bountiesOnMe: [Bounty] = []
    // MARK: - Faction v2 state (ranked wars, news)
    var rankedWars: [RankedWar] = []
    var factionNews: [FactionNews] = []
    var watchedThreads: [WatchedThread] = []
    var forumWatchConfig: ForumWatchConfig = ForumWatchConfig()

    // MARK: - Update State
    var updateAvailable: GitHubRelease?

    // MARK: - Feedback State
    var feedbackState: AppFeedbackState?
    var showFeedbackPrompt: Bool = false
    static let feedbackThresholds: [TimeInterval] = [3600, 7 * 86400, 30 * 86400]

    // MARK: - Fetch Time (for live countdown calculations)
    var lastFetchTime: Date = Date()

    /// Absolute end-timestamps for active cooldowns, derived at fetch time from
    /// the server's response timestamp. The single source of truth that keeps
    /// the menu-bar and Status tab cooldown countdowns matching torn.com.
    var cooldownEnds: CooldownEnds?

    // MARK: - Live Travel Countdown
    var travelSecondsRemaining: Int = 0
    var menuBarDisplay: MenuBarDisplay = .fallbackIcon
    @ObservationIgnored private var liveTimerCancellable: AnyCancellable?

    // MARK: - Managers
    @ObservationIgnored let launchAtLogin = LaunchAtLoginManager()
    @ObservationIgnored let shortcutsManager = ShortcutsManager()
    @ObservationIgnored let updateManager = UpdateManager.shared

    // MARK: - Networking (Dependency Injection for Testing)
    @ObservationIgnored private let session: NetworkSession
    @ObservationIgnored private let connectivity: NetworkConnectivity

    // MARK: - State Comparison
    @ObservationIgnored private var previousBars: Bars?
    @ObservationIgnored private var previousCooldowns: Cooldowns?
    @ObservationIgnored private var previousTravel: Travel?
    @ObservationIgnored private var previousChain: Chain?
    @ObservationIgnored private var previousStatus: Status?
    @ObservationIgnored private var previousOCReadyId: Int?
    @ObservationIgnored private var notifiedBountyKeys: Set<String> = []

    // MARK: - Task Handles (for deduplication)
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var watchlistTask: Task<Void, Never>?
    @ObservationIgnored private var forumFetchTask: Task<Void, Never>?

    // MARK: - Timer
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var forumTimerCancellable: AnyCancellable?
    @ObservationIgnored private var lastForumFetchAt: Date?

    private static let stocksMetadataCacheKey = "stocksMetadataCache"

    // Stocks metadata backoff: ladder of seconds applied between retries after failures.
    // Last value is the cap and is used for any further failure beyond the ladder length.
    // Reset to 0 (= no backoff active) on success or when metadata is freshly cached.
    private static let stocksBackoffLadder: [TimeInterval] = [60, 300, 1800]
    // `internal` (default) so @testable can read these in performance tests.
    var stocksFailureCount = 0
    var stocksNextRetryAfter: Date?

    init(session: NetworkSession = URLSession.shared, connectivity: NetworkConnectivity? = nil) {
        self.session = session
        self.connectivity = connectivity ?? NetworkMonitor.shared

        // F-01 migration: lift any pre-existing plaintext key out of UserDefaults
        // into the Keychain on first launch of the new build, then clear the
        // UserDefaults entry. Safe to run every launch (idempotent).
        if let legacy = UserDefaults.standard.string(forKey: "apiKey"), !legacy.isEmpty {
            KeychainStore.set(legacy)
            UserDefaults.standard.removeObject(forKey: "apiKey")
            logger.info("Migrated API key from UserDefaults to Keychain")
        }
        self.apiKey = KeychainStore.get() ?? ""

        // Was provided by @AppStorage; now manual seed from UserDefaults so the
        // values survive across launches. Note: didSet does NOT fire on init,
        // so this assignment doesn't loop-write back into UserDefaults.
        if let stored = UserDefaults.standard.object(forKey: "refreshInterval") as? Int {
            self.refreshInterval = stored
        }
        if let stored = UserDefaults.standard.string(forKey: "appearanceMode") {
            self.appearanceMode = stored
        }

        loadNotificationRules()
        loadTravelNotificationSettings()
        loadWatchlist()
        loadForumWatch()
        loadFeedbackState()
        loadStocksMetadataFromCache()
        // Polling and permissions moved to onAppear in UI
    }

    // MARK: - Stocks Metadata (global lookup from torn/?selections=stocks)
    func loadStocksMetadataFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.stocksMetadataCacheKey),
              let cached = try? JSONDecoder().decode([Int: StockMetadata].self, from: data) else {
            return
        }
        stocksMetadata = cached
    }

    func fetchStocksMetadata() async {
        guard !apiKey.isEmpty, let url = TornAPI.tornStocksURL(for: apiKey) else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await session.data(for: request)
            let parsed = AppState.parseStocksMetadata(from: data, logger: logger)
            guard !parsed.isEmpty else {
                await MainActor.run { self.recordStocksMetadataFailure() }
                return
            }
            await MainActor.run {
                self.stocksMetadata = parsed
                if let encoded = try? JSONEncoder().encode(parsed) {
                    UserDefaults.standard.set(encoded, forKey: Self.stocksMetadataCacheKey)
                }
                self.stocksFailureCount = 0
                self.stocksNextRetryAfter = nil
                logger.info("Stocks metadata loaded: \(parsed.count) stocks")
            }
        } catch {
            await MainActor.run { self.recordStocksMetadataFailure() }
            logger.error("Failed to fetch stocks metadata: \(error.localizedDescription)")
        }
    }

    /// Bumps failure count and computes the next allowable retry instant from the backoff ladder.
    /// `internal` so unit tests can drive it without going through a fake URL session.
    @MainActor
    func recordStocksMetadataFailure() {
        stocksFailureCount += 1
        let idx = min(stocksFailureCount - 1, Self.stocksBackoffLadder.count - 1)
        let delay = Self.stocksBackoffLadder[idx]
        stocksNextRetryAfter = Date().addingTimeInterval(delay)
    }

    /// Parses the `torn/?selections=stocks` response using JSONSerialization (resilient to extra fields).
    /// Exposed as a static func so tests can drive it without a network round-trip.
    nonisolated static func parseStocksMetadata(from data: Data, logger: Logger) -> [Int: StockMetadata] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Stocks metadata: failed to parse JSON")
            return [:]
        }
        if let msg = tornAPIErrorMessage(in: json) {
            logger.error("Stocks metadata API error: \(msg)")
            return [:]
        }
        guard let stocksDict = json["stocks"] as? [String: [String: Any]] else {
            logger.warning("Stocks metadata: no 'stocks' key in response")
            return [:]
        }
        var result: [Int: StockMetadata] = [:]
        for (key, stockData) in stocksDict {
            guard let id = Int(key) else { continue }
            let name = stockData["name"] as? String ?? ""
            let acronym = stockData["acronym"] as? String ?? ""
            let price: Double
            if let n = stockData["current_price"] as? NSNumber {
                price = n.doubleValue
            } else if let s = stockData["current_price"] as? String, let d = Double(s) {
                price = d
            } else {
                price = 0
            }
            result[id] = StockMetadata(id: id, name: name, acronym: acronym, currentPrice: price)
        }
        return result
    }
    
    // MARK: - Notification Rules
    func loadNotificationRules() {
        if let data = UserDefaults.standard.data(forKey: "notificationRules"),
           let rules = try? JSONDecoder().decode([NotificationRule].self, from: data) {
            notificationRules = rules
        } else {
            notificationRules = NotificationRule.defaults
            saveNotificationRules()
        }
    }
    
    func saveNotificationRules() {
        if let data = try? JSONEncoder().encode(notificationRules) {
            UserDefaults.standard.set(data, forKey: "notificationRules")
        }
    }
    
    func updateRule(_ rule: NotificationRule) {
        if let index = notificationRules.firstIndex(where: { $0.id == rule.id }) {
            notificationRules[index] = rule
            saveNotificationRules()
        }
    }

    // MARK: - Travel Notification Settings
    func loadTravelNotificationSettings() {
        if let data = UserDefaults.standard.data(forKey: "travelNotificationSettings"),
           let settings = try? JSONDecoder().decode([TravelNotificationSetting].self, from: data) {
            travelNotificationSettings = settings
        } else {
            travelNotificationSettings = TravelNotificationSetting.defaults
            saveTravelNotificationSettings()
        }
    }

    func saveTravelNotificationSettings() {
        if let data = try? JSONEncoder().encode(travelNotificationSettings) {
            UserDefaults.standard.set(data, forKey: "travelNotificationSettings")
        }
    }

    func updateTravelNotificationSetting(_ setting: TravelNotificationSetting) {
        if let index = travelNotificationSettings.firstIndex(where: { $0.id == setting.id }) {
            travelNotificationSettings[index] = setting
            saveTravelNotificationSettings()
            // Reschedule notifications if currently traveling
            if let travel = data?.travel, travel.isTraveling {
                scheduleTravelNotifications(for: travel)
            }
        }
    }

    func scheduleTravelNotifications(for travel: Travel) {
        // Cancel any existing travel notifications first
        NotificationManager.shared.cancelTravelNotifications()

        guard let arrivalDate = travel.arrivalDate else { return }

        for setting in travelNotificationSettings where setting.enabled {
            let notificationDate = arrivalDate.addingTimeInterval(-Double(setting.secondsBefore))

            // Only schedule if the notification time is in the future
            if notificationDate > Date() {
                let identifier = "\(setting.id)_alert"
                let timeText: String
                if setting.secondsBefore >= 60 {
                    timeText = "\(setting.secondsBefore / 60) minute\(setting.secondsBefore >= 120 ? "s" : "")"
                } else {
                    timeText = "\(setting.secondsBefore) seconds"
                }

                NotificationManager.shared.scheduleNotification(
                    title: "Landing Soon!",
                    body: "You will arrive in \(travel.destination ?? "your destination") in \(timeText)",
                    type: .travelApproaching,
                    at: notificationDate,
                    identifier: identifier
                )
            }
        }
    }

    // MARK: - Live Timer (drives travel countdown + menu bar display)
    func manageLiveTimer() {
        tick()
        if shouldRunLiveTimer {
            if liveTimerCancellable == nil {
                startLiveTimer()
            }
        } else {
            stopLiveTimer()
        }
    }

    private var shouldRunLiveTimer: Bool {
        guard let data = data else { return false }
        if let travel = data.travel, travel.isTraveling { return true }
        if let status = data.status, status.isInHospital || status.isInJail { return true }
        if let ends = cooldownEnds, ends.soonestActive() != nil { return true }
        return false
    }

    private func startLiveTimer() {
        liveTimerCancellable?.cancel()

        liveTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopLiveTimer() {
        liveTimerCancellable?.cancel()
        liveTimerCancellable = nil
        travelSecondsRemaining = 0
        menuBarDisplay = computeMenuBarDisplay()
    }

    private func tick() {
        updateTravelSecondsRemaining()
        // Skip @Published write if computed value is unchanged: avoids SwiftUI
        // invalidating MenuBarLabel + every observer once per second when the
        // displayed string hasn't actually changed (cooldowns shown as `Hh Mm`
        // tick the underlying seconds but render the same label for ~60s).
        let next = computeMenuBarDisplay()
        if next != menuBarDisplay {
            menuBarDisplay = next
        }
    }

    private func updateTravelSecondsRemaining() {
        let next: Int
        if let travel = data?.travel, travel.isTraveling {
            next = travel.remainingSeconds(from: lastFetchTime)
        } else {
            next = 0
        }
        if next != travelSecondsRemaining {
            travelSecondsRemaining = next
        }
    }

    private func computeMenuBarDisplay() -> MenuBarDisplay {
        guard let data = data else { return .fallbackIcon }

        if let travel = data.travel, travel.isTraveling {
            let flag = TornDestination.flag(for: travel.destination ?? "?")
            return .traveling(flag: flag, seconds: travel.remainingSeconds(from: lastFetchTime))
        }

        if let status = data.status, status.isInHospital {
            let secs = status.timeRemaining
            if let travel = data.travel, travel.isAbroad {
                let flag = TornDestination.flag(for: travel.destination ?? "?")
                return .hospitalAbroad(flag: flag, seconds: secs)
            }
            return .hospitalAtHome(seconds: secs)
        }

        if let status = data.status, status.isInJail {
            return .jail(seconds: status.timeRemaining)
        }

        if let ends = cooldownEnds,
           let soonest = ends.soonestActive() {
            return .cooldown(emoji: soonest.kind.emoji, seconds: soonest.seconds)
        }

        return .fallbackIcon
    }

    // MARK: - Watchlist
    func loadWatchlist() {
        if let data = UserDefaults.standard.data(forKey: "watchlist"),
           let items = try? JSONDecoder().decode([WatchlistItem].self, from: data) {
            watchlistItems = items
        }
    }
    
    func saveWatchlist() {
        if let data = try? JSONEncoder().encode(watchlistItems) {
            UserDefaults.standard.set(data, forKey: "watchlist")
        }
    }
    
    func addToWatchlist(itemId: Int, name: String) {
        // Clamp inputs at the trust boundary. itemId flows directly into a request URL path
        // and `name` flows into UNNotificationContent.body, so reject obviously bogus values
        // rather than persisting them. Torn item IDs are positive and currently <100k.
        guard itemId > 0, itemId < 100_000 else {
            logger.warning("addToWatchlist rejected itemId out of range: \(itemId)")
            return
        }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        let item = WatchlistItem(id: itemId, name: trimmed, lowestPrice: 0, lowestPriceQuantity: 0, secondLowestPrice: 0, lastUpdated: nil, error: nil)
        if !watchlistItems.contains(where: { $0.id == itemId }) {
            watchlistItems.append(item)
            saveWatchlist()
            // Fetch price immediately
            Task {
                await fetchItemPrice(itemId: itemId)
            }
        }
    }
    
    func removeFromWatchlist(_ itemId: Int) {
        watchlistItems.removeAll { $0.id == itemId }
        saveWatchlist()
    }
    
    func refreshWatchlistPrices() {
        watchlistTask?.cancel()
        watchlistTask = Task {
            await fetchWatchlistPrices()
        }
    }
    
    /// Accumulated alerts during a batch refresh; flushed (single or summary) at the end.
    private var pendingPriceAlerts: [(name: String, price: Int)] = []

    private func fetchWatchlistPrices() async {
        guard connectivity.isConnected else { return }
        pendingPriceAlerts.removeAll(keepingCapacity: true)
        await withTaskGroup(of: Void.self) { group in
            for item in watchlistItems {
                group.addTask { await self.fetchItemPrice(itemId: item.id, save: false) }
            }
        }
        flushPendingPriceAlerts()
        saveWatchlist()
    }

    private func flushPendingPriceAlerts() {
        let alerts = pendingPriceAlerts
        pendingPriceAlerts.removeAll(keepingCapacity: true)
        guard !alerts.isEmpty else { return }
        if alerts.count == 1 {
            let a = alerts[0]
            NotificationManager.shared.send(
                title: "Price Alert: \(a.name)",
                body: "Lowest price dropped to \(formatAlertPrice(a.price))",
                type: .priceAlert
            )
            return
        }
        // Summary notification: list up to 3 names then "+N more".
        let preview = alerts.prefix(3).map { $0.name }.joined(separator: ", ")
        let extra = alerts.count > 3 ? " +\(alerts.count - 3) more" : ""
        NotificationManager.shared.send(
            title: "\(alerts.count) price alerts",
            body: "\(preview)\(extra)",
            type: .priceAlert
        )
    }
    
    private func fetchItemPrice(itemId: Int, save: Bool = true) async {
        guard !apiKey.isEmpty,
              let url = TornAPI.marketURL(itemId: itemId, apiKey: apiKey) else { return }

        logger.info("Fetching price for item \(itemId)")

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                logger.error("Item \(itemId) HTTP Error: \(httpResponse.statusCode)")
                updateItemError(itemId: itemId, error: "HTTP \(httpResponse.statusCode)", save: save)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Check if API returned error
                if let errorText = tornAPIErrorMessage(in: json) {
                    logger.warning("Item \(itemId) API error: \(errorText)")
                    updateItemError(itemId: itemId, error: errorText, save: save)
                    return
                }

                var allListings: [(price: Int, amount: Int)] = []

                // Check itemmarket v2 structure
                if let itemmarket = json["itemmarket"] as? [String: Any],
                   let listings = itemmarket["listings"] as? [[String: Any]] {
                     let mapped = listings.compactMap { dict -> (Int, Int)? in
                        guard let p = dict["price"] as? Int else { return nil }
                        return (p, dict["amount"] as? Int ?? 1)
                     }
                     allListings.append(contentsOf: mapped)
                }
                // Fallback for v1
                else if let itemmarketArr = json["itemmarket"] as? [[String: Any]] {
                     let mapped = itemmarketArr.compactMap { dict -> (Int, Int)? in
                        guard let p = dict["cost"] as? Int else { return nil }
                        return (p, dict["quantity"] as? Int ?? 1)
                     }
                     allListings.append(contentsOf: mapped)
                }

                // Check bazaar
                if let bazaarArr = json["bazaar"] as? [[String: Any]] {
                    let mapped = bazaarArr.compactMap { dict -> (Int, Int)? in
                        guard let p = dict["cost"] as? Int else { return nil }
                        return (p, dict["quantity"] as? Int ?? 1)
                    }
                    allListings.append(contentsOf: mapped)
                }

                let sortedListings = allListings.sorted { $0.price < $1.price }
                logger.debug("Item \(itemId): found \(sortedListings.count) listings, lowest: \(sortedListings.first?.price ?? 0)")

                if let best = sortedListings.first {
                    let secondPrice = sortedListings.count > 1 ? sortedListings[1].price : 0
                    updateItemPrice(itemId: itemId, lowestPrice: best.price, lowestPriceQuantity: best.amount, secondLowestPrice: secondPrice, save: save)
                } else {
                    updateItemError(itemId: itemId, error: "No listings", save: save)
                }
            } else {
                logger.error("Item \(itemId): failed to parse JSON response")
                updateItemError(itemId: itemId, error: "Parse Error", save: save)
            }
        } catch {
            if Task.isCancelled { return }
            logger.error("Item \(itemId) price fetch error: \(error.localizedDescription)")
            updateItemError(itemId: itemId, error: "Network Error", save: save)
        }
    }
    
    @MainActor
    private func updateItemPrice(itemId: Int, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, save: Bool = true) {
        if let index = watchlistItems.firstIndex(where: { $0.id == itemId }) {
            var item = watchlistItems[index]
            item.lowestPrice = lowestPrice
            item.lowestPriceQuantity = lowestPriceQuantity
            item.secondLowestPrice = secondLowestPrice
            item.lastUpdated = Date()
            item.error = nil
            watchlistItems[index] = item
            if watchlistItems[index].shouldFirePriceAlert {
                if save {
                    // Single-item path (e.g. addToWatchlist): fire immediately.
                    NotificationManager.shared.send(
                        title: "Price Alert: \(item.name)",
                        body: "Lowest price dropped to \(formatAlertPrice(lowestPrice))",
                        type: .priceAlert
                    )
                } else {
                    // Batch path (refreshWatchlistPrices): buffer and emit one summary
                    // notification at end of fetchWatchlistPrices via flushPendingPriceAlerts().
                    pendingPriceAlerts.append((name: item.name, price: lowestPrice))
                }
                watchlistItems[index].lastAlertedPrice = lowestPrice
            }
            if save { saveWatchlist() }
        }
    }

    private func formatAlertPrice(_ price: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "$\(price)"
    }

    @MainActor
    private func updateItemError(itemId: Int, error: String, save: Bool = true) {
        if let index = watchlistItems.firstIndex(where: { $0.id == itemId }) {
            var item = watchlistItems[index]
            item.error = error
            watchlistItems[index] = item
            if save { saveWatchlist() }
        }
    }
    
    // MARK: - Forum Watch
    func loadForumWatch() {
        if let data = UserDefaults.standard.data(forKey: "forumWatchedThreads"),
           let threads = try? JSONDecoder().decode([WatchedThread].self, from: data) {
            watchedThreads = threads
        }
        if let data = UserDefaults.standard.data(forKey: "forumWatchConfig"),
           let config = try? JSONDecoder().decode(ForumWatchConfig.self, from: data) {
            forumWatchConfig = config
        }
    }

    func saveForumWatch() {
        if let data = try? JSONEncoder().encode(watchedThreads) {
            UserDefaults.standard.set(data, forKey: "forumWatchedThreads")
        }
        if let data = try? JSONEncoder().encode(forumWatchConfig) {
            UserDefaults.standard.set(data, forKey: "forumWatchConfig")
        }
    }

    func parseThreadInput(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try bare integer
        if let id = Int(trimmed) {
            return id
        }
        // Try URL pattern: forums.php...t=12345
        if let range = trimmed.range(of: #"[?&#]t=(\d+)"#, options: .regularExpression) {
            let match = trimmed[range]
            let digits = match.drop(while: { !$0.isNumber })
            return Int(digits)
        }
        return nil
    }

    func addWatchedThread(input: String) {
        guard let threadId = parseThreadInput(input) else { return }
        guard !watchedThreads.contains(where: { $0.id == threadId }) else { return }

        let thread = WatchedThread(id: threadId, title: "Loading...", lastKnownPostCount: 0)
        watchedThreads.append(thread)
        saveForumWatch()

        Task {
            await fetchForumThreadMetadata(threadId: threadId)
        }
    }

    func removeWatchedThread(_ threadId: Int) {
        watchedThreads.removeAll { $0.id == threadId }
        saveForumWatch()
    }

    func toggleThreadNotifications(_ threadId: Int) {
        if let index = watchedThreads.firstIndex(where: { $0.id == threadId }) {
            watchedThreads[index].notificationsEnabled.toggle()
            saveForumWatch()
        }
    }

    func markThreadAsRead(_ threadId: Int) {
        if let index = watchedThreads.firstIndex(where: { $0.id == threadId }) {
            // We don't know the "current" post count from here, so the view should pass it
            // or we just flag it. The fetchForumUpdates will set the correct count next poll.
            watchedThreads[index].error = nil
            saveForumWatch()
        }
    }

    func startForumPolling() {
        // Same MenuBarExtra-onAppear churn as startPolling: skip restart if already
        // running and we polled recently.
        if forumTimerCancellable != nil,
           let last = lastForumFetchAt,
           Date().timeIntervalSince(last) < Double(forumWatchConfig.pollingIntervalSeconds) / 2 {
            return
        }
        forumTimerCancellable?.cancel()
        guard !apiKey.isEmpty else { return }

        // Initial fetch
        refreshForumWatch()

        forumTimerCancellable = Timer.publish(every: Double(forumWatchConfig.pollingIntervalSeconds), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshForumWatch()
            }
    }

    func stopForumPolling() {
        forumTimerCancellable?.cancel()
        forumTimerCancellable = nil
    }

    func refreshForumWatch() {
        forumFetchTask?.cancel()
        forumFetchTask = Task {
            await fetchForumUpdates()
        }
    }

    private func fetchForumUpdates() async {
        guard connectivity.isConnected, !apiKey.isEmpty else { return }

        // Fetch all watched threads in parallel
        await withTaskGroup(of: Void.self) { group in
            for thread in watchedThreads {
                group.addTask { await self.checkThreadForUpdates(threadId: thread.id) }
            }
        }

        lastForumFetchAt = Date()
        saveForumWatch()
    }

    private func checkThreadForUpdates(threadId: Int) async {
        guard let url = TornAPI.forumThreadURL(threadId: threadId, apiKey: apiKey) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            // v2 API wraps the thread in a top-level object
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for API error
                if let errorText = tornAPIErrorMessage(in: json) {
                    await updateThreadError(threadId: threadId, error: errorText)
                    return
                }

                // Parse thread data - v2 may return directly or nested
                let threadData: [String: Any]? = json["thread"] as? [String: Any] ?? json
                guard let threadInfo = threadData else { return }

                let title = threadInfo["title"] as? String ?? "Unknown"
                let currentPostCount = threadInfo["posts"] as? Int ?? 0

                await MainActor.run {
                    if let index = self.watchedThreads.firstIndex(where: { $0.id == threadId }) {
                        let previousCount = self.watchedThreads[index].lastKnownPostCount

                        // Always-set: title (may have changed) + lastChecked. Only set error
                        // if it was non-nil (avoid spurious @Published write on no-op).
                        if self.watchedThreads[index].title != title {
                            self.watchedThreads[index].title = title
                        }
                        self.watchedThreads[index].lastChecked = Date()
                        if self.watchedThreads[index].error != nil {
                            self.watchedThreads[index].error = nil
                        }

                        // Short-circuit: if post count is unchanged, skip the
                        // notification check + post-count write entirely.
                        guard currentPostCount != previousCount else { return }

                        if previousCount > 0 && currentPostCount > previousCount {
                            let newPosts = currentPostCount - previousCount
                            if self.watchedThreads[index].notificationsEnabled {
                                let threadURL = URL(string: "https://www.torn.com/forums.php#/p=threads&t=\(threadId)")
                                NotificationManager.shared.send(
                                    title: "Forum: \(title)",
                                    body: "\(newPosts) new post\(newPosts == 1 ? "" : "s")",
                                    type: .forumNewPosts,
                                    customURL: threadURL
                                )
                            }
                        }
                        self.watchedThreads[index].lastKnownPostCount = currentPostCount
                    }
                }
            }
        } catch {
            if Task.isCancelled { return }
            await updateThreadError(threadId: threadId, error: "Network Error")
        }
    }

    @MainActor
    private func updateThreadError(threadId: Int, error: String) {
        if let index = watchedThreads.firstIndex(where: { $0.id == threadId }) {
            watchedThreads[index].error = error
        }
    }

    private func fetchForumThreadMetadata(threadId: Int) async {
        guard let url = TornAPI.forumThreadURL(threadId: threadId, apiKey: apiKey) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await updateThreadError(threadId: threadId, error: "HTTP Error")
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errorText = tornAPIErrorMessage(in: json) {
                    await updateThreadError(threadId: threadId, error: errorText)
                    return
                }

                let threadData: [String: Any]? = json["thread"] as? [String: Any] ?? json
                guard let threadInfo = threadData else { return }

                let title = threadInfo["title"] as? String ?? "Unknown"
                let postCount = threadInfo["posts"] as? Int ?? 0

                await MainActor.run {
                    if let index = self.watchedThreads.firstIndex(where: { $0.id == threadId }) {
                        self.watchedThreads[index].title = title
                        self.watchedThreads[index].lastKnownPostCount = postCount
                        self.watchedThreads[index].lastChecked = Date()
                        self.watchedThreads[index].error = nil
                    }
                }
            }
        } catch {
            if Task.isCancelled { return }
            await updateThreadError(threadId: threadId, error: "Network Error")
        }

        saveForumWatch()
    }

    // MARK: - Polling
    func startPolling(force: Bool = false) {
        // MenuBarExtra fires onAppear on every menu open, so this is called repeatedly.
        // If the timer is already running and we fetched recently (< refreshInterval/2 ago),
        // skip the restart + immediate refetch — it just burns API quota.
        // `force: true` (refreshNow) bypasses the guard for an explicit user-initiated refresh.
        if !force,
           timerCancellable != nil,
           Date().timeIntervalSince(lastFetchTime) < Double(refreshInterval) / 2 {
            return
        }
        timerCancellable?.cancel()
        fetchData()
        // Idempotent: only fetch if we don't already have metadata. This survives the
        // "startPolling fires before apiKey loaded" race because we'll retry next tick.
        triggerStocksMetadataFetchIfNeeded()
        timerCancellable = Timer.publish(every: Double(refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchData()
                self?.triggerStocksMetadataFetchIfNeeded()
            }
    }

    private func triggerStocksMetadataFetchIfNeeded() {
        guard stocksMetadata.isEmpty, !apiKey.isEmpty else { return }
        // Respect exponential backoff so a persistent endpoint failure doesn't
        // burn API quota on every 30s poll cycle.
        if let nextRetry = stocksNextRetryAfter, Date() < nextRetry { return }
        Task { await self.fetchStocksMetadata() }
    }
    
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    func refreshNow() {
        startPolling(force: true)
    }
    
    // MARK: - Fetch Data
    func fetchData() {
        guard connectivity.isConnected else {
            if errorMsg != "No internet connection" {
                errorMsg = "No internet connection"
                logger.warning("Fetch aborted: No internet connection")
            }
            return
        }

        guard !apiKey.isEmpty else {
            errorMsg = "API Key required"
            logger.warning("Fetch aborted: API Key required")
            return
        }

        guard let url = TornAPI.url(for: apiKey) else {
            errorMsg = "Invalid URL"
            logger.error("Fetch aborted: Invalid URL")
            return
        }

        isLoading = true
        errorMsg = nil

        logger.info("Starting data fetch from: \(tornRedactedURL(url))")

        fetchTask?.cancel()
        fetchTask = Task {
            let startTime = Date()

            // Ensure minimum loading time for UX, then set isLoading = false
            defer {
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed < 0.5 {
                        try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
                    }
                    self.isLoading = false
                }
            }

            do {
                // Create request with no-cache policy to ensure fresh data
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                logger.info("HTTP response: \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200:
                    // Diagnostics only: payload size + top-level keys. Never log raw response —
                    // it contains player name, money, stats, attacks, and other PII (and the
                    // request URL with the API key already passed through redacted logging).
                    if let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let keys = topLevel.keys.sorted().joined(separator: ",")
                        logger.debug("API response: \(data.count) bytes, keys=[\(keys)]")
                    } else {
                        logger.debug("API response: \(data.count) bytes (non-JSON or unparseable)")
                    }

                    // Parse user data and fetch faction + v2 data in parallel
                    async let factionResult: Void = self.fetchFactionData()
                    async let userV2Result: Void = self.fetchUserV2Data()
                    async let factionV2Result: Void = self.fetchFactionV2Data()
                    try await parseDataInBackground(data: data)
                    await factionResult
                    await userV2Result
                    await factionV2Result

                    logger.info("Data fetch completed successfully")

                case 403, 404:
                    await MainActor.run {
                        self.errorMsg = "Invalid API Key"
                        self.data = nil
                    }
                    logger.error("HTTP \(httpResponse.statusCode): Invalid API Key")
                default:
                    await MainActor.run {
                        self.errorMsg = "HTTP Error: \(httpResponse.statusCode)"
                    }
                    logger.error("HTTP Error: \(httpResponse.statusCode)")
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.errorMsg = "Network error: \(error.localizedDescription)"
                }
                logger.error("Network error: \(error.localizedDescription)")
            }
        }
    }

    // Move parsing logic here and mark as non-isolated or detached
    private func parseDataInBackground(data: Data) async throws {
        // Run CPU-heavy parsing detached from MainActor
        let result = await Task.detached(priority: .userInitiated) { () -> (TornResponse?, MoneyData?, BattleStats?, [AttackResult]?, [PropertyInfo]?, [StockHolding], String?) in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, nil, nil, nil, nil, [], "Failed to parse response")
            }

            // Check for Torn API error (API returns HTTP 200 even on errors like rate limiting)
            if let errorMessage = tornAPIErrorMessage(in: json) {
                return (nil, nil, nil, nil, nil, [], "API Error: \(errorMessage)")
            }

            // Attempt to decode TornResponse first. Surface the decode failure class
            // (without dumping payload contents — that's PII) so silent decode failures
            // become diagnosable instead of vanishing into a "no data" state.
            let decodedTornResponse: TornResponse?
            do {
                decodedTornResponse = try JSONDecoder().decode(TornResponse.self, from: data)
            } catch let DecodingError.keyNotFound(key, ctx) {
                logger.error("TornResponse decode: missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                decodedTornResponse = nil
            } catch let DecodingError.typeMismatch(_, ctx) {
                logger.error("TornResponse decode: type mismatch at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                decodedTornResponse = nil
            } catch let DecodingError.valueNotFound(_, ctx) {
                logger.error("TornResponse decode: value not found at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                decodedTornResponse = nil
            } catch {
                logger.error("TornResponse decode failed: \(String(describing: type(of: error)))")
                decodedTornResponse = nil
            }
            
            // --- EXTENDED DATA ---
            
             // Money
            let cash = json["money_onhand"] as? Int ?? 0
            var vault = 0
            if let v = json["vault_amount"] as? Int { vault = v }
            else if let v = json["property_vault"] as? Int { vault = v }
            else if let moneyDict = json["money"] as? [String: Any] { vault = moneyDict["vault"] as? Int ?? 0 }
            
            let points = json["points"] as? Int ?? 0
            let tokens = json["donator"] as? Int ?? 0
            let cayman = json["cayman_bank"] as? Int ?? 0
            let moneyData = MoneyData(cash: cash, vault: vault, points: points, tokens: tokens, cayman: cayman)
            
            // Battle Stats
            let strength = json["strength"] as? Int ?? 0
            let defense = json["defense"] as? Int ?? 0
            let speed = json["speed"] as? Int ?? 0
            let dexterity = json["dexterity"] as? Int ?? 0
            let battleStats = BattleStats(strength: strength, defense: defense, speed: speed, dexterity: dexterity)
            
            // Attacks
            var attacksList: [AttackResult]?
            if let attacks = json["attacks"] as? [String: [String: Any]] {
                attacksList = attacks.values.compactMap { attackDict -> AttackResult? in
                    guard let code = attackDict["code"] as? String else { return nil }
                    return AttackResult(
                        code: code,
                        timestampStarted: attackDict["timestamp_started"] as? Int,
                        timestampEnded: attackDict["timestamp_ended"] as? Int,
                        attackerId: attackDict["attacker_id"] as? Int,
                        attackerName: attackDict["attacker_name"] as? String,
                        defenderId: attackDict["defender_id"] as? Int,
                        defenderName: attackDict["defender_name"] as? String,
                        result: attackDict["result"] as? String,
                        respect: attackDict["respect"] as? Double
                    )
                }.sorted(by: { ($0.timestampEnded ?? 0) > ($1.timestampEnded ?? 0) })
            }
            
            // Properties — Torn API: `rented` is null OR {user_id, days_left, cost_per_day}
            // `status` indicates residency ("Owned by them" = owned, not residing).
            // `upkeep`/`staff_cost` are per-day rates that only apply when residing — we don't surface them.
            var propertiesList: [PropertyInfo]?
            if let properties = json["properties"] as? [String: [String: Any]] {
                propertiesList = properties.values.compactMap { propDict -> PropertyInfo? in
                    let rentedDict = propDict["rented"] as? [String: Any]
                    return PropertyInfo(
                        id: propDict["property_id"] as? Int ?? 0,
                        propertyType: propDict["property"] as? String ?? "",
                        status: propDict["status"] as? String ?? "",
                        cost: propDict["cost"] as? Int ?? 0,
                        marketprice: propDict["marketprice"] as? Int ?? 0,
                        happy: propDict["happy"] as? Int ?? 0,
                        rented: rentedDict != nil,
                        rentDaysLeft: rentedDict?["days_left"] as? Int
                    )
                }
            }
            // Stocks
            var stocksList: [StockHolding] = []
            if let stocks = json["stocks"] as? [String: [String: Any]] {
                for (_, stockData) in stocks {
                    if let stockJSON = try? JSONSerialization.data(withJSONObject: stockData),
                       let stock = try? JSONDecoder().decode(StockHolding.self, from: stockJSON) {
                        stocksList.append(stock)
                    }
                }
            }

            // If we couldn't decode TornResponse, report error but continue with extended data
            let parseError: String? = (decodedTornResponse == nil) ? "Failed to decode user data" : nil

            return (decodedTornResponse, moneyData, battleStats, attacksList, propertiesList, stocksList, parseError)
        }.value

        await MainActor.run {
            // Check for parse errors
            if let parseError = result.6, result.0 == nil {
                self.errorMsg = parseError
                logger.error("Data error: \(parseError)")
                self.lastUpdated = Date() // Still update timestamp on error
                return
            }

            if let decoded = result.0 {
                // Don't log player name (identifying PII). State + life are non-identifying diagnostics.
                logger.info("Parsed data — Life: \(decoded.life?.current ?? -1)/\(decoded.life?.maximum ?? -1), State: \(decoded.status?.state ?? "nil")")
                if let events = decoded.events {
                    logger.info("Events count: \(events.count)")
                }

                self.checkNotifications(newData: decoded)
                self.data = decoded

                // Convert relative cooldown durations into absolute end-timestamps,
                // anchored on the server's response time so countdowns match torn.com
                // even if the Mac clock is skewed vs the Torn server.
                if let cooldowns = decoded.cooldowns {
                    let anchor = decoded.anchorTimestamp ?? Int(Date().timeIntervalSince1970)
                    let fresh = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
                    // Pin previous end-timestamps when the freshly computed values
                    // wobble by ≤3 s — that wobble is API/latency jitter, not a real
                    // change in expiry, and replacing endsAt would visibly jump the
                    // menu bar countdown on every poll.
                    self.cooldownEnds = self.cooldownEnds?.merged(with: fresh) ?? fresh
                } else {
                    self.cooldownEnds = nil
                }

                self.previousBars = decoded.bars
                self.previousCooldowns = decoded.cooldowns
                self.previousTravel = decoded.travel
                self.previousChain = decoded.chain
                self.previousStatus = decoded.status
            } else {
                logger.warning("TornResponse decoded as nil but no parse error reported")
            }

            if let m = result.1 { self.moneyData = m }
            if let b = result.2 { self.battleStats = b }
            if let a = result.3 { self.recentAttacks = a }
            if let p = result.4 { self.propertiesData = p }
            self.stocksData = result.5

            self.lastUpdated = Date()
            self.lastFetchTime = Date()
            self.errorMsg = nil

            // Manage live timer (travel + hospital + jail + cooldowns) after data is set
            self.manageLiveTimer()

            // Check if feedback prompt should be shown
            self.checkFeedbackPrompt()

            logger.info("Data updated, lastUpdated: \(self.lastUpdated?.description ?? "nil")")
        }
    }
    
    // MARK: - Fetch Faction Data
    private func fetchFactionData() async {
        guard let url = TornAPI.factionURL(for: apiKey) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await session.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for Torn API error first
                if let errorMessage = tornAPIErrorMessage(in: json) {
                    logger.warning("Faction API error: \(errorMessage)")
                    return
                }

                let name = json["name"] as? String ?? ""
                let factionId = json["ID"] as? Int ?? 0
                let respect = json["respect"] as? Int ?? 0

                var chain = FactionChain()
                if let chainDict = json["chain"] as? [String: Any] {
                    chain = FactionChain(
                        current: chainDict["current"] as? Int ?? 0,
                        max: chainDict["max"] as? Int ?? 0,
                        timeout: chainDict["timeout"] as? Int ?? 0,
                        cooldown: chainDict["cooldown"] as? Int ?? 0
                    )
                }

                // Organized crime moved to `fetchUserV2Data` (own OC 2.0). The v1
                // `crimes` selection is dead (frozen OC-1.0 history only).

                self.factionData = FactionData(name: name, factionId: factionId, respect: respect, chain: chain)
                logger.info("Faction data fetched: \(name)")
            }
        } catch {
            logger.warning("Faction fetch error (optional): \(error.localizedDescription)")
            // Faction data is optional, ignore errors
        }
    }

    // MARK: - Fetch API v2 User Data (organized crime, refills, education, bounties)
    //
    // One combined v2 call (v2 accepts multiple selections). Each section is decoded
    // independently so a malformed/absent one never drops the others. Payload is small
    // (~2 KB), so decoding on the main actor is fine — same pattern as fetchFactionData.
    private func fetchUserV2Data() async {
        guard !apiKey.isEmpty, let url = TornAPI.userV2URL(for: apiKey) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await session.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let errorMessage = tornAPIErrorMessage(in: json) {
                logger.warning("User v2 API error: \(errorMessage)")
                return
            }

            let decoder = JSONDecoder()

            // Organized crime — `organizedCrime` is oneOf(object | error | null).
            // Only a well-formed object carrying an Int `id` is a real active OC.
            var oc: OrganizedCrime2?
            if let ocDict = json["organizedCrime"] as? [String: Any], ocDict["id"] is Int,
               let ocData = try? JSONSerialization.data(withJSONObject: ocDict) {
                oc = try? decoder.decode(OrganizedCrime2.self, from: ocData)
            }
            self.organizedCrime = oc

            if let rDict = json["refills"] as? [String: Any],
               let rData = try? JSONSerialization.data(withJSONObject: rDict) {
                self.refills = try? decoder.decode(Refills.self, from: rData)
            }

            if let eDict = json["education"] as? [String: Any],
               let eData = try? JSONSerialization.data(withJSONObject: eDict) {
                self.education = try? decoder.decode(EducationStatus.self, from: eData)
            }

            // `/user?selections=bounties` is scoped to the authenticated player, so
            // every returned bounty is a bounty ON Paweł.
            if let bArr = json["bounties"] as? [[String: Any]],
               let bData = try? JSONSerialization.data(withJSONObject: bArr) {
                self.bountiesOnMe = (try? decoder.decode([Bounty].self, from: bData)) ?? []
            } else {
                self.bountiesOnMe = []
            }

            // OC-ready notification: fire once per OC as it crosses its ready time.
            if let oc, oc.isReady {
                if previousOCReadyId != oc.id {
                    NotificationManager.shared.send(
                        title: "OC Ready! 💼",
                        body: "\(oc.name) is ready to execute",
                        type: .ocReady
                    )
                }
                previousOCReadyId = oc.id
            } else {
                previousOCReadyId = nil
            }

            notifyBountiesOnMe()

            logger.info("User v2 data fetched (OC: \(oc?.name ?? "none"), bounties: \(self.bountiesOnMe.count))")
        } catch {
            logger.warning("User v2 fetch error (optional): \(error.localizedDescription)")
        }
    }

    /// Alerts once per distinct bounty placed on Paweł (safety signal). Re-remembers
    /// only the bounties still active, so a bounty that's cleared and re-listed alerts again.
    private func notifyBountiesOnMe() {
        let currentKeys = Set(bountiesOnMe.map(\.id))
        for bounty in bountiesOnMe where !notifiedBountyKeys.contains(bounty.id) {
            let amount = Self.decimalFormatter.string(from: NSNumber(value: bounty.reward)) ?? "\(bounty.reward)"
            let who: String
            if bounty.isAnonymous == true {
                who = " (anonymous)"
            } else if let name = bounty.listerName {
                who = " from \(name)"
            } else {
                who = ""
            }
            NotificationManager.shared.send(
                title: "⚠️ Bounty on you",
                body: "$\(amount)\(who)",
                type: .bountyOnMe
            )
        }
        notifiedBountyKeys = currentKeys
    }

    static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    // MARK: - Fetch API v2 Faction Data (ranked wars, news)
    //
    // Dedicated v2 paths: the combined `?selections=rankedwars,news` call fails with
    // code 21 because `news` needs a `cat` parameter. Both are optional overlays.
    private func fetchFactionV2Data() async {
        guard !apiKey.isEmpty else { return }

        if let url = TornAPI.factionRankedWarsURL(for: apiKey),
           let wars: [RankedWar] = await fetchV2Array(url: url, key: "rankedwars") {
            self.rankedWars = wars
        }

        if let url = TornAPI.factionNewsURL(for: apiKey),
           let news: [FactionNews] = await fetchV2Array(url: url, key: "news") {
            self.factionNews = news
        }
    }

    /// Fetches a v2 endpoint whose payload is `{ "<key>": [ … ] }` and decodes the
    /// array. Returns nil on network/API error so the caller keeps its prior value.
    private func fetchV2Array<T: Decodable>(url: URL, key: String) async -> [T]? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await session.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let errorMessage = tornAPIErrorMessage(in: json) {
                logger.warning("Faction v2 (\(key)) API error: \(errorMessage)")
                return nil
            }
            guard let arr = json[key] as? [[String: Any]],
                  let arrData = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
            return try? JSONDecoder().decode([T].self, from: arrData)
        } catch {
            logger.warning("Faction v2 (\(key)) fetch error (optional): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Notifications
    private func checkNotifications(newData: TornResponse) {
        if let prev = previousBars, let current = newData.bars {
            checkBarNotification(prevBar: prev.energy, currentBar: current.energy, barType: .energy)
            checkBarNotification(prevBar: prev.nerve, currentBar: current.nerve, barType: .nerve)
            checkBarNotification(prevBar: prev.happy, currentBar: current.happy, barType: .happy)
            checkBarNotification(prevBar: prev.life, currentBar: current.life, barType: .life)
        }
        
        if let prevCD = previousCooldowns, let currentCD = newData.cooldowns {
            if prevCD.drug > 0 && currentCD.drug == 0 {
                NotificationManager.shared.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended", type: .drugReady)
            }
            if prevCD.medical > 0 && currentCD.medical == 0 {
                NotificationManager.shared.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended", type: .medicalReady)
            }
            if prevCD.booster > 0 && currentCD.booster == 0 {
                NotificationManager.shared.send(title: "Booster Ready! 🚀", body: "Booster cooldown has ended", type: .boosterReady)
            }
        }
        
        if let prevTravel = previousTravel, let currentTravel = newData.travel {
            // Just landed
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(title: "Landed!", body: "You have arrived in \(currentTravel.destination ?? "destination")", type: .landed)
                NotificationManager.shared.cancelTravelNotifications()
            }
            // Just started traveling
            if !prevTravel.isTraveling && currentTravel.isTraveling {
                scheduleTravelNotifications(for: currentTravel)
            }
        } else if let currentTravel = newData.travel, currentTravel.isTraveling, previousTravel == nil {
            // First data fetch while traveling
            scheduleTravelNotifications(for: currentTravel)
        }
        
        if let chain = newData.chain, chain.isActive {
            if chain.timeoutRemaining < 60 && chain.timeoutRemaining > 0 {
                NotificationManager.shared.send(title: "Chain Expiring! ⚠️", body: "Chain timeout in \(chain.timeoutRemaining) seconds!", type: .chainExpiring)
            }
        }
        
        if let prevStatus = previousStatus, let currentStatus = newData.status {
            if (prevStatus.isInHospital || prevStatus.isInJail) && currentStatus.isOkay {
                NotificationManager.shared.send(title: "Released! 🎉", body: "You are now free", type: .released)
            }
        }
    }
    
    private func checkBarNotification(prevBar: Bar, currentBar: Bar, barType: NotificationRule.BarType) {
        let prevPct = prevBar.percentage
        let currentPct = currentBar.percentage

        for rule in notificationRules where rule.enabled && rule.barType == barType {
            let threshold = Double(rule.threshold)

            if prevPct < threshold && currentPct >= threshold {
                let title: String
                let notificationType: NotificationType
                switch barType {
                case .energy:
                    title = "Energy \(rule.threshold)%! ⚡️"
                    notificationType = .energy
                case .nerve:
                    title = "Nerve \(rule.threshold)%! 💪"
                    notificationType = .nerve
                case .happy:
                    title = "Happy \(rule.threshold)%! 😊"
                    notificationType = .happy
                case .life:
                    title = "Life \(rule.threshold)%! ❤️"
                    notificationType = .life
                }
                NotificationManager.shared.send(title: title, body: "\(barType.rawValue) is now at \(currentBar.current)/\(currentBar.maximum)", type: notificationType)

                if let sound = NotificationSound(rawValue: rule.soundName) {
                    SoundManager.shared.play(sound)
                }
            }
        }
    }
    
    // MARK: - Updates
    func checkForAppUpdates() {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        Task {
            if let release = await updateManager.checkForUpdates(currentVersion: currentVersion) {
                await MainActor.run {
                    self.updateAvailable = release
                }
            }
        }
    }

    // MARK: - Feedback Prompt

    func loadFeedbackState() {
        if let data = UserDefaults.standard.data(forKey: "appFeedbackState"),
           let state = try? JSONDecoder().decode(AppFeedbackState.self, from: data) {
            feedbackState = state
        } else {
            feedbackState = AppFeedbackState(
                firstLaunchDate: Date(),
                hasResponded: false,
                dismissCount: 0,
                lastDismissedDate: nil
            )
            saveFeedbackState()
        }
    }

    func saveFeedbackState() {
        guard let state = feedbackState,
              let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: "appFeedbackState")
    }

    func checkFeedbackPrompt() {
        guard let state = feedbackState else { return }
        guard !state.hasResponded else { return }
        guard state.dismissCount < Self.feedbackThresholds.count else { return }

        // 5-minute cooldown after last dismissal
        if let lastDismissed = state.lastDismissedDate,
           Date().timeIntervalSince(lastDismissed) < 300 {
            return
        }

        let elapsed = Date().timeIntervalSince(state.firstLaunchDate)
        let requiredTime = Self.feedbackThresholds[state.dismissCount]

        if elapsed >= requiredTime {
            showFeedbackPrompt = true
        }
    }

    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    func feedbackRespondedPositive() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
        // Guard prevents tests from spamming the user's browser/mail client.
        guard !Self.isRunningUnderXCTest else { return }
        if let url = URL(string: "https://www.torn.com/forums.php#/p=threads&f=67&t=16532308") {
            BrowserManager.shared.open(url)
        }
    }

    func feedbackRespondedNegative() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
        guard !Self.isRunningUnderXCTest else { return }
        if let url = URL(string: "mailto:pawel@orzech.lol?subject=MacTorn%20Feedback") {
            BrowserManager.shared.open(url)
        }
    }

    func feedbackDismissed() {
        feedbackState?.dismissCount += 1
        feedbackState?.lastDismissedDate = Date()
        showFeedbackPrompt = false
        saveFeedbackState()
    }
}

// MARK: - Errors
enum APIError: Error {
    case invalidResponse
    case invalidData
}
