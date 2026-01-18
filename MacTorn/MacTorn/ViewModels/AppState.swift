import Foundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.mactorn", category: "AppState")

@MainActor
class AppState: ObservableObject {
    // MARK: - Persisted
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("refreshInterval") var refreshInterval: Int = 30

    // MARK: - Published State
    @Published var data: TornResponse?
    @Published var lastUpdated: Date?
    @Published var errorMsg: String?
    @Published var isLoading: Bool = false
    @Published var notificationRules: [NotificationRule] = []

    // MARK: - New Data Sources
    @Published var moneyData: MoneyData?
    @Published var battleStats: BattleStats?
    @Published var recentAttacks: [AttackResult]?
    @Published var factionData: FactionData?
    @Published var propertiesData: [PropertyInfo]?
    @Published var watchlistItems: [WatchlistItem] = []

    // MARK: - Update State
    @Published var updateAvailable: GitHubRelease?

    // MARK: - Managers
    let launchAtLogin = LaunchAtLoginManager()
    let shortcutsManager = ShortcutsManager()
    let updateManager = UpdateManager.shared

    // MARK: - Networking (Dependency Injection for Testing)
    private let session: NetworkSession

    // MARK: - State Comparison
    private var previousBars: Bars?
    private var previousCooldowns: Cooldowns?
    private var previousTravel: Travel?
    private var previousChain: Chain?
    private var previousStatus: Status?

    // MARK: - Timer
    private var timerCancellable: AnyCancellable?

    init(session: NetworkSession = URLSession.shared) {
        self.session = session
        loadNotificationRules()
        loadWatchlist()
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
        Task {
            await fetchWatchlistPrices()
        }
    }
    
    private func fetchWatchlistPrices() async {
        for item in watchlistItems {
            await fetchItemPrice(itemId: item.id)
        }
    }
    
    private func fetchItemPrice(itemId: Int) async {
        guard !apiKey.isEmpty,
              let url = TornAPI.marketURL(itemId: itemId, apiKey: apiKey) else { return }

        logger.info("Fetching price for item \(itemId)")

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                logger.error("Item \(itemId) HTTP Error: \(httpResponse.statusCode)")
                await updateItemError(itemId: itemId, error: "HTTP \(httpResponse.statusCode)")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Check if API returned error
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
                    logger.warning("Item \(itemId) API error: \(errorText)")
                    await updateItemError(itemId: itemId, error: errorText)
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
                
                await MainActor.run {
                    if let index = watchlistItems.firstIndex(where: { $0.id == itemId }) {
                         if let best = sortedListings.first {
                            watchlistItems[index].lowestPrice = best.price
                            watchlistItems[index].lowestPriceQuantity = best.amount
                            
                            // Check for next distinct price or just next listing? usually user wants to know diff to next cheapest offer even if it's same price? 
                            // Actually "second lowest price" usually implies the price of the *next available item*.
                            // But usually users want to know price steps. 
                            // Let's stick to simple logic: price of the 2nd listing in sorted list.
                            watchlistItems[index].secondLowestPrice = sortedListings.count > 1 ? sortedListings[1].price : 0
                            
                            watchlistItems[index].lastUpdated = Date()
                            watchlistItems[index].error = nil
                         } else {
                            watchlistItems[index].error = "No listings"
                         }
                        saveWatchlist()
                    }
                }
            }
        } catch {
            logger.error("Item \(itemId) price fetch error: \(error.localizedDescription)")
            await updateItemError(itemId: itemId, error: "Network Error")
        }
    }
    
    @MainActor
    private func updateItemError(itemId: Int, error: String) {
        if let index = watchlistItems.firstIndex(where: { $0.id == itemId }) {
            watchlistItems[index].error = error
            saveWatchlist()
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
        fetchData()
    }
    
    // MARK: - Fetch Data
    func fetchData() {
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

        Task {
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
                        logger.info("Raw API response: \(jsonString.prefix(500))")
                    }

                    // Check for Torn API error in response (API returns 200 even on errors)
                    if let tornError = checkForTornAPIError(data: data) {
                        await MainActor.run {
                            self.errorMsg = tornError
                        }
                        logger.error("Torn API error: \(tornError)")
                        return
                    }

                    // Parse on background thread
                    try await parseDataInBackground(data: data)

                    // Fetch faction data separately
                    await fetchFactionData()

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
                await MainActor.run {
                    self.errorMsg = "Network error: \(error.localizedDescription)"
                }
                logger.error("Network error: \(error.localizedDescription)")
            }
        }
    }

    /// Check if Torn API returned an error (API returns HTTP 200 even on errors like rate limiting)
    private func checkForTornAPIError(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let errorMessage = error["error"] as? String else {
            return nil
        }

        let errorCode = error["code"] as? Int ?? 0
        logger.warning("Torn API error code \(errorCode): \(errorMessage)")
        return "API Error: \(errorMessage)"
    }
    
    // Move parsing logic here and mark as non-isolated or detached
    private func parseDataInBackground(data: Data) async throws {
        // Run CPU-heavy parsing detached from MainActor
        let result = await Task.detached(priority: .userInitiated) { () -> (TornResponse?, MoneyData?, BattleStats?, [AttackResult]?, [PropertyInfo]?, String?) in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, nil, nil, nil, nil, "Failed to parse response")
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
                        opponentId: attackDict["defender_id"] as? Int,
                        opponentName: attackDict["defender_name"] as? String,
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
                logger.error("Parse error: \(parseError)")
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
            self.errorMsg = nil

            // Force UI update by triggering objectWillChange
            self.objectWillChange.send()
            logger.info("UI update triggered, lastUpdated: \(self.lastUpdated?.description ?? "nil")")
        }
    }
    
    // MARK: - Fetch Faction Data
    private func fetchFactionData() async {
        guard let url = TornAPI.factionURL(for: apiKey) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await session.data(for: request)

            // Check for Torn API error
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let errorMessage = error["error"] as? String {
                logger.warning("Faction API error: \(errorMessage)")
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(title: "Landed! ✈️", body: "You have arrived in \(currentTravel.destination ?? "destination")", type: .landed)
            }
        }
        
        if let chain = newData.chain, chain.isActive {
            if chain.timeoutRemaining < 60 && chain.timeoutRemaining > 0 {
                NotificationManager.shared.send(title: "Chain Expiring! ⚠️", body: "Chain timeout in \(chain.timeoutRemaining) seconds!", type: .chainExpiring)
            }
        }
        
        if let prevStatus = previousStatus, let currentStatus = newData.status {
            if !prevStatus.isOkay && currentStatus.isOkay {
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
}

// MARK: - Errors
enum APIError: Error {
    case invalidResponse
    case invalidData
}
