import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "TornModels")

// MARK: - Constants
enum TornConstants {
    static let developerID = 2362436
    static let logSubsystem = "com.mactorn"
}

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
    /// Server-side Unix epoch at which this response was generated. Used as the
    /// anchor when converting relative durations (e.g. cooldowns) into absolute
    /// end-timestamps so countdowns match torn.com regardless of Mac↔server clock skew.
    ///
    /// The live v1 `user` root returns this under `server_time` — NOT `timestamp`
    /// (which is only present when the `timestamp` selection is requested, which we
    /// don't). `legacyTimestamp` keeps the old `timestamp` key working as a fallback
    /// so a response carrying either key still anchors correctly. Verified against a
    /// live API response 2026-07-03.
    let serverTimestamp: Int?
    let legacyTimestamp: Int?

    /// Best available server-time anchor: prefer `server_time`, fall back to the
    /// legacy `timestamp` key, else nil (caller drops to local `Date()`).
    var anchorTimestamp: Int? { serverTimestamp ?? legacyTimestamp }

    enum CodingKeys: String, CodingKey {
        case name
        case playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, status, chain
        case events, messages, error
        case serverTimestamp = "server_time"
        case legacyTimestamp = "timestamp"
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
        return events
            .map { apiID, event in event.identified(by: apiID) }
            .sorted { $0.timestamp > $1.timestamp }
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

enum CooldownKind: CaseIterable {
    case drug, booster, medical

    var emoji: String {
        switch self {
        case .drug:    return "💊"
        case .booster: return "🧪"
        case .medical: return "🩹"
        }
    }

    /// Spoken/written name of the cooldown. The emoji above is decoration; this is the
    /// meaning, and it is what VoiceOver and any text fallback must use.
    var displayName: String {
        switch self {
        case .drug:    return "Drug"
        case .booster: return "Booster"
        case .medical: return "Medical"
        }
    }
}

/// Absolute end-timestamps for each cooldown, computed once at fetch time from
/// the server's response timestamp + the relative cooldown duration. Storing the
/// end-time (not the duration) is what keeps every countdown drift-free against
/// torn.com — see `Plans/wszystkie-czasy-kt-re-s-dazzling-bumblebee.md`. A value
/// of `0` means the cooldown is not active.
struct CooldownEnds: Equatable {
    let drugEndsAt: Int
    let boosterEndsAt: Int
    let medicalEndsAt: Int

    static func from(cooldowns: Cooldowns, anchor: Int) -> CooldownEnds {
        CooldownEnds(
            drugEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.drug),
            boosterEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.booster),
            medicalEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.medical)
        )
    }

    /// One cooldown's absolute end-timestamp, or `0` — the struct's existing "not active"
    /// sentinel — when the cooldown is inactive or the API's numbers cannot produce a
    /// usable one.
    ///
    /// `anchor` and `duration` are both raw `Int`s decoded straight from Torn, so nothing
    /// bounds their sum. A response carrying a duration near `Int.max` overflowed the
    /// addition and trapped the process (SIGTRAP, exit 133). Degrading that cooldown to
    /// "unknown" keeps a display-only menu bar app running, which is strictly better than
    /// crashing it over a number it only meant to display.
    private static func endTimestamp(anchor: Int, duration: Int) -> Int {
        guard duration > 0 else { return 0 }
        let (endsAt, overflowed) = anchor.addingReportingOverflow(duration)
        return overflowed ? 0 : endsAt
    }

    func endsAt(_ kind: CooldownKind) -> Int {
        switch kind {
        case .drug:    return drugEndsAt
        case .booster: return boosterEndsAt
        case .medical: return medicalEndsAt
        }
    }

    /// `endsAt` is an absolute **server** timestamp, so `now` must be Torn's now
    /// (`AppState.serverNow`). The `Date()` default is for pure-model callers only.
    func remainingSeconds(_ kind: CooldownKind, at now: Date = Date()) -> Int {
        let target = endsAt(kind)
        guard target > 0 else { return 0 }
        return max(0, target - Int(now.timeIntervalSince1970))
    }

    func soonestActive(at now: Date = Date()) -> (kind: CooldownKind, seconds: Int)? {
        CooldownKind.allCases
            .map { (kind: $0, seconds: remainingSeconds($0, at: now)) }
            .filter { $0.seconds > 0 }
            .min { $0.seconds < $1.seconds }
    }

    /// Stabilises per-poll jitter in cooldown end-timestamps. Each poll re-derives
    /// `endsAt = serverTimestamp + cooldowns.{kind}`, but both the API timestamp and
    /// the duration are integer-seconds and are subject to network-latency variance,
    /// so the freshly-computed `endsAt` typically wobbles by ±1–3 s between polls
    /// even though the cooldown's true expiry is fixed. Without smoothing, every
    /// poll causes a visible jump in the menu bar countdown.
    ///
    /// Per kind: keep the previously-pinned `endsAt` whenever the new one is within
    /// `toleranceSeconds`. A larger gap means the cooldown was reset (new booster
    /// taken, drug applied, medical after hospitalisation) — we adopt the new value.
    /// A `0` on either side (cooldown inactive on one side) is taken from `other`
    /// so transitions in/out of active are immediate.
    ///
    /// The tolerance is shared with `ServerClock.merged`, which damps the *other* half
    /// of the same subtraction (issue #46): pinning `endsAt` while `now` still wobbles
    /// poll to poll would give the jump back.
    func merged(with other: CooldownEnds,
                toleranceSeconds: Int = ServerClock.jitterToleranceSeconds) -> CooldownEnds {
        func pick(_ old: Int, _ new: Int) -> Int {
            if old == 0 || new == 0 { return new }
            return abs(new - old) <= toleranceSeconds ? old : new
        }
        return CooldownEnds(
            drugEndsAt:    pick(drugEndsAt,    other.drugEndsAt),
            boosterEndsAt: pick(boosterEndsAt, other.boosterEndsAt),
            medicalEndsAt: pick(medicalEndsAt, other.medicalEndsAt)
        )
    }
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

    /// Remaining seconds of flight.
    ///
    /// `timestamp` is an absolute **server** timestamp and `time_left` is measured from
    /// the instant the *server* generated the response, so both `fetchTime` and `now`
    /// must be expressed on Torn's clock (`AppState.serverFetchTime` / `AppState.serverNow`)
    /// — mixing the two clocks is exactly the bug in issue #46. The `Date()` default is
    /// for pure-model callers that have no skew to correct.
    func remainingSeconds(from fetchTime: Date, now: Date = Date()) -> Int {
        // Primary: Use timestamp directly if available (more accurate)
        if let timestamp = timestamp, timestamp > 0 {
            return max(0, timestamp - Int(now.timeIntervalSince1970))
        }

        // Fallback: Use timeLeft with fetchTime offset (backward compatibility)
        guard let timeLeft = timeLeft, timeLeft > 0 else { return 0 }
        let elapsed = Int(now.timeIntervalSince(fetchTime))
        return max(0, timeLeft - elapsed)
    }

    /// Calculate flight progress (0.0 to 1.0) based on fetch time
    func flightProgress(from fetchTime: Date, now: Date = Date()) -> Double {
        guard let departed = departed, let timestamp = timestamp else { return 0 }
        let totalDuration = timestamp - departed
        guard totalDuration > 0 else { return 0 }
        let remaining = remainingSeconds(from: fetchTime, now: now)
        let elapsed = totalDuration - remaining
        return min(1.0, max(0.0, Double(elapsed) / Double(totalDuration)))
    }
}

