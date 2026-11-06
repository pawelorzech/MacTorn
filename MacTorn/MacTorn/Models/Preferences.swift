import Foundation

/// UserDefaults keys that more than one type reads (`@AppStorage` in views, direct reads
/// elsewhere). A key that only one type touches stays private to that type.
enum StoredPreference {
    static let appearanceMode = "appearanceMode"
    static let reduceTransparency = "reduceTransparency"
    static let preferredBrowser = "preferredBrowser"
    static let boosterCooldownTarget = "boosterCooldownTarget"
    static let privateIsland = "privateIsland"
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

/// Which items page the booster cooldown links to: some players reset it with alcohol.
enum BoosterCooldownTarget: String, CaseIterable {
    case boosters
    case alcohol

    var title: String { rawValue.capitalized }
    var actionLabel: String { self == .alcohol ? "Use Alcohol →" : "Use Booster →" }
    var itemsURL: URL { TornLink.page("item.php#\(rawValue)-items") }
}

struct TravelNotificationSetting: Codable, Identifiable, Equatable {
    let id: String
    let secondsBefore: Int
    var enabled: Bool

    /// The pending-notification id the landing alert is scheduled under.
    var notificationIdentifier: String { "\(id)_alert" }

    var displayName: String {
        if secondsBefore >= 60 {
            return "\(secondsBefore / 60) min before"
        }
        return "\(secondsBefore) sec before"
    }

    static let defaults: [TravelNotificationSetting] = [
        TravelNotificationSetting(id: "travel_2min", secondsBefore: 120, enabled: false),
        TravelNotificationSetting(id: "travel_1min", secondsBefore: 60, enabled: true),
        TravelNotificationSetting(id: "travel_30sec", secondsBefore: 30, enabled: false),
        TravelNotificationSetting(id: "travel_10sec", secondsBefore: 10, enabled: false)
    ]
}

/// See "Tolerant decoding for persisted preferences" above `WatchedThread`.
extension TravelNotificationSetting {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let shipped = Self.defaults.first { $0.id == id }
        self.id = id
        // `secondsBefore` is what the setting *means*, so a partial row rebuilds as the
        // shipped lead time for its id rather than as zero — which would schedule the
        // "landing soon" alert for the moment of landing.
        secondsBefore = try container.decodeIfPresent(Int.self, forKey: .secondsBefore)
            ?? shipped?.secondsBefore ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? shipped?.enabled ?? false
    }
}

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

/// See "Tolerant decoding for persisted preferences" above `WatchedThread`.
extension NotificationRule {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The rule id is the identity, and every rule the app defines has one.
        let id = try container.decode(String.self, forKey: .id)
        // A missing field falls back to the shipped rule with the same id, which is a
        // truer reconstruction of a partial row than a bare zero would be.
        let shipped = Self.defaults.first { $0.id == id }
        self.id = id
        // Decoded through the raw value rather than as `BarType`: `decodeIfPresent` still
        // throws when the key is present but holds a raw value this build does not know,
        // so retiring or renaming a bar in a later release would throw here and take
        // every other rule down with it.
        let rawBarType = try container.decodeIfPresent(String.self, forKey: .barType)
        barType = rawBarType.flatMap(BarType.init(rawValue:)) ?? shipped?.barType ?? .energy
        threshold = try container.decodeIfPresent(Int.self, forKey: .threshold)
            ?? shipped?.threshold ?? 100
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? shipped?.enabled ?? false
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName)
            ?? shipped?.soundName ?? "default"
    }
}

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

struct AppFeedbackState: Codable {
    var firstLaunchDate: Date
    var hasResponded: Bool
    var dismissCount: Int
    var lastDismissedDate: Date?
}

struct WatchedThread: Codable, Identifiable {
    let id: Int
    var title: String
    var notificationsEnabled: Bool
    var lastKnownPostCount: Int
    var lastChecked: Date?
    var error: String?
    var isFactionThread: Bool

    init(id: Int, title: String, notificationsEnabled: Bool = true, lastKnownPostCount: Int = 0, lastChecked: Date? = nil, error: String? = nil, isFactionThread: Bool = false) {
        self.id = id
        self.title = title
        self.notificationsEnabled = notificationsEnabled
        self.lastKnownPostCount = lastKnownPostCount
        self.lastChecked = lastChecked
        self.error = error
        self.isFactionThread = isFactionThread
    }

}

