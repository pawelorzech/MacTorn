import Foundation
import Combine
import SwiftUI

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
    
    // MARK: - State Comparison
    private var previousBars: Bars?
    private var previousCooldowns: Cooldowns?
    private var previousTravel: Travel?
    private var previousChain: Chain?
    private var previousStatus: Status?
    
    // MARK: - Timer
    private var timerCancellable: AnyCancellable?
    
    init() {
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
        
        // Debug
        // print("Fetching price for item \(itemId): \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // print("HTTP Error: \(httpResponse.statusCode)")
                await updateItemError(itemId: itemId, error: "HTTP \(httpResponse.statusCode)")
                return
            }
            
            // Debug JSON
            // if let str = String(data: data, encoding: .utf8) {
            //     print("Market JSON: \(str)")
            // }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // Check if API returned error
                if let error = json["error"] as? [String: Any], let errorText = error["error"] as? String {
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
                // print("Found \(sortedListings.count) listings for item \(itemId). Lowest: \(sortedListings.first?.price ?? 0)")
                
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
            // print("Price fetch error: \(error)")
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
            return
        }
        
        guard let url = TornAPI.url(for: apiKey) else {
            errorMsg = "Invalid URL"
            return
        }
        
        isLoading = true
        errorMsg = nil
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    // Parse on background thread
                    try await parseDataInBackground(data: data)
                    
                    // Fetch faction data separately
                    await fetchFactionData()
                    
                case 403, 404:
                    await MainActor.run {
                        self.errorMsg = "Invalid API Key"
                        self.data = nil
                        self.isLoading = false
                    }
                default:
                    await MainActor.run {
                        self.errorMsg = "HTTP Error: \(httpResponse.statusCode)"
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // Move parsing logic here and mark as non-isolated or detached
    private func parseDataInBackground(data: Data) async throws {
        // Run CPU-heavy parsing detached from MainActor
        let result = await Task.detached(priority: .userInitiated) { () -> (TornResponse?, MoneyData?, BattleStats?, [AttackResult]?, [PropertyInfo]?) in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, nil, nil, nil, nil)
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
            return (decodedTornResponse, moneyData, battleStats, attacksList, propertiesList)
        }.value
        
        await MainActor.run {
            if let decoded = result.0 {
                self.checkNotifications(newData: decoded)
                self.data = decoded
                
                self.previousBars = decoded.bars
                self.previousCooldowns = decoded.cooldowns
                self.previousTravel = decoded.travel
                self.previousChain = decoded.chain
                self.previousStatus = decoded.status
            }
            
            if let m = result.1 { self.moneyData = m }
            if let b = result.2 { self.battleStats = b }
            if let a = result.3 { self.recentAttacks = a }
            if let p = result.4 { self.propertiesData = p }
            
            self.lastUpdated = Date()
            self.isLoading = false
            self.errorMsg = nil
        }
    }
    
    // MARK: - Fetch Faction Data
    private func fetchFactionData() async {
        guard let url = TornAPI.factionURL(for: apiKey) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
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
            }
        } catch {
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
                NotificationManager.shared.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended")
            }
            if prevCD.medical > 0 && currentCD.medical == 0 {
                NotificationManager.shared.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended")
            }
            if prevCD.booster > 0 && currentCD.booster == 0 {
                NotificationManager.shared.send(title: "Booster Ready! 🚀", body: "Booster cooldown has ended")
            }
        }
        
        if let prevTravel = previousTravel, let currentTravel = newData.travel {
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(title: "Landed! ✈️", body: "You have arrived in \(currentTravel.destination ?? "destination")")
            }
        }
        
        if let chain = newData.chain, chain.isActive {
            if chain.timeoutRemaining < 60 && chain.timeoutRemaining > 0 {
                NotificationManager.shared.send(title: "Chain Expiring! ⚠️", body: "Chain timeout in \(chain.timeoutRemaining) seconds!")
            }
        }
        
        if let prevStatus = previousStatus, let currentStatus = newData.status {
            if !prevStatus.isOkay && currentStatus.isOkay {
                NotificationManager.shared.send(title: "Released! 🎉", body: "You are now free")
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
                switch barType {
                case .energy: title = "Energy \(rule.threshold)%! ⚡️"
                case .nerve: title = "Nerve \(rule.threshold)%! 💪"
                case .happy: title = "Happy \(rule.threshold)%! 😊"
                case .life: title = "Life \(rule.threshold)%! ❤️"
                }
                NotificationManager.shared.send(title: title, body: "\(barType.rawValue) is now at \(currentBar.current)/\(currentBar.maximum)")
                
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