// MARK: - Travel Destinations
enum TornDestination: String, CaseIterable, Identifiable {
    case mexico = "Mexico"
    case caymanIslands = "Cayman Islands"
    case canada = "Canada"
    case hawaii = "Hawaii"
    case unitedKingdom = "United Kingdom"
    case argentina = "Argentina"
    case switzerland = "Switzerland"
    case japan = "Japan"
    case china = "China"
    case uae = "UAE"
    case southAfrica = "South Africa"

    var id: String { rawValue }

    enum FlightMethod: String, CaseIterable {
        case standard = "Standard"
        case airstrip = "Airstrip + pilot"
    }

    /// Torn documents up to 3% variance around the published base durations.
    static let estimateVariancePercent = 3

    var flag: String {
        switch self {
        case .mexico: return "🇲🇽"
        case .caymanIslands: return "🇰🇾"
        case .canada: return "🇨🇦"
        case .hawaii: return "🇺🇸"
        case .unitedKingdom: return "🇬🇧"
        case .argentina: return "🇦🇷"
        case .switzerland: return "🇨🇭"
        case .japan: return "🇯🇵"
        case .china: return "🇨🇳"
        case .uae: return "🇦🇪"
        case .southAfrica: return "🇿🇦"
        }
    }

    /// Current one-way base duration published by Torn.
    ///
    /// Patch #438 (2026-06-23) reduced every travel method by 5.26%. These values
    /// intentionally mirror the official table instead of deriving one method from
    /// another, because Torn rounds each displayed duration independently.
    /// Live flights never use this estimate: their countdown comes from the API's
    /// `travel.timestamp`, `departed`, and `time_left` fields.
    func flightTimeMinutes(method: FlightMethod = .standard) -> Int {
        switch (self, method) {
        case (.mexico, .standard): return 24
        case (.caymanIslands, .standard): return 33
        case (.canada, .standard): return 39
        case (.hawaii, .standard): return 127
        case (.unitedKingdom, .standard): return 151
        case (.argentina, .standard): return 158
        case (.switzerland, .standard): return 166
        case (.japan, .standard): return 213
        case (.china, .standard): return 229
        case (.uae, .standard): return 257
        case (.southAfrica, .standard): return 282
        case (.mexico, .airstrip): return 17
        case (.caymanIslands, .airstrip): return 23
        case (.canada, .airstrip): return 27
        case (.hawaii, .airstrip): return 89
        case (.unitedKingdom, .airstrip): return 106
        case (.argentina, .airstrip): return 111
        case (.switzerland, .airstrip): return 116
        case (.japan, .airstrip): return 149
        case (.china, .airstrip): return 160
        case (.uae, .airstrip): return 180
        case (.southAfrica, .airstrip): return 197
        }
    }

    /// Compatibility accessor for callers that want the standard estimate.
    var flightTimeMinutes: Int {
        flightTimeMinutes()
    }

    func flightTimeFormatted(method: FlightMethod = .standard) -> String {
        let duration = flightTimeMinutes(method: method)
        let hours = duration / 60
        let minutes = duration % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Compatibility accessor for callers that want the standard estimate.
    var flightTimeFormatted: String {
        flightTimeFormatted()
    }

    var travelAgencyURL: URL {
        URL(string: "https://www.torn.com/travelagency.php")!
    }

    /// Look up flag emoji for a destination string, including non-enum values like "Torn"
    static func flag(for destination: String) -> String {
        if let known = TornDestination(rawValue: destination) {
            return known.flag
        }
        if destination.lowercased() == "torn" {
            let hasPrivateIsland = UserDefaults.standard.bool(forKey: "privateIsland")
            return hasPrivateIsland ? "🏝️" : "🏠"
        }
        return "🌍"
    }
}

// MARK: - Travel Notification Settings
struct TravelNotificationSetting: Codable, Identifiable, Equatable {
    let id: String
    let secondsBefore: Int
    var enabled: Bool

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
    
    /// Seconds until release. `until` is an absolute **server** timestamp, so `now` must
    /// be Torn's now (`AppState.serverNow`).
    func timeRemaining(at now: Date) -> Int {
        guard let until = until else { return 0 }
        return max(0, until - Int(now.timeIntervalSince1970))
    }

    var timeRemaining: Int { timeRemaining(at: Date()) }
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
    
    /// Seconds until the chain lapses. `timeout` is an absolute **server** timestamp, so
    /// `now` must be Torn's now (`AppState.serverNow`).
    func timeoutRemaining(at now: Date) -> Int {
        guard let timeout = timeout else { return 0 }
        return max(0, timeout - Int(now.timeIntervalSince1970))
    }

    var timeoutRemaining: Int { timeoutRemaining(at: Date()) }
}

// MARK: - Events
struct TornEvent: Codable, Identifiable {
    let timestamp: Int
    let event: String
    let seen: Int?
    /// Dictionary key supplied by Torn. Two events can share a second-level timestamp,
    /// so the timestamp alone is not a stable SwiftUI identity.
    private var apiID: String? = nil

    enum CodingKeys: String, CodingKey {
        case timestamp, event, seen
    }

    var id: String { apiID ?? "\(timestamp):\(event)" }