// MARK: - Tolerant decoding for persisted preferences
//
// Swift's synthesized `init(from:)` throws on a missing key instead of falling back to a default,
// so adding a field to a persisted type would make every existing user's stored blob fail to
// decode. These types therefore decode field by field in extensions, which also keeps the
// synthesized memberwise initialiser (an explicit `init` in the struct body would suppress it).
// `encode(to:)` stays synthesized.

extension WatchedThread {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The thread id is the identity. A row without one is not a watched thread.
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown"
        notificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        // Zero is the honest answer for a row that never stored a count: `apply`'s `previousCount > 0`
        // guard then re-baselines silently on the next poll, costing one missed alert, never a false one.
        lastKnownPostCount =
            try container.decodeIfPresent(Int.self, forKey: .lastKnownPostCount) ?? 0
        lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        isFactionThread =
            try container.decodeIfPresent(Bool.self, forKey: .isFactionThread) ?? false
    }
}

struct ForumWatchConfig: Codable {
    /// The forum poll cadences Settings offers, in seconds.
    static let pollingIntervals = [120, 180, 300]
    static let defaultPollingInterval = 180

    var factionForumAutoMonitor: Bool
    var factionForumCategoryId: Int?
    var pollingIntervalSeconds: Int
    /// Thread ids already seen in the watched category, most recently seen first.
    ///
    /// Ordered and cumulative, not a snapshot of the last page. The listing is capped at one page of
    /// rows, so replacing this with each page would forget threads that scrolled off, and the next
    /// reply that bumped one back to the top would be announced as new.
    var seenFactionThreadIds: [Int]
    /// The category `seenFactionThreadIds` was gathered from.
    ///
    /// Without it, a listing in flight when the user edits the Category ID would write the old
    /// category's ids under the new category's id and announce a page of months-old threads.
    var seededCategoryId: Int?
    /// Whether the category has been read at least once.
    ///
    /// Separate from the id list because an empty list is ambiguous: "never looked" and "looked, and the
    /// category was empty" differ, and conflating them would swallow the first thread posted to a quiet
    /// category.
    var hasSeededFactionThreads: Bool

    /// Ceiling on remembered ids. A category holds far fewer threads in practice; the cap only keeps the
    /// preference from growing forever, and evicts the least recently seen first because those are the
    /// least likely to be bumped back to the top.
    static let maximumSeenThreadIds = 500

    init(factionForumAutoMonitor: Bool = false,
         factionForumCategoryId: Int? = nil,
         pollingIntervalSeconds: Int = ForumWatchConfig.defaultPollingInterval,
         seenFactionThreadIds: [Int] = [],
         seededCategoryId: Int? = nil,
         hasSeededFactionThreads: Bool = false) {
        self.factionForumAutoMonitor = factionForumAutoMonitor
        self.factionForumCategoryId = factionForumCategoryId
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.seenFactionThreadIds = seenFactionThreadIds
        self.seededCategoryId = seededCategoryId
        self.hasSeededFactionThreads = hasSeededFactionThreads
    }

    private enum CodingKeys: String, CodingKey {
        case factionForumAutoMonitor, factionForumCategoryId, pollingIntervalSeconds
        case seenFactionThreadIds, seededCategoryId, hasSeededFactionThreads
        /// Written by 1.12.0/1.12.1. Read for migration, never written again.
        case knownFactionThreadIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(factionForumAutoMonitor, forKey: .factionForumAutoMonitor)
        try container.encodeIfPresent(factionForumCategoryId, forKey: .factionForumCategoryId)
        try container.encode(pollingIntervalSeconds, forKey: .pollingIntervalSeconds)
        try container.encode(seenFactionThreadIds, forKey: .seenFactionThreadIds)
        try container.encodeIfPresent(seededCategoryId, forKey: .seededCategoryId)
        try container.encode(hasSeededFactionThreads, forKey: .hasSeededFactionThreads)
    }

    /// Forgets the watched category. Used when the user turns the watch off or points it
    /// somewhere else — remembered ids from one category say nothing about another.
    mutating func forgetSeenThreads() {
        seenFactionThreadIds = []
        seededCategoryId = nil
        hasSeededFactionThreads = false
    }

