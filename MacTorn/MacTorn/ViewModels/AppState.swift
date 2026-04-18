import Foundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "AppState")

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
class AppState: ObservableObject {
    // MARK: - Persisted
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("refreshInterval") var refreshInterval: Int = 30
    @AppStorage("appearanceMode") var appearanceMode: String = AppearanceMode.system.rawValue

    // MARK: - Published State
    @Published var data: TornResponse?
    @Published var lastUpdated: Date?
    @Published var errorMsg: String?
    @Published var isLoading: Bool = false
    @Published var notificationRules: [NotificationRule] = []
    @Published var travelNotificationSettings: [TravelNotificationSetting] = []

    // MARK: - New Data Sources
    @Published var moneyData: MoneyData?
    @Published var battleStats: BattleStats?
    @Published var recentAttacks: [AttackResult]?
    @Published var factionData: FactionData?
    @Published var propertiesData: [PropertyInfo]?
    @Published var stocksData: [StockHolding] = []
    @Published var stocksMetadata: [Int: StockMetadata] = [:]
    @Published var watchlistItems: [WatchlistItem] = []
    @Published var organizedCrimes: [OrganizedCrime] = []
    @Published var watchedThreads: [WatchedThread] = []
    @Published var forumWatchConfig: ForumWatchConfig = ForumWatchConfig()

    // MARK: - Update State
    @Published var updateAvailable: GitHubRelease?

    // MARK: - Feedback State
    @Published var feedbackState: AppFeedbackState?
    @Published var showFeedbackPrompt: Bool = false
    static let feedbackThresholds: [TimeInterval] = [3600, 7 * 86400, 30 * 86400]

    // MARK: - Fetch Time (for live countdown calculations)
    @Published var lastFetchTime: Date = Date()

    // MARK: - Live Travel Countdown
    @Published var travelSecondsRemaining: Int = 0
    private var travelTimerCancellable: AnyCancellable?

    // MARK: - Managers
    let launchAtLogin = LaunchAtLoginManager()
    let shortcutsManager = ShortcutsManager()
    let updateManager = UpdateManager.shared

    // MARK: - Networking (Dependency Injection for Testing)
    private let session: NetworkSession
    private let connectivity: NetworkConnectivity

    // MARK: - State Comparison
    private var previousBars: Bars?
    private var previousCooldowns: Cooldowns?
    private var previousTravel: Travel?
    private var previousChain: Chain?
    private var previousStatus: Status?
    private var previousOCReady: Set<Int> = []

    // MARK: - Task Handles (for deduplication)
    private var fetchTask: Task<Void, Never>?
    private var watchlistTask: Task<Void, Never>?
    private var forumFetchTask: Task<Void, Never>?

    // MARK: - Timer
    private var timerCancellable: AnyCancellable?
    private var forumTimerCancellable: AnyCancellable?

    private static let stocksMetadataCacheKey = "stocksMetadataCache"

