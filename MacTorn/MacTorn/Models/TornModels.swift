import Foundation
import SwiftUI

// MARK: - Root Response
struct TornResponse: Codable {
    let name: String?
    let playerId: Int?
    let energy: Bar?
    let nerve: Bar?
    let life: Bar?
    let happy: Bar?
    let cooldowns: Cooldowns?
    let travel: Travel?
    let status: Status?
    let chain: Chain?
    let events: [String: TornEvent]?
    let messages: [String: TornMessage]?
    let error: TornError?
    
    enum CodingKeys: String, CodingKey {
        case name
        case playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, status, chain
        case events, messages, error
    }
    
    // Convenience computed property
    var bars: Bars? {
        guard let energy = energy,
              let nerve = nerve,
              let life = life,
              let happy = happy else { return nil }
        return Bars(energy: energy, nerve: nerve, life: life, happy: happy)
    }
    
    // Unread messages count
    var unreadMessagesCount: Int {
        messages?.values.filter { $0.read == 0 }.count ?? 0
    }
    
    // Recent events sorted
    var recentEvents: [TornEvent] {
        guard let events = events else { return [] }
        return events.values.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Bars
struct Bar: Codable, Equatable {
    let current: Int
    let maximum: Int
    let increment: Double?
    let interval: Int?
    let ticktime: Int?
    let fulltime: Int?
    
    init(current: Int, maximum: Int, increment: Double? = nil, interval: Int? = nil, ticktime: Int? = nil, fulltime: Int? = nil) {
        self.current = current
        self.maximum = maximum
        self.increment = increment
        self.interval = interval
        self.ticktime = ticktime
        self.fulltime = fulltime
    }
    
    var percentage: Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum) * 100
    }
}

struct Bars: Equatable {
    let energy: Bar
    let nerve: Bar
    let life: Bar
    let happy: Bar
}

// MARK: - Cooldowns
struct Cooldowns: Codable, Equatable {
    let drug: Int
    let medical: Int
    let booster: Int
}

// MARK: - Travel
struct Travel: Codable, Equatable {
    let destination: String?
    let timestamp: Int?
    let departed: Int?
    let timeLeft: Int?
    
    enum CodingKeys: String, CodingKey {
        case destination
        case timestamp
        case departed
        case timeLeft = "time_left"
    }
    
    var isAbroad: Bool {
        guard let dest = destination, let time = timeLeft else { return false }
        return dest != "Torn" && time == 0
    }
    
    var isTraveling: Bool {
        guard let time = timeLeft else { return false }
        return time > 0
    }
    
    var arrivalDate: Date? {
        guard isTraveling, let ts = timestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }
}

// MARK: - Status (Hospital/Jail)
struct Status: Codable, Equatable {
    let description: String?
    let details: String?
    let state: String?
    let until: Int?
    
    var isInHospital: Bool {
        state == "Hospital"
    }
    
    var isInJail: Bool {
        state == "Jail"
    }
    
    var isOkay: Bool {
        state == "Okay" || state == nil
    }
    
    var timeRemaining: Int {
        guard let until = until else { return 0 }
        return max(0, until - Int(Date().timeIntervalSince1970))
    }
}

// MARK: - Chain
struct Chain: Codable, Equatable {
    let current: Int?
    let maximum: Int?
    let timeout: Int?
    let cooldown: Int?
    
    var isActive: Bool {
        guard let current = current, let timeout = timeout else { return false }
        return current > 0 && timeout > 0
    }
    
    var isOnCooldown: Bool {
        guard let cooldown = cooldown else { return false }
        return cooldown > 0
    }
    
    var timeoutRemaining: Int {
        guard let timeout = timeout else { return 0 }
        return max(0, timeout - Int(Date().timeIntervalSince1970))
    }
}

// MARK: - Events
struct TornEvent: Codable, Identifiable {
    let timestamp: Int
    let event: String
    let seen: Int?
    