    func identified(by apiID: String) -> TornEvent {
        var copy = self
        copy.apiID = apiID
        return copy
    }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    // Strip HTML tags and decode HTML entities from event text
    var cleanEvent: String {
        event.strippedHTMLAndDecodedEntities
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
        case tokens = "donator"
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
    let attackerId: Int?
    let attackerName: String?
    let defenderId: Int?
    let defenderName: String?
    let result: String?
    let respect: Double?

    let id: String

    enum CodingKeys: String, CodingKey {
        case code
        case timestampStarted = "timestamp_started"
        case timestampEnded = "timestamp_ended"
        case attackerId = "attacker_id"
        case attackerName = "attacker_name"
        case defenderId = "defender_id"
        case defenderName = "defender_name"
        case result, respect
    }

    init(code: String?, timestampStarted: Int?, timestampEnded: Int?, attackerId: Int?, attackerName: String?, defenderId: Int?, defenderName: String?, result: String?, respect: Double?) {
        self.code = code
        self.timestampStarted = timestampStarted
        self.timestampEnded = timestampEnded
        self.attackerId = attackerId
        self.attackerName = attackerName
        self.defenderId = defenderId
        self.defenderName = defenderName
        self.result = result
        self.respect = respect
        self.id = code ?? UUID().uuidString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        timestampStarted = try container.decodeIfPresent(Int.self, forKey: .timestampStarted)
        timestampEnded = try container.decodeIfPresent(Int.self, forKey: .timestampEnded)
        attackerId = try container.decodeIfPresent(Int.self, forKey: .attackerId)
        attackerName = try container.decodeIfPresent(String.self, forKey: .attackerName)
        defenderId = try container.decodeIfPresent(Int.self, forKey: .defenderId)
        defenderName = try container.decodeIfPresent(String.self, forKey: .defenderName)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        respect = try container.decodeIfPresent(Double.self, forKey: .respect)
        id = code ?? UUID().uuidString
    }

    func opponentName(forUserId userId: Int) -> String {
        let name: String?
        if attackerId == userId {
            name = defenderName
        } else {
            name = attackerName
        }

        if let name = name, !name.isEmpty {
            return name
        }
        return "Someone"
    }

    func opponentId(forUserId userId: Int) -> Int? {
        if attackerId == userId {
            return defenderId
        } else {
            return attackerId
        }
    }

    func wasAttacker(userId: Int) -> Bool {
        return attackerId == userId
    }
    
    func resultIcon(forUserId userId: Int) -> String {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked": return userWasAttacker ? "checkmark.circle.fill" : "xmark.circle.fill"
        case "Mugged": return userWasAttacker ? "dollarsign.circle.fill" : "xmark.circle.fill"
        case "Hospitalized": return userWasAttacker ? "cross.circle.fill" : "xmark.circle.fill"
        case "Lost": return userWasAttacker ? "xmark.circle.fill" : "shield.checkered"
        case "Stalemate": return "equal.circle.fill"
        case "Escape": return userWasAttacker ? "figure.run" : "shield.checkered"
        case "Assist": return "person.2.fill"
        default: return "questionmark.circle"
        }
    }

    func resultColor(forUserId userId: Int) -> Color {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked", "Mugged", "Hospitalized":
            return userWasAttacker ? .green : .red
        case "Lost":
            return userWasAttacker ? .red : .green
        case "Stalemate":
            return .orange
        case "Escape":
            return userWasAttacker ? .orange : .green
        case "Assist":
            return .blue
        default:
            return .gray
        }
    }
    
    /// `timestampEnded` is Torn's clock, so `now` should be too (`AppState.serverNow`).
    func timeAgo(at now: Date) -> String {
        guard let ts = timestampEnded else { return "" }
        let diff = Int(now.timeIntervalSince1970) - ts
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }

    var timeAgo: String { timeAgo(at: Date()) }
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

    /// A copy whose `chain.timeout` is an absolute server timestamp. See
    /// `FactionChain.resolvingExpiry(fetchedAt:clock:)`.
    func resolvingChainExpiry(fetchedAt: Date, clock: ServerClock) -> FactionData {
        FactionData(name: name, factionId: factionId, respect: respect,
                    chain: chain.resolvingExpiry(fetchedAt: fetchedAt, clock: clock))
    }
}

/// The `chain` object of v1 `faction/?selections=chain`.
///
/// **Wire semantics (verified live 2026-09-01):** Torn sends `timeout` as the number of
/// **seconds remaining** when the response was built, and `end` as the absolute Unix
/// expiry — `{"current":1,"timeout":146,"start":1788292282,"end":1788292582}` next to a
/// `server_time` of 1788292436. Every consumer in the app (`Chain`, `ChainView`,
/// `FactionView`, the chain-expiring alert, Next Action) compares `timeout` against the
/// server clock as an absolute timestamp, so a raw payload must go through
/// `resolvingExpiry(fetchedAt:clock:)` before it is published. `AppState.fetchFactionData`
/// does that; after it, `timeout == end`.
struct FactionChain: Codable {
    let current: Int
    let max: Int
    /// Raw off the wire: seconds remaining. After `resolvingExpiry`: absolute expiry.
    let timeout: Int
    let cooldown: Int
    /// Absolute Unix expiry as reported by Torn (`nil` when absent or 0).
    let end: Int?

    init(current: Int = 0, max: Int = 0, timeout: Int = 0, cooldown: Int = 0, end: Int? = nil) {
        self.current = current
        self.max = max
        self.timeout = timeout
        self.cooldown = cooldown
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = (try? container.decode(Int.self, forKey: .current)) ?? 0
        max = (try? container.decode(Int.self, forKey: .max)) ?? 0
        timeout = (try? container.decode(Int.self, forKey: .timeout)) ?? 0
        cooldown = (try? container.decode(Int.self, forKey: .cooldown)) ?? 0
        let rawEnd = (try? container.decode(Int.self, forKey: .end)) ?? 0
        end = rawEnd > 0 ? rawEnd : nil
    }

    enum CodingKeys: String, CodingKey {
        case current, max, timeout, cooldown, end
    }

    /// Turns the wire shape (relative `timeout`) into the app shape (absolute `timeout`).
    ///
    /// Prefers Torn's own `end` timestamp; without one, anchors the remaining seconds to
    /// the server clock at the moment the response arrived, the same way `travel.time_left`
    /// and `bar.fulltime` are anchored. An inactive chain (no links or no time left) is
    /// returned unchanged so `timeout` stays 0 and `isActive` stays false.
    func resolvingExpiry(fetchedAt: Date, clock: ServerClock) -> FactionChain {
        guard current > 0, timeout > 0 else { return self }
        let expiry = end ?? clock.serverTimestamp(fetchedAt: fetchedAt, plus: timeout)
        return FactionChain(current: current, max: max, timeout: expiry, cooldown: cooldown, end: expiry)
    }
}

