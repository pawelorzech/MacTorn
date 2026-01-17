import Foundation

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

// MARK: - Error
struct TornError: Codable {
    let code: Int
    let error: String
}

// MARK: - API Configuration
enum TornAPI {
    static let baseURL = "https://api.torn.com/user/"
    static let selections = "basic,bars,cooldowns,travel,profile,events,messages"
    
    static func url(for apiKey: String) -> URL? {
        URL(string: "\(baseURL)?selections=\(selections)&key=\(apiKey)")
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