    var id: Int { timestamp }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    // Strip HTML tags from event text
    var cleanEvent: String {
        event.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: - Messages
struct TornMessage: Codable {
    let name: String?
    let type: String?
    let title: String?
    let timestamp: Int?
    let read: Int?
}

// MARK: - Money
struct MoneyData: Codable {
    let cash: Int
    let vault: Int
    let points: Int
    let tokens: Int
    let cayman: Int
    
    enum CodingKeys: String, CodingKey {
        case cash = "money_onhand"
        case vault = "vault_amount"
        case points
        case tokens = "company_funds"
        case cayman = "cayman_bank"
    }
    
    init(cash: Int = 0, vault: Int = 0, points: Int = 0, tokens: Int = 0, cayman: Int = 0) {
        self.cash = cash
        self.vault = vault
        self.points = points
        self.tokens = tokens
        self.cayman = cayman
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cash = (try? container.decode(Int.self, forKey: .cash)) ?? 0
        vault = (try? container.decode(Int.self, forKey: .vault)) ?? 0
        points = (try? container.decode(Int.self, forKey: .points)) ?? 0
        tokens = (try? container.decode(Int.self, forKey: .tokens)) ?? 0
        cayman = (try? container.decode(Int.self, forKey: .cayman)) ?? 0
    }
}

// MARK: - Battle Stats
struct BattleStats: Codable {
    let strength: Int
    let defense: Int
    let speed: Int
    let dexterity: Int
    let total: Int
    
    init(strength: Int = 0, defense: Int = 0, speed: Int = 0, dexterity: Int = 0) {
        self.strength = strength
        self.defense = defense
        self.speed = speed
        self.dexterity = dexterity
        self.total = strength + defense + speed + dexterity
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strength = (try? container.decode(Int.self, forKey: .strength)) ?? 0
        defense = (try? container.decode(Int.self, forKey: .defense)) ?? 0
        speed = (try? container.decode(Int.self, forKey: .speed)) ?? 0
        dexterity = (try? container.decode(Int.self, forKey: .dexterity)) ?? 0
        total = (try? container.decode(Int.self, forKey: .total)) ?? (strength + defense + speed + dexterity)
    }
    
    enum CodingKeys: String, CodingKey {
        case strength, defense, speed, dexterity, total
    }
}

// MARK: - Attack Result
struct AttackResult: Codable, Identifiable {
    let code: String?
    let timestampStarted: Int?
    let timestampEnded: Int?
    let opponentId: Int?
    let opponentName: String?
    let result: String?
    let respect: Double?
    
    var id: String { code ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case code
        case timestampStarted = "timestamp_started"
        case timestampEnded = "timestamp_ended"
        case opponentId = "defender_id"
        case opponentName = "defender_name"
        case result, respect
    }
    
    var resultIcon: String {
        switch result {
        case "Attacked": return "checkmark.circle.fill"
        case "Mugged": return "dollarsign.circle.fill"
        case "Hospitalized": return "cross.circle.fill"
        case "Lost": return "xmark.circle.fill"
        case "Stalemate": return "equal.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    var resultColor: Color {
        switch result {
        case "Attacked", "Mugged", "Hospitalized": return .green
        case "Lost": return .red
        case "Stalemate": return .orange
        default: return .gray
        }
    }
    
    var timeAgo: String {
        guard let ts = timestampEnded else { return "" }
        let now = Int(Date().timeIntervalSince1970)
        let diff = now - ts
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }
}

// MARK: - Faction Data
struct FactionData: Codable {
    let name: String
    let factionId: Int
    let respect: Int
    let chain: FactionChain
    
    enum CodingKeys: String, CodingKey {
        case name
        case factionId = "ID"
        case respect
        case chain
    }
    
    init(name: String = "", factionId: Int = 0, respect: Int = 0, chain: FactionChain = FactionChain()) {
        self.name = name
        self.factionId = factionId
        self.respect = respect
        self.chain = chain
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        factionId = (try? container.decode(Int.self, forKey: .factionId)) ?? 0
        respect = (try? container.decode(Int.self, forKey: .respect)) ?? 0
        chain = (try? container.decode(FactionChain.self, forKey: .chain)) ?? FactionChain()
    }
}

struct FactionChain: Codable {
    let current: Int
    let max: Int
    let timeout: Int
    let cooldown: Int
    
    init(current: Int = 0, max: Int = 0, timeout: Int = 0, cooldown: Int = 0) {
        self.current = current
        self.max = max
        self.timeout = timeout
        self.cooldown = cooldown
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = (try? container.decode(Int.self, forKey: .current)) ?? 0
        max = (try? container.decode(Int.self, forKey: .max)) ?? 0
        timeout = (try? container.decode(Int.self, forKey: .timeout)) ?? 0
        cooldown = (try? container.decode(Int.self, forKey: .cooldown)) ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case current, max, timeout, cooldown
    }
}

// MARK: - Property Info
struct PropertyInfo: Codable, Identifiable {
    let id: Int
    let propertyType: String
    let vault: Int
    let upkeep: Int
    let rented: Bool
    let daysUntilUpkeep: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "property_id"
        case propertyType = "property"
        case vault = "money"
        case upkeep, rented
        case daysUntilUpkeep = "days_left"
    }
    
    init(id: Int = 0, propertyType: String = "", vault: Int = 0, upkeep: Int = 0, rented: Bool = false, daysUntilUpkeep: Int = 0) {
        self.id = id
        self.propertyType = propertyType
        self.vault = vault
        self.upkeep = upkeep
        self.rented = rented
        self.daysUntilUpkeep = daysUntilUpkeep
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        propertyType = (try? container.decode(String.self, forKey: .propertyType)) ?? ""
        vault = (try? container.decode(Int.self, forKey: .vault)) ?? 0
        upkeep = (try? container.decode(Int.self, forKey: .upkeep)) ?? 0
        rented = (try? container.decode(Bool.self, forKey: .rented)) ?? false
        daysUntilUpkeep = (try? container.decode(Int.self, forKey: .daysUntilUpkeep)) ?? 0
    }
}

// MARK: - Watchlist Item
struct WatchlistItem: Codable, Identifiable {
    let id: Int
    let name: String
    var lowestPrice: Int
    var lowestPriceQuantity: Int
    var secondLowestPrice: Int
    var lastUpdated: Date?
    var error: String?
    
    // Explicit memberwise initializer
    init(id: Int, name: String, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, lastUpdated: Date?, error: String?) {
        self.id = id
        self.name = name
        self.lowestPrice = lowestPrice
        self.lowestPriceQuantity = lowestPriceQuantity
        self.secondLowestPrice = secondLowestPrice
        self.lastUpdated = lastUpdated
        self.error = error
    }
    
    // Custom decoding to handle legacy data missing new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lowestPrice = try container.decodeIfPresent(Int.self, forKey: .lowestPrice) ?? 0
        lowestPriceQuantity = try container.decodeIfPresent(Int.self, forKey: .lowestPriceQuantity) ?? 0
        secondLowestPrice = try container.decodeIfPresent(Int.self, forKey: .secondLowestPrice) ?? 0
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
    
    var priceDifference: Int {
        guard secondLowestPrice > 0 && lowestPrice > 0 else { return 0 }
        return secondLowestPrice - lowestPrice
    }
    
    var isLoading: Bool {
        lowestPrice == 0 && error == nil
    }
}

// MARK: - Error
struct TornError: Codable {
    let code: Int
    let error: String
}

// MARK: - API Configuration
enum TornAPI {
    static let baseURL = "https://api.torn.com/user/"
    static let factionURL = "https://api.torn.com/faction/"
    static let marketURL = "https://api.torn.com/market/"
    static let tornURL = "https://api.torn.com/torn/"
    static let selections = "basic,bars,cooldowns,travel,profile,events,messages,money,battlestats,attacks,properties"
    
    static func url(for apiKey: String) -> URL? {
        URL(string: "\(baseURL)?selections=\(selections)&key=\(apiKey)")
    }
    
    static func factionURL(for apiKey: String) -> URL? {
        URL(string: "\(factionURL)?selections=basic,chain&key=\(apiKey)")
    }
    
    static func marketURL(itemId: Int, apiKey: String) -> URL? {
        // v2 endpoint for item market
        URL(string: "https://api.torn.com/v2/market/\(itemId)?selections=itemmarket,bazaar&key=\(apiKey)")
    }
}

// MARK: - Notification Settings
struct NotificationRule: Codable, Identifiable, Equatable {
    let id: String
    var barType: BarType
    var threshold: Int  // Percentage 0-100
    var enabled: Bool
    var soundName: String
    
    enum BarType: String, Codable, CaseIterable {
        case energy = "Energy"
        case nerve = "Nerve"
        case happy = "Happy"
        case life = "Life"
    }
    
    static let defaults: [NotificationRule] = [
        NotificationRule(id: "energy_full", barType: .energy, threshold: 100, enabled: true, soundName: "default"),
        NotificationRule(id: "energy_high", barType: .energy, threshold: 80, enabled: false, soundName: "default"),
        NotificationRule(id: "nerve_full", barType: .nerve, threshold: 100, enabled: true, soundName: "default"),
        NotificationRule(id: "happy_full", barType: .happy, threshold: 100, enabled: false, soundName: "default"),
        NotificationRule(id: "life_low", barType: .life, threshold: 20, enabled: false, soundName: "default")
    ]
}

// MARK: - Sound Options
enum NotificationSound: String, CaseIterable {
    case `default` = "default"
    case ping = "Ping"
    case glass = "Glass"
    case hero = "Hero"
    case pop = "Pop"
    case submarine = "Submarine"
    case none = "None"
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .ping: return "Ping"
        case .glass: return "Glass"
        case .hero: return "Hero"
        case .pop: return "Pop"
        case .submarine: return "Submarine"
        case .none: return "None"
        }
    }
}

// MARK: - Keyboard Shortcuts
struct KeyboardShortcut: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var url: String
    var keyEquivalent: String
    var modifiers: [String]
    
    static let defaults: [KeyboardShortcut] = [
        KeyboardShortcut(id: "home", name: "Home", url: "https://www.torn.com/", keyEquivalent: "h", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "items", name: "Items", url: "https://www.torn.com/item.php", keyEquivalent: "i", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "gym", name: "Gym", url: "https://www.torn.com/gym.php", keyEquivalent: "g", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "crimes", name: "Crimes", url: "https://www.torn.com/crimes.php", keyEquivalent: "c", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "mission", name: "Missions", url: "https://www.torn.com/missions.php", keyEquivalent: "m", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "travel", name: "Travel", url: "https://www.torn.com/travelagency.php", keyEquivalent: "t", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "hospital", name: "Hospital", url: "https://www.torn.com/hospitalview.php", keyEquivalent: "o", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "faction", name: "Faction", url: "https://www.torn.com/factions.php", keyEquivalent: "f", modifiers: ["command", "shift"])
    ]
}