// MARK: - Organized Crime 2.0 (player's own OC via v2 /user?selections=organizedcrime)
//
// Torn migrated every faction to Organized Crimes 2.0 (~Feb 2025). The old v1
// `faction/?selections=crimes` selection now only returns frozen OC-1.0 *history*
// (completed pre-migration crimes, 0 active) and its `initiated` field flipped from
// Bool to Int — so the previous parser silently dropped every crime. We instead read
// the player's OWN current OC from the v2 endpoint: the live, useful signal for a
// menu-bar monitor. Shape verified against a live API response 2026-07-03.
struct OrganizedCrime2: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let difficulty: Int?
    let status: String?          // e.g. "Planning", "Recruiting", "Successful"
    let createdAt: Int?
    let readyAt: Int?            // epoch when the OC becomes executable
    let expiredAt: Int?
    let executedAt: Int?
    let slots: [OCSlot]?

    enum CodingKeys: String, CodingKey {
        case id, name, difficulty, status, slots
        case createdAt = "created_at"
        case readyAt = "ready_at"
        case expiredAt = "expired_at"
        case executedAt = "executed_at"
    }

    init(id: Int, name: String, difficulty: Int? = nil, status: String? = nil,
         createdAt: Int? = nil, readyAt: Int? = nil, expiredAt: Int? = nil,
         executedAt: Int? = nil, slots: [OCSlot]? = nil) {
        self.id = id; self.name = name; self.difficulty = difficulty; self.status = status
        self.createdAt = createdAt; self.readyAt = readyAt; self.expiredAt = expiredAt
        self.executedAt = executedAt; self.slots = slots
    }

    var readyDate: Date? {
        guard let readyAt, readyAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(readyAt))
    }

    /// True once the OC has reached its ready time and hasn't been executed yet.
    /// `readyAt` is an absolute **server** timestamp, so `now` must be Torn's now
    /// (`AppState.serverNow`).
    func isReady(at now: Date) -> Bool {
        guard executedAt == nil, let readyAt, readyAt > 0 else { return false }
        return readyAt <= Int(now.timeIntervalSince1970)
    }

    var isReady: Bool { isReady(at: Date()) }

    var filledSlots: Int { slots?.filter { $0.user != nil }.count ?? 0 }
    var totalSlots: Int { slots?.count ?? 0 }

    /// The signed-in player's progress (0–100) in their slot, if they hold one.
    func myProgress(playerId: Int) -> Double? {
        slots?.first { $0.user?.id == playerId }?.user?.progress
    }
}

struct OCSlot: Codable, Equatable {
    let position: String?
    let checkpointPassRate: Int?
    let user: OCSlotUser?

    enum CodingKeys: String, CodingKey {
        case position, user
        case checkpointPassRate = "checkpoint_pass_rate"
    }

    init(position: String? = nil, checkpointPassRate: Int? = nil, user: OCSlotUser? = nil) {
        self.position = position; self.checkpointPassRate = checkpointPassRate; self.user = user
    }
}

struct OCSlotUser: Codable, Equatable {
    let id: Int?
    let progress: Double?
    let joinedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, progress
        case joinedAt = "joined_at"
    }

    init(id: Int? = nil, progress: Double? = nil, joinedAt: Int? = nil) {
        self.id = id; self.progress = progress; self.joinedAt = joinedAt
    }
}

// MARK: - Daily Refills (v2 /user?selections=refills)
struct Refills: Codable, Equatable {
    let energy: Bool
    let nerve: Bool
    let token: Bool
    let specialCount: Int?

    enum CodingKeys: String, CodingKey {
        case energy, nerve, token
        case specialCount = "special_count"
    }

    init(energy: Bool = false, nerve: Bool = false, token: Bool = false, specialCount: Int? = nil) {
        self.energy = energy; self.nerve = nerve; self.token = token; self.specialCount = specialCount
    }

    /// Refills the player hasn't claimed yet today (the actionable nudge).
    var unclaimed: [String] {
        var out: [String] = []
        if !energy { out.append("Energy") }
        if !nerve { out.append("Nerve") }
        if !token { out.append("Token") }
        return out
    }
}

// MARK: - Notification counters (v2 /user?selections=notifications)

/// The four counters Torn's own header badges are built from.
///
/// This is the cheap way to know there is something waiting. MacTorn used to learn its
/// unread-message count from the row-based `messages` selection, which spends rows against
/// the 50,000-a-day-per-category cap just to produce one integer — so it could only afford
/// to ask every five minutes. `notifications` is point-in-time, costs no rows, needs only a
/// Minimal-access key, and rides the poll MacTorn already makes. It also carries two
/// signals the app previously had no way to see at all: pending awards, and an active
/// competition.
struct TornNotifications: Codable, Equatable, Sendable {
    let messages: Int
    let events: Int
    let awards: Int
    let competition: Int

    init(messages: Int = 0, events: Int = 0, awards: Int = 0, competition: Int = 0) {
        self.messages = messages
        self.events = events
        self.awards = awards
        self.competition = competition
    }

    var total: Int { messages + events + awards + competition }
    var hasAny: Bool { total > 0 }
}

// MARK: - Virus programming (v2 /user/virus)

/// A virus being written, and the instant it finishes.
///
/// `nil` at the response level means no virus is being programmed. Torn gives an absolute
/// Unix timestamp rather than a duration, so the countdown is derived locally and the
/// endpoint only needs re-reading when it lapses — see `AppState.fetchVirusIfNeeded`.
struct VirusProgramming: Codable, Equatable, Sendable {
    let itemID: Int
    let name: String
    /// Absolute Unix timestamp the virus is finished at.
    let until: Int

    init(itemID: Int, name: String, until: Int) {
        self.itemID = itemID
        self.name = name
        self.until = until
    }

    private enum CodingKeys: String, CodingKey { case item, until }
    private enum ItemKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let item = try container.nestedContainer(keyedBy: ItemKeys.self, forKey: .item)
        itemID = try item.decode(Int.self, forKey: .id)
        name = try item.decode(String.self, forKey: .name)
        until = try container.decode(Int.self, forKey: .until)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var item = container.nestedContainer(keyedBy: ItemKeys.self, forKey: .item)
        try item.encode(itemID, forKey: .id)
        try item.encode(name, forKey: .name)
        try container.encode(until, forKey: .until)
    }

    /// Seconds left, measured against the Torn-side clock the caller supplies (issue #46:
    /// every countdown in the app reads through `ServerClock`, never a bare `Date()`).
    /// Never negative — a finished virus reads as zero, not as a countdown running
    /// backwards.
    func secondsRemaining(at serverNow: Date) -> Int {
        max(0, until - Int(serverNow.timeIntervalSince1970))
    }

    func isReady(at serverNow: Date) -> Bool { Int(serverNow.timeIntervalSince1970) >= until }
}

// MARK: - Education (v2 /user?selections=education)
struct EducationStatus: Codable, Equatable {
    let complete: [Int]
    let current: CurrentEducation?

    init(complete: [Int] = [], current: CurrentEducation? = nil) {
        self.complete = complete; self.current = current
    }

    var isStudying: Bool { current?.until != nil }

