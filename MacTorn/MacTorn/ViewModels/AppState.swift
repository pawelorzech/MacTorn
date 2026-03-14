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
    @Published var watchlistItems: [WatchlistItem] = []

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

    // MARK: - Task Handles (for deduplication)
    private var fetchTask: Task<Void, Never>?
    private var watchlistTask: Task<Void, Never>?

    // MARK: - Timer
    private var timerCancellable: AnyCancellable?

    init(session: NetworkSession = URLSession.shared, connectivity: NetworkConnectivity = NetworkMonitor.shared) {
        self.session = session
        self.connectivity = connectivity
        loadNotificationRules()
        loadTravelNotificationSettings()
        loadWatchlist()
        loadFeedbackState()
        // Polling and permissions moved to onAppear in UI
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
                await updateItemError(itemId: itemId, error: "HTTP \(httpResponse.statusCode)", save: save)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Check if API returned error
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
                    logger.warning("Item \(itemId) API error: \(errorText)")
                    await updateItemError(itemId: itemId, error: errorText, save: save)
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
                    await updateItemPrice(itemId: itemId, lowestPrice: best.price, lowestPriceQuantity: best.amount, secondLowestPrice: secondPrice, save: save)
                } else {
                    await updateItemError(itemId: itemId, error: "No listings", save: save)
                }
            } else {
                logger.error("Item \(itemId): failed to parse JSON response")
                await updateItemError(itemId: itemId, error: "Parse Error", save: save)
            }
        } catch {
            if Task.isCancelled { return }
            logger.error("Item \(itemId) price fetch error: \(error.localizedDescription)")
            await updateItemError(itemId: itemId, error: "Network Error", save: save)
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
            if save { saveWatchlist() }
        }
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
    
    // MARK: - Polling
    func startPolling() {
        timerCancellable?.cancel()
        fetchData()
        timerCancellable = Timer.publish(every: Double(refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchData()
            }
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
        let result = await Task.detached(priority: .userInitiated) { () -> (TornResponse?, MoneyData?, BattleStats?, [AttackResult]?, [PropertyInfo]?, String?) in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, nil, nil, nil, nil, "Failed to parse response")
            }

            // Check for Torn API error (API returns HTTP 200 even on errors like rate limiting)
            if let apiError = json["error"] as? [String: Any],
               let errorMessage = apiError["error"] as? String {
                return (nil, nil, nil, nil, nil, "API Error: \(errorMessage)")
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
            
            // Properties
            var propertiesList: [PropertyInfo]?
            if let properties = json["properties"] as? [String: [String: Any]] {
                propertiesList = properties.values.compactMap { propDict -> PropertyInfo? in
                    return PropertyInfo(
                        id: propDict["property_id"] as? Int ?? 0,
                        propertyType: propDict["property"] as? String ?? "",
                        vault: propDict["money"] as? Int ?? 0,
                        upkeep: propDict["upkeep"] as? Int ?? 0,
                        rented: propDict["rented"] as? Bool ?? false,
                        daysUntilUpkeep: propDict["days_left"] as? Int ?? 0
                    )
                }
            }
            // If we couldn't decode TornResponse, report error but continue with extended data
            let parseError: String? = (decodedTornResponse == nil) ? "Failed to decode user data" : nil

            return (decodedTornResponse, moneyData, battleStats, attacksList, propertiesList, parseError)
        }.value

        await MainActor.run {
            // Check for parse errors
            if let parseError = result.5, result.0 == nil {
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

    func feedbackRespondedPositive() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
        if let url = URL(string: "https://www.torn.com/forums.php#/p=threads&f=67&t=16532308") {
            BrowserManager.shared.open(url)
        }
    }

    func feedbackRespondedNegative() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
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
