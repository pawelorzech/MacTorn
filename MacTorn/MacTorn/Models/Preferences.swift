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

// MARK: - Travel Notification Settings
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

// MARK: - App Feedback State
struct AppFeedbackState: Codable {
    var firstLaunchDate: Date
    var hasResponded: Bool
    var dismissCount: Int
    var lastDismissedDate: Date?
}

// MARK: - Forum Watch
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
// Swift's synthesized `init(from:)` calls `decode(_:forKey:)` for every non-optional
// property and throws on a missing key — it does **not** fall back to the defaults in a
// memberwise initialiser. So adding one field to a persisted type throws on every
// existing user's stored blob.
//
// That is only a nuisance where the load path is guarded. For these four it is data loss:
// `loadNotificationRules`, `loadTravelNotificationSettings` and `loadShortcuts` answer a
// decode failure by installing the defaults and saving them in the same statement, and
// `WatchedThread` latches `threadsLoadFailed` and leaves the Forum Watch tab empty for
// good. `WatchlistItem` and `ForumWatchConfig` already decode this way; these four are
// the rest of the set.
//
// Each lives in an extension so the *synthesized memberwise* initialiser survives — an
// explicit `init` in the struct body would suppress it and break every `defaults` entry.
// `encode(to:)` is still synthesized, which keeps `CodingKeys` available here.

extension WatchedThread {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The thread id is the identity. A row without one is not a watched thread.
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown"
        notificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        // Zero is the honest answer for a row that never stored a count, and `apply`'s
        // `previousCount > 0` guard then re-baselines silently on the next poll: one
        // missed alert, never a false one. Same reasoning as audit finding D-02.
        lastKnownPostCount =
            try container.decodeIfPresent(Int.self, forKey: .lastKnownPostCount) ?? 0
        lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        isFactionThread =
            try container.decodeIfPresent(Bool.self, forKey: .isFactionThread) ?? false
    }
}

struct ForumWatchConfig: Codable {
    var factionForumAutoMonitor: Bool
    var factionForumCategoryId: Int?
    var pollingIntervalSeconds: Int
    /// Thread ids already seen in the watched category, most recently seen first.
    ///
    /// Ordered and cumulative, not a snapshot of the last page. The listing is capped at
    /// `TornAPI.forumCategoryRowLimit` rows, so replacing this with each page turned it
    /// into a sliding window: in any category busier than one page, a thread that scrolled
    /// off was forgotten, and the next reply that bumped it back to the top was announced
    /// as new. Under activity-ordered listings that is the steady state, not an edge case.
    var seenFactionThreadIds: [Int]
    /// The category `seenFactionThreadIds` was gathered from.
    ///
    /// Without it, a listing already in flight when the user edits the Category ID lands
    /// afterwards and writes the *old* category's ids under the *new* category's id, with
    /// `hasSeededFactionThreads` set. The next poll then finds nothing familiar and
    /// announces a page of months-old threads: exactly the storm seeding exists to prevent.
    var seededCategoryId: Int?
    /// Whether the category has been read at least once.
    ///
    /// Kept separately from the id list because an empty list is ambiguous: it means both
    /// "never looked" and "looked, and the category was empty". Conflating them costs the
    /// announcement of the very first thread posted to a quiet category, the one most
    /// worth hearing about.
    var hasSeededFactionThreads: Bool

    /// Ceiling on remembered ids. A category holds far fewer threads than this in
    /// practice, so eviction should never fire; it is here so an unbounded preference
    /// cannot grow forever, and it drops the least recently seen first because those are
    /// the least likely to be bumped back to the top.
    static let maximumSeenThreadIds = 500

    init(factionForumAutoMonitor: Bool = false,
         factionForumCategoryId: Int? = nil,
         pollingIntervalSeconds: Int = 180,
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

    /// Decoded field by field so a config written by an older build — which has no
    /// `hasSeededFactionThreads` key — still loads. Synthesized `Codable` would throw on
    /// the missing key and silently reset every forum preference the user had set.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factionForumAutoMonitor =
            try container.decodeIfPresent(Bool.self, forKey: .factionForumAutoMonitor) ?? false
        factionForumCategoryId =
            try container.decodeIfPresent(Int.self, forKey: .factionForumCategoryId)
        pollingIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? 180

        // `knownFactionThreadIds` was an unordered Set written by 1.12.0 and 1.12.1.
        // Decoding it here keeps those installs from re-announcing their whole category
        // after the upgrade. Order is unrecoverable from a Set, which costs nothing: the
        // ids are all equally "already seen", and the next listing re-establishes order.
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
        // Derived from the flag, not from list emptiness. A 1.12.1 install that had seeded
        // an *empty* category carried `hasSeededFactionThreads: true` with no ids, so
        // inferring from the list left `seededCategoryId` nil, `applyCategory` recomputed
        // `wasSeeded` as false, and it re-seeded silently — swallowing the first thread
        // posted to a quiet category, which is the exact case the flag was added for.
        seededCategoryId =
            try container.decodeIfPresent(Int.self, forKey: .seededCategoryId)
            ?? (seeded ? factionForumCategoryId : nil)
    }
}

// MARK: - Keyboard Shortcuts
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
/// These are hand-authored names, URLs and hotkeys with no other copy anywhere, and
/// `loadShortcuts` replaces them with the defaults and saves in the same statement on a
/// decode failure — the most expensive of the four to get wrong.
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