    /// When the in-progress course finishes; nil if not studying.
    var endsDate: Date? {
        guard let until = current?.until, until > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(until))
    }
}

struct CurrentEducation: Codable, Equatable {
    let id: Int?
    let until: Int?   // epoch when the current course completes
}

// MARK: - Bounty (v2 /user?selections=bounties)
struct Bounty: Codable, Equatable, Identifiable {
    let targetId: Int
    let targetName: String?
    let targetLevel: Int?
    let listerId: Int?
    let listerName: String?     // null when the bounty is anonymous
    let reward: Int
    let reason: String?
    let quantity: Int?
    let isAnonymous: Bool?
    let validUntil: Int?

    // The payload has no stable per-bounty id; a composite key is enough to
    // de-dup "bounty on you" notifications across polls.
    var id: String { "\(targetId)-\(reward)-\(listerId ?? 0)-\(validUntil ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case targetId = "target_id"
        case targetName = "target_name"
        case targetLevel = "target_level"
        case listerId = "lister_id"
        case listerName = "lister_name"
        case reward, reason, quantity
        case isAnonymous = "is_anonymous"
        case validUntil = "valid_until"
    }
}

// MARK: - Faction Ranked War (v2 /faction/rankedwars)
struct RankedWar: Codable, Equatable, Identifiable {
    let id: Int
    let start: Int
    let end: Int
    let target: Int
    let winner: Int?
    let factions: [RankedWarFaction]

    /// Ongoing war: no end timestamp yet. Shape verified live 2026-07-03.
    var isActive: Bool { end == 0 }

    func faction(id: Int) -> RankedWarFaction? { factions.first { $0.id == id } }
    func opponent(of factionId: Int) -> RankedWarFaction? { factions.first { $0.id != factionId } }
}

struct RankedWarFaction: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let score: Int
    let chain: Int?
}

// MARK: - Faction News (v2 /faction/news?cat=main)
struct FactionNews: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let timestamp: Int

    /// News text arrives as HTML (profile/faction links); strip tags and decode entities for display,
    /// matching `TornEvent.cleanEvent`.
    var plainText: String {
        text.strippedHTMLAndDecodedEntities
    }
}

// MARK: - Property Info
//
// Field semantics (verified against real Torn API on 2026-04-18):
// - `cost`: purchase price you paid
// - `marketprice`: current resale value (use for net worth)
// - `status`: residency context. Examples: "Owned by them" (you own it but live elsewhere),
//   "Rented from {user}", "Owned by you and rented to {user}". Empty/missing for default state.
// - `upkeep` / `staffCost`: per-day RATES that ONLY apply when you currently reside in
//   the property. We deliberately do NOT show these — labeling them is too easy to mistake
//   for current debt or unconditional cost.
// - `rented`: object|null in API. Non-null means RENTED OUT to another player.
struct PropertyInfo: Codable, Identifiable {
    let id: Int
    let propertyType: String
    let status: String
    let cost: Int
    let marketprice: Int
    let happy: Int
    let rented: Bool
    let rentDaysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case id = "property_id"
        case propertyType = "property"
        case status
        case cost
        case marketprice
        case happy
        case rented
    }

    private struct RentedInfo: Codable {
        let daysLeft: Int?
        enum CodingKeys: String, CodingKey { case daysLeft = "days_left" }
    }

    init(id: Int = 0, propertyType: String = "", status: String = "", cost: Int = 0, marketprice: Int = 0, happy: Int = 0, rented: Bool = false, rentDaysLeft: Int? = nil) {
        self.id = id
        self.propertyType = propertyType
        self.status = status
        self.cost = cost
        self.marketprice = marketprice
        self.happy = happy
        self.rented = rented
        self.rentDaysLeft = rentDaysLeft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        propertyType = (try? container.decode(String.self, forKey: .propertyType)) ?? ""
        status = (try? container.decode(String.self, forKey: .status)) ?? ""
        cost = (try? container.decode(Int.self, forKey: .cost)) ?? 0
        marketprice = (try? container.decode(Int.self, forKey: .marketprice)) ?? 0
        happy = (try? container.decode(Int.self, forKey: .happy)) ?? 0
        if let rentedInfo = try? container.decode(RentedInfo.self, forKey: .rented) {
            rented = true
            rentDaysLeft = rentedInfo.daysLeft
        } else {
            rented = false
            rentDaysLeft = nil
        }
    }
}

// MARK: - Stock Holdings
struct StockHolding: Codable, Identifiable {
    let stockId: Int
    let totalShares: Int
    let transactions: [StockTransaction]?

    var id: Int { stockId }

    enum CodingKeys: String, CodingKey {
        case stockId = "stock_id"
        case totalShares = "total_shares"
        case transactions
    }

    init(stockId: Int, totalShares: Int, transactions: [StockTransaction]?) {
        self.stockId = stockId
        self.totalShares = totalShares
        self.transactions = transactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stockId = (try? container.decode(Int.self, forKey: .stockId)) ?? 0
        totalShares = (try? container.decode(Int.self, forKey: .totalShares)) ?? 0
        // Torn API returns `transactions` as a dict keyed by transaction_id.
        // Try dict first, fall back to array for forward compatibility.
        if let dict = try? container.decode([String: StockTransaction].self, forKey: .transactions) {
            transactions = Array(dict.values)
        } else if let array = try? container.decode([StockTransaction].self, forKey: .transactions) {
            transactions = array
        } else {
            transactions = nil
        }
    }

    var totalCostBasis: Int {
        guard let txns = transactions else { return 0 }
        return txns.reduce(0) { $0 + ($1.shares * $1.boughtPrice) }
    }

    func marketValue(using metadata: [Int: StockMetadata]) -> Int {
        guard let meta = metadata[stockId] else { return 0 }
        return Int(Double(totalShares) * meta.currentPrice)
    }
}

// MARK: - Stock Metadata (global lookup from torn/?selections=stocks)
struct StockMetadata: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let acronym: String
    let currentPrice: Double

    enum CodingKeys: String, CodingKey {
        case stockId = "stock_id"
        case name
        case acronym
        case currentPrice = "current_price"
    }

    init(id: Int, name: String, acronym: String, currentPrice: Double) {
        self.id = id
        self.name = name
        self.acronym = acronym
        self.currentPrice = currentPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .stockId)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        acronym = (try? container.decode(String.self, forKey: .acronym)) ?? ""
        currentPrice = (try? container.decode(Double.self, forKey: .currentPrice)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stockId)
        try container.encode(name, forKey: .name)
        try container.encode(acronym, forKey: .acronym)
        try container.encode(currentPrice, forKey: .currentPrice)
    }
}