    /// Decoded field by field so a config written by an older build, which has no
    /// `hasSeededFactionThreads` key, still loads instead of resetting every forum preference.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factionForumAutoMonitor =
            try container.decodeIfPresent(Bool.self, forKey: .factionForumAutoMonitor) ?? false
        factionForumCategoryId =
            try container.decodeIfPresent(Int.self, forKey: .factionForumCategoryId)
        pollingIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? Self.defaultPollingInterval

        // `knownFactionThreadIds` was an unordered Set written by 1.12.0 and 1.12.1. Decoding it keeps
        // those installs from re-announcing their whole category; order is unrecoverable from a Set, but
        // the ids are all equally "already seen" and the next listing re-establishes it.
        if let ordered = try container.decodeIfPresent([Int].self, forKey: .seenFactionThreadIds) {
            seenFactionThreadIds = ordered
        } else {
            seenFactionThreadIds =
                Array(try container.decodeIfPresent(Set<Int>.self, forKey: .knownFactionThreadIds) ?? [])
        }
        // An older config that already has ids was plainly seeded by an older build.
        let seeded = try container.decodeIfPresent(Bool.self, forKey: .hasSeededFactionThreads)
            ?? !seenFactionThreadIds.isEmpty
        hasSeededFactionThreads = seeded
        // Derived from the flag, not from list emptiness: a 1.12.1 install that seeded an empty category
        // has `hasSeededFactionThreads: true` with no ids, and inferring from the list would re-seed it
        // silently and swallow the first thread posted to that quiet category.
        seededCategoryId =
            try container.decodeIfPresent(Int.self, forKey: .seededCategoryId)
            ?? (seeded ? factionForumCategoryId : nil)
    }
}

/// The Torn quick links on the Status tab. Users of the old shortcut editor may still
/// have a customised list stored; everyone else gets the current defaults.
enum QuickLinks {
    static func load(from defaults: UserDefaults = .standard) -> [KeyboardShortcut] {
        guard let data = defaults.data(forKey: "customShortcuts"),
              let saved = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) else {
            return KeyboardShortcut.defaults
        }
        return saved
    }
}

struct KeyboardShortcut: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var url: String
    var keyEquivalent: String
    var modifiers: [String]
    
    static let defaults: [KeyboardShortcut] = [
        KeyboardShortcut(id: "home", name: "Home", url: TornLink.home.absoluteString, keyEquivalent: "h", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "items", name: "Items", url: TornLink.items.absoluteString, keyEquivalent: "i", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "gym", name: "Gym", url: TornLink.gym.absoluteString, keyEquivalent: "g", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "crimes", name: "Crimes", url: TornLink.crimes.absoluteString, keyEquivalent: "c", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "mission", name: "Missions", url: TornLink.page("missions.php").absoluteString, keyEquivalent: "m", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "travel", name: "Travel", url: TornLink.travelAgency.absoluteString, keyEquivalent: "t", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "hospital", name: "Hospital", url: TornLink.hospital.absoluteString, keyEquivalent: "o", modifiers: ["command", "shift"]),
        KeyboardShortcut(id: "faction", name: "Faction", url: TornLink.page("factions.php").absoluteString, keyEquivalent: "f", modifiers: ["command", "shift"])
    ]
}

/// See "Tolerant decoding for persisted preferences" above `WatchedThread`.
///
/// These are hand-authored names, URLs and hotkeys with no other copy anywhere, so a decode
/// failure must not be allowed to discard them.
extension KeyboardShortcut {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        // A shortcut the user created themselves has no shipped counterpart, so the
        // fallbacks below degrade rather than invent: an unnamed row shows its id, and a
        // row with no URL simply does not open anything.
        let shipped = Self.defaults.first { $0.id == id }
        self.id = id
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? shipped?.name ?? id
        url = try container.decodeIfPresent(String.self, forKey: .url)
            ?? shipped?.url ?? ""
        keyEquivalent = try container.decodeIfPresent(String.self, forKey: .keyEquivalent)
            ?? shipped?.keyEquivalent ?? ""
        modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers)
            ?? shipped?.modifiers ?? []
    }
}