    init(session: NetworkSession = URLSession.shared, connectivity: NetworkConnectivity? = nil) {
        self.session = session
        self.connectivity = connectivity ?? NetworkMonitor.shared
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
            guard !parsed.isEmpty else { return }
            await MainActor.run {
                self.stocksMetadata = parsed
                if let encoded = try? JSONEncoder().encode(parsed) {
                    UserDefaults.standard.set(encoded, forKey: Self.stocksMetadataCacheKey)
                }
                logger.info("Stocks metadata loaded: \(parsed.count) stocks")
            }
        } catch {
            logger.error("Failed to fetch stocks metadata: \(error.localizedDescription)")
        }
    }

    /// Parses the `torn/?selections=stocks` response using JSONSerialization (resilient to extra fields).
    /// Exposed as a static func so tests can drive it without a network round-trip.
    nonisolated static func parseStocksMetadata(from data: Data, logger: Logger) -> [Int: StockMetadata] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Stocks metadata: failed to parse JSON")
            return [:]
        }
        if let apiError = json["error"] as? [String: Any], let msg = apiError["error"] as? String {
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

    // MARK: - Live Travel Timer
    func manageTravelTimer() {
        if let travel = data?.travel, travel.isTraveling {
            // Start or continue timer
            updateTravelSecondsRemaining()
            if travelTimerCancellable == nil {
                startTravelTimer()
            }
        } else {
            // Stop timer when not traveling
            stopTravelTimer()
        }
    }

    private func startTravelTimer() {
        travelTimerCancellable?.cancel()

        travelTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTravelSecondsRemaining()
            }
    }

    private func stopTravelTimer() {
        travelTimerCancellable?.cancel()
        travelTimerCancellable = nil
        travelSecondsRemaining = 0
    }

    private func updateTravelSecondsRemaining() {
        guard let travel = data?.travel, travel.isTraveling else {
            travelSecondsRemaining = 0
            return
        }
        travelSecondsRemaining = travel.remainingSeconds(from: lastFetchTime)
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
        let item = WatchlistItem(id: itemId, name: name, lowestPrice: 0, lowestPriceQuantity: 0, secondLowestPrice: 0, lastUpdated: nil, error: nil)
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
    
    private func fetchWatchlistPrices() async {
        guard connectivity.isConnected else { return }
        await withTaskGroup(of: Void.self) { group in
            for item in watchlistItems {
                group.addTask { await self.fetchItemPrice(itemId: item.id, save: false) }
            }
        }
        saveWatchlist()
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
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
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
                let priceString = formatAlertPrice(lowestPrice)
                NotificationManager.shared.send(
                    title: "Price Alert: \(item.name)",
                    body: "Lowest price dropped to \(priceString)",
                    type: .priceAlert
                )
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
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
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
                        self.watchedThreads[index].title = title
                        self.watchedThreads[index].lastChecked = Date()
                        self.watchedThreads[index].error = nil

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
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
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
    func startPolling() {
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
        Task { await self.fetchStocksMetadata() }
    }
    
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    func refreshNow() {
        startPolling()
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

        logger.info("Starting data fetch from: \(url.absoluteString.prefix(80))...")

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
                    // Log raw JSON for debugging (first 500 chars)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.debug("Raw API response: \(jsonString.prefix(500))")
                    }

                    // Parse user data and fetch faction data in parallel
                    async let factionResult: Void = self.fetchFactionData()
                    try await parseDataInBackground(data: data)
                    await factionResult

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
            if let apiError = json["error"] as? [String: Any],
               let errorMessage = apiError["error"] as? String {
                return (nil, nil, nil, nil, nil, [], "API Error: \(errorMessage)")
            }

            // Attempt to decode TornResponse first
            let decodedTornResponse = try? JSONDecoder().decode(TornResponse.self, from: data)
            
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
                logger.info("Parsed data - Name: \(decoded.name ?? "nil"), Life: \(decoded.life?.current ?? -1)/\(decoded.life?.maximum ?? -1)")
                logger.info("Status: \(decoded.status?.description ?? "nil"), State: \(decoded.status?.state ?? "nil")")
                if let events = decoded.events {
                    logger.info("Events count: \(events.count)")
                }

                self.checkNotifications(newData: decoded)
                self.data = decoded

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

            // Manage travel timer after data is set
            self.manageTravelTimer()

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
                if let error = json["error"] as? [String: Any],
                   let errorMessage = error["error"] as? String {
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

                // Parse Organized Crimes
                var crimes: [OrganizedCrime] = []
                if let crimesDict = json["crimes"] as? [String: [String: Any]] {
                    for (_, crimeData) in crimesDict {
                        if let crimeJSON = try? JSONSerialization.data(withJSONObject: crimeData),
                           let crime = try? JSONDecoder().decode(OrganizedCrime.self, from: crimeJSON) {
                            crimes.append(crime)
                        }
                    }
                }
                self.organizedCrimes = crimes.sorted { $0.timeReady < $1.timeReady }

                // Check for OC ready notifications
                for crime in crimes where crime.isReady {
                    if !previousOCReady.contains(crime.crimeId) {
                        NotificationManager.shared.send(
                            title: "OC Ready! 💼",
                            body: "\(crime.crimeName) is ready to initiate",
                            type: .ocReady
                        )
                    }
                }
                previousOCReady = Set(crimes.filter { $0.isReady }.map { $0.crimeId })

                self.factionData = FactionData(name: name, factionId: factionId, respect: respect, chain: chain)
                logger.info("Faction data fetched: \(name)")
            }
        } catch {
            logger.warning("Faction fetch error (optional): \(error.localizedDescription)")
            // Faction data is optional, ignore errors
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