// Note: parsing of `torn/?selections=stocks` is done via JSONSerialization in
// `AppState.parseStocksMetadata(from:logger:)` to be resilient to extra/changing
// fields in the live API response.

struct StockTransaction: Codable {
    let shares: Int
    let boughtPrice: Int
    let timeBought: Int

    enum CodingKeys: String, CodingKey {
        case shares
        case boughtPrice = "bought_price"
        case timeBought = "time_bought"
    }

    init(shares: Int, boughtPrice: Int, timeBought: Int) {
        self.shares = shares
        self.boughtPrice = boughtPrice
        self.timeBought = timeBought
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
    var priceThreshold: Int?
    var lastAlertedPrice: Int?

    // Explicit memberwise initializer
    init(id: Int, name: String, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, lastUpdated: Date?, error: String?, priceThreshold: Int? = nil, lastAlertedPrice: Int? = nil) {
        self.id = id
        self.name = name
        self.lowestPrice = lowestPrice
        self.lowestPriceQuantity = lowestPriceQuantity
        self.secondLowestPrice = secondLowestPrice
        self.lastUpdated = lastUpdated
        self.error = error
        self.priceThreshold = priceThreshold
        self.lastAlertedPrice = lastAlertedPrice
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
        priceThreshold = try container.decodeIfPresent(Int.self, forKey: .priceThreshold)
        lastAlertedPrice = try container.decodeIfPresent(Int.self, forKey: .lastAlertedPrice)
    }

    /// Longest display name a watchlist entry may carry. `MarketWatchService.add`
    /// enforced this on names the user typed; `renamed(to:)` now enforces it on names
    /// that arrive from Torn's item catalog, so there is one rule rather than two.
    static let maximumNameLength = 64

    /// A copy under a different display name. `id` is the identity: renaming an entry
    /// keeps its prices, its threshold and its alert history intact.
    ///
    /// The new name is trimmed and capped exactly as a typed one is. Without that, a
    /// hostile or MITM'd `/v2/torn/items` response could write unbounded server text into
    /// the user's own persisted watchlist through the catalog backfill.
    func renamed(to newName: String) -> WatchlistItem {
        let cleaned = String(
            newName.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WatchlistItem.maximumNameLength)
        )
        return WatchlistItem(id: id,
                      name: cleaned.isEmpty ? name : cleaned,
                      lowestPrice: lowestPrice,
                      lowestPriceQuantity: lowestPriceQuantity,
                      secondLowestPrice: secondLowestPrice,
                      lastUpdated: lastUpdated,
                      error: error,
                      priceThreshold: priceThreshold,
                      lastAlertedPrice: lastAlertedPrice)
    }

    var priceDifference: Int {
        guard secondLowestPrice > 0 && lowestPrice > 0 else { return 0 }
        return secondLowestPrice - lowestPrice
    }

    var isLoading: Bool {
        lowestPrice == 0 && error == nil
    }

    var shouldFirePriceAlert: Bool {
        guard let threshold = priceThreshold, lowestPrice > 0 else { return false }
        guard lowestPrice <= threshold else { return false }
        if let lastAlerter = lastAlertedPrice {
            return lowestPrice < lastAlerter
        }
        return true
    }
}

// MARK: - Update Manager
struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

class UpdateManager {
    static let shared = UpdateManager()

    // Configure your repository here
    private let githubOwner = "pawelorzech"
    private let githubRepo = "MacTorn"

    /// GitHub's API, not Torn's — bypassing the Torn budget-gated `session` on
    /// `AppState` is correct here. The bug was that this was hard-coded to
    /// `URLSession.shared`, so the type had 0% test coverage; injecting it lets tests
    /// substitute a `MockNetworkSession` (issue #56).
    private let session: NetworkSession

