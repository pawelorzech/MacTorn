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
    let error: TornError?
    
    enum CodingKeys: String, CodingKey {
        case name
        case playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, error
    }
    
    // Convenience computed property
    var bars: Bars? {
        guard let energy = energy,
              let nerve = nerve,
              let life = life,
              let happy = happy else { return nil }
        return Bars(energy: energy, nerve: nerve, life: life, happy: happy)
    }
}

// MARK: - Bars (for internal use)
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
    let destination: String
    let timestamp: Int
    let departed: Int
    let timeLeft: Int
    
    enum CodingKeys: String, CodingKey {
        case destination
        case timestamp
        case departed
        case timeLeft = "time_left"
    }
    
    var isAbroad: Bool {
        destination != "Torn" && timeLeft == 0
    }
    
    var isTraveling: Bool {
        timeLeft > 0
    }
    
    var arrivalDate: Date? {
        guard isTraveling else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
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
    static let selections = "basic,bars,cooldowns,travel"
    
    static func url(for apiKey: String) -> URL? {
        URL(string: "\(baseURL)?selections=\(selections)&key=\(apiKey)")
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
        KeyboardShortcut(
            id: "home",
            name: "Home",
            url: "https://www.torn.com/",
            keyEquivalent: "h",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "items",
            name: "Items",
            url: "https://www.torn.com/item.php",
            keyEquivalent: "i",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "gym",
            name: "Gym",
            url: "https://www.torn.com/gym.php",
            keyEquivalent: "g",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "crimes",
            name: "Crimes",
            url: "https://www.torn.com/crimes.php",
            keyEquivalent: "c",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "mission",
            name: "Missions",
            url: "https://www.torn.com/missions.php",
            keyEquivalent: "m",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "travel",
            name: "Travel",
            url: "https://www.torn.com/travelagency.php",
            keyEquivalent: "t",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "hospital",
            name: "Hospital",
            url: "https://www.torn.com/hospitalview.php",
            keyEquivalent: "o",
            modifiers: ["command", "shift"]
        ),
        KeyboardShortcut(
            id: "faction",
            name: "Faction",
            url: "https://www.torn.com/factions.php",
            keyEquivalent: "f",
            modifiers: ["command", "shift"]
        )
    ]
}