    init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }

    /// Hosts a release link may point at.
    ///
    /// `GitHubRelease.htmlUrl` is decoded straight from api.github.com and handed to
    /// `BrowserManager` behind a button labelled "Download Update". `BrowserManager`
    /// checks the scheme, which stops `NSWorkspace` opening arbitrary handlers, but any
    /// https host still passes — so a compromised or MITM'd GitHub response could send the
    /// user somewhere else entirely under MacTorn's own update prompt.
    static let allowedReleaseHosts: Set<String> = ["github.com", "www.github.com"]

    /// Whether a release's link points somewhere MacTorn is willing to send the user.
    static func isTrustedReleaseURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return allowedReleaseHosts.contains(host)
    }

    func checkForUpdates(currentVersion: String) async -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            // Compare versions. Strip only a LEADING "v" prefix — release tags can
            // legitimately contain other "v" characters (e.g. "v1.2.3-victory"), and
            // `replacingOccurrences(of: "v", with: "")` used to strip every one of
            // them, mangling the version string past the parseable components.
            let versionString = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            if isVersion(versionString, greaterThan: currentVersion) {
                return release
            }

        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
        }

        return nil
    }
    
    /// The leading run of digits in a dot-separated component, e.g. "3-victory" -> 3.
    /// A component that starts with a non-digit (or is empty) contributes 0 rather
    /// than being dropped, so a trailing suffix (build metadata, a named release)
    /// can't shift later components out of alignment.
    private func leadingNumericPrefix(_ component: Substring) -> Int {
        Int(component.prefix { $0.isNumber }) ?? 0
    }

    private func isVersion(_ newVersion: String, greaterThan currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").map(leadingNumericPrefix)
        let currentComponents = currentVersion.split(separator: ".").map(leadingNumericPrefix)

        let maxLength = max(newComponents.count, currentComponents.count)
        
        for i in 0..<maxLength {
            let new = i < newComponents.count ? newComponents[i] : 0
            let current = i < currentComponents.count ? currentComponents[i] : 0
            
            if new > current {
                return true
            } else if new < current {
                return false
            }
        }
        
        return false
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

    /// Fast poll: only point-in-time selections. Deliberately EXCLUDES the row-based
    /// cloud categories (`events`, `attacks`) — those count against Torn's 50,000-
    /// rows/day-per-category cap (error code 14 "Daily read limit reached"), which is
    /// a separate limit from the 100-requests/minute rate limit. Pulling a full
    /// `events`/`attacks` page every 30 s, 24/7 blows past 50k rows/day ~5×. Row-based
    /// data now lives on `activityURL` below (slow cadence + hard row limit).
    static let selections = "basic,bars,cooldowns,travel,profile,money,battlestats,properties,stocks"

    /// Slow poll: the row-based / display-only categories. Capped with `limit` and
    /// fetched every few minutes so each category stays well under 50k rows/day.
    ///
    /// `messages` used to be here purely to produce one unread count, at the price of 25
    /// rows a call against the daily cap. That count now comes free from the point-in-time
    /// `notifications` selection on the v2 poll, so this call carries a third fewer rows.
    static let activitySelections = "events,attacks"
    /// Rows per category per activity call. The UI only ever shows a handful, so 25 is
    /// generous; at a 5-minute cadence that is 25 × 288 ≈ 7,200 rows/day/category.
    static let activityRowLimit = 25

    /// Build a Torn API URL with proper percent-encoding via URLComponents/URLQueryItem.
    /// String interpolation (the previous approach) would silently mangle keys that
    /// happen to contain `&`, `=`, or whitespace if pasted with junk.
    ///
    /// Every request carries `comment=MacTorn` (see `TornAPIClient.comment`), so the
    /// key owner can tell MacTorn's traffic apart from every other tool sharing their
    /// key in Torn's own key log.
    private static func build(_ urlString: String, query: [String: String]) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        var query = query
        query["comment"] = TornAPIClient.comment
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return comps.url
    }

    static func url(for apiKey: String) -> URL? {
        build(baseURL, query: ["selections": selections, "key": apiKey])
    }

    /// Row-based activity call (events + messages + attacks) with a hard `limit` so
    /// it can never exhaust the 50k-rows/day category budget. Polled slowly.
    static func activityURL(for apiKey: String) -> URL? {
        build(baseURL, query: ["selections": activitySelections,
                               "limit": String(activityRowLimit),
                               "key": apiKey])
    }

    static func factionURL(for apiKey: String) -> URL? {
        // `crimes` dropped: OC 1.0 is dead (frozen history + Int/Bool decode break).
        // The player's own OC 2.0 comes from `userV2URL` instead.
        build(factionURL, query: ["selections": "basic,chain", "key": apiKey])
    }

    /// Combined API v2 `user` call. v2 accepts multiple selections in one request
    /// (verified live), so a single call covers organized crime, refills, education
    /// and bounties. v1 selections stay on the frozen v1 endpoints above.
    static let userV2Selections = "organizedcrime,refills,education,bounties,notifications"
    static func userV2URL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/user",
              query: ["selections": userV2Selections, "key": apiKey])
    }

    /// Official key-info endpoint (Etap C). Returns the key's access level/type, the
    /// owner's IDs, and the per-category selections the key can read — the authoritative
    /// source for onboarding validation. Called on demand only (never polled).
    static func keyInfoURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/key/info", query: ["key": apiKey])
    }

    /// Ranked wars use a dedicated v2 path (the combined `?selections=rankedwars,news`
    /// call returns code 21 because `news` requires a `cat` parameter).
    static func factionRankedWarsURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/faction/rankedwars", query: ["key": apiKey])
    }

    /// Faction news requires a category (`cat`); `main` is the general feed.
    /// `news` is a row-based cloud category (counts against the 50k-rows/day cap),
    /// so cap it with `limit` on top of the slow poll cadence.
    static func factionNewsURL(for apiKey: String, cat: String = "main") -> URL? {
        build("https://api.torn.com/v2/faction/news",
              query: ["cat": cat, "limit": String(activityRowLimit), "key": apiKey])
    }

    /// Item-market listings for one item.
    ///
    /// `bazaar` used to ride along here. It no longer carries prices: on API v2 the
    /// per-item `bazaar` selection returns a *directory* of the player bazaars stocking
    /// the item — `{id, name, is_open, weekly_customers}` — with no cost or quantity
    /// anywhere in the shape (`BazaarResponseSpecialized` in Torn's OpenAPI document,
    /// spec 6.13.1). Torn does not expose per-item bazaar prices on v2 at all, so asking
    /// for it bought a larger payload and nothing else.
    static func marketURL(itemId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/market/\(itemId)/itemmarket",
              query: ["key": apiKey])
    }

    /// Virus programming has no combinable `/user` selection — it is absent from Torn's
    /// `UserSelectionName` enum — so it needs its own path. Read rarely: the response is an
    /// absolute finish timestamp, and the countdown between reads is derived locally.
    static func userVirusURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/user/virus", query: ["key": apiKey])
    }

    /// The global item catalog. `cat` is deliberately omitted: the default category is
    /// "All", which is the only one that returns every item, and its details are stripped —
    /// exactly the trade MacTorn wants, since it needs names and nothing else.
    static func tornItemsURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/torn/items", query: ["key": apiKey])
    }

    static func tornStocksURL(for apiKey: String) -> URL? {
        build(tornURL, query: ["selections": "stocks", "key": apiKey])
    }

    static func forumThreadURL(threadId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(threadId)/thread", query: ["key": apiKey])
    }

    /// Unlike a single thread, a category listing accepts `limit` — and defaults to 100.
    /// Sending the cap explicitly is what makes the row accounting honest: without it the
    /// registry booked 20 rows for a call that was pulling five times that.
    static func forumCategoryThreadsURL(categoryId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(categoryId)/threads",
              query: ["key": apiKey, "limit": String(forumCategoryRowLimit)])
    }

    /// Threads fetched per category check. The alert only needs to spot ids it has not
    /// seen, and a busy category turns over far fewer than 20 threads in a poll interval.
    static let forumCategoryRowLimit = 20
}

// MARK: - Request construction

/// The one place MacTorn turns a built Torn API URL into the request it actually sends.
///
/// Two things happen here that every call site needs and none of them should re-implement:
///
///  1. **The key leaves the URL on API v2.** Torn's OpenAPI document declares an
///     `Authorization: ApiKey <key>` header and states the `key` query parameter "is not
///     required … when passing the API key via the Authorization header". A key in a
///     query string is a key in every URL that gets logged, cached, or attached to a
///     crash report; a key in a header is not. v1 has no documented header form, so v1
///     URLs keep `key=` — `tornRedactedURL` remains the guard there.
///  2. **The URL cache is bypassed.** Torn may itself serve a response up to ~30 s old;
///     letting `URLCache` stack a second layer on top of that is how a countdown ends up
///     minutes stale.
enum TornAPIClient {
    /// Sent as `comment` on every request. Torn surfaces it in the key owner's key log
    /// (`/v2/key/log`), which is how a user tells MacTorn's calls apart from those of
    /// every other tool they have handed the same key to.
    static let comment = "MacTorn"

    /// Header name Torn documents for key auth.
    static let authorizationHeader = "Authorization"

    /// True for the `/v2/...` paths, the only ones where header auth is documented.
    static func usesHeaderAuth(_ url: URL) -> Bool {
        url.path.hasPrefix("/v2/") || url.path == "/v2"
    }

    /// Builds the request for `url`, relocating the key into the Authorization header
    /// where Torn supports it. Returns the URL unchanged when it carries no `key` item.
    static func request(for url: URL) -> URLRequest {
        guard usesHeaderAuth(url),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let key = items.first(where: { $0.name == "key" })?.value,
              !key.isEmpty
        else {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return request
        }

        let remaining = items.filter { $0.name != "key" }
        comps.queryItems = remaining.isEmpty ? nil : remaining
        var request = URLRequest(url: comps.url ?? url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("ApiKey \(key)", forHTTPHeaderField: authorizationHeader)
        return request
    }
}

/// Returns a log-safe description of an api.torn.com URL: scheme://host/path?[sorted-query-keys].
/// Strips every query *value* — Torn API keys travel in the `key` query param, so any
/// `absoluteString` interpolated into a log call would leak the key into os_log / Console.app.
/// Always use this instead of `url.absoluteString` in logger statements.
func tornRedactedURL(_ url: URL) -> String {
    let scheme = url.scheme ?? "?"
    let host = url.host ?? "?"
    let path = url.path
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let keys = (comps?.queryItems?.map(\.name).sorted() ?? []).joined(separator: ",")
    if keys.isEmpty {
        return "\(scheme)://\(host)\(path)"
    }
    return "\(scheme)://\(host)\(path)?[\(keys)]"
}

/// Extracts a Torn API error message from a parsed top-level JSON object, accepting
/// BOTH error envelopes Torn uses. Torn always returns HTTP 200 even on API errors,
/// so the envelope — not the status code — is the source of truth.
///
///   • v1 (legacy `/user`, `/faction`, `/torn`):  `{"error": {"code": Int, "error": String}}`
///   • v2 (`/v2/...` market, forum):              `{"code": Int, "error": String}`
///
/// The v2 form (per the Torn OpenAPI spec: ErrorTooManyRequests, ErrorIncorrectKey, …)
/// carries `code` and `error` as sibling top-level keys with `error` as a *string*.
/// Parsing only the v1 shape silently swallows every v2 error (rate-limit, bad key,
/// access level), so v2 call sites surfaced garbage ("No listings", "Unknown" thread)
/// instead of the real failure. This helper detects either shape.
///
/// Returns the human-readable message, or nil if `json` is not an error envelope.
func tornAPIErrorMessage(in json: [String: Any]) -> String? {
    // v1 envelope: `error` is a nested object carrying the message.
    if let nested = json["error"] as? [String: Any], let message = nested["error"] as? String {
        return message
    }
    // v2 envelope: `code` + `error` are sibling top-level keys, `error` a String.
    if json["code"] != nil, let message = json["error"] as? String {
        return message
    }
    return nil
}

/// Like `tornAPIErrorMessage`, but returns the *classified* error (Etap B) so callers can
/// react to its kind — halt on a permanent key/permission error (codes 2/16/18), pause a
/// category on the daily-row-limit (14), back off on transient ones. Returns nil when the
/// payload is not an error envelope. Recognises both v1 and v2 shapes.
func tornAPIError(in json: [String: Any]) -> TornAPIError? {
    // v1 envelope: { "error": { "code": Int, "error": String } }
    if let nested = json["error"] as? [String: Any] {
        let code = nested["code"] as? Int ?? 0
        let message = nested["error"] as? String ?? ""
        return TornAPIError.classify(code: code, message: message)
    }
    // v2 envelope: { "code": Int, "error": String }
    if let code = json["code"] as? Int, let message = json["error"] as? String {
        return TornAPIError.classify(code: code, message: message)
    }
    return nil
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

struct ForumThreadResponse: Codable {
    let id: Int
    let title: String
    let posts: Int
    let lastPostTime: Int?
    let isLocked: Bool?
    let author: ForumAuthor?

    enum CodingKeys: String, CodingKey {
        case id, title, posts
        case lastPostTime = "last_post_time"
        case isLocked = "is_locked"
        case author
    }
}

struct ForumAuthor: Codable {
    let id: Int
    let username: String
}

struct ForumThreadSummary: Codable {
    let id: Int
    let title: String
    let posts: Int
    let author: ForumAuthor?
    let firstPostTime: Int?
    let lastPostTime: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, posts, author
        case firstPostTime = "first_post_time"
        case lastPostTime = "last_post_time"
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

// MARK: - Menu Bar Display

/// What the menu bar label should render at any given moment.
/// Priority: traveling > hospital > jail > soonest cooldown > fallback icon.
///
/// The cases carry **meaning** (destination name, cooldown kind), not presentation.
/// The flag/emoji glyphs are derived at render time. Storing only the glyph — as this
/// enum used to — made the state unspeakable: VoiceOver read "airplane, flag of United
/// Kingdom, 2 colon 35" because there was no name left in the model to say instead.
enum MenuBarDisplay: Equatable {
    case traveling(destination: String?, seconds: Int)
    case hospitalAbroad(destination: String?, seconds: Int)
    case hospitalAtHome(seconds: Int)
    case jail(seconds: Int)
    case cooldown(kind: CooldownKind, seconds: Int)
    case fallbackIcon

    /// Spoken description for the menu-bar label — the app's only always-visible surface.
    /// Pure function of the case, so it is unit-testable without a running menu bar.
    var accessibilityDescription: String {
        switch self {
        case .traveling(let destination, let seconds):
            let place = destination.map { " to \($0)" } ?? ""
            return "Traveling\(place), arriving in \(Self.spokenDuration(seconds))"
        case .hospitalAbroad(let destination, let seconds):
            let place = destination.map { " in \($0)" } ?? " abroad"
            return "In hospital\(place), \(Self.spokenDuration(seconds)) remaining"
        case .hospitalAtHome(let seconds):
            return "In hospital, \(Self.spokenDuration(seconds)) remaining"
        case .jail(let seconds):
            return "In jail, \(Self.spokenDuration(seconds)) remaining"
        case .cooldown(let kind, let seconds):
            return "\(kind.displayName) cooldown, \(Self.spokenDuration(seconds)) remaining"
        case .fallbackIcon:
            return "MacTorn — no active timer"
        }
    }

    /// "1 hour 4 minutes", "2 minutes 35 seconds", "12 seconds". Zero-valued leading
    /// components are dropped so the phrase stays short enough to be useful in speech.
    static func spokenDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0 seconds" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        func unit(_ value: Int, _ name: String) -> String {
            "\(value) \(name)\(value == 1 ? "" : "s")"
        }

        if hours > 0 {
            return minutes > 0
                ? "\(unit(hours, "hour")) \(unit(minutes, "minute"))"
                : unit(hours, "hour")
        }
        if minutes > 0 {
            return secs > 0
                ? "\(unit(minutes, "minute")) \(unit(secs, "second"))"
                : unit(minutes, "minute")
        }
        return unit(secs, "second")
    }
}
