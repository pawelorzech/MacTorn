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
    let serverTimestamp: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, status, chain
        case events, messages, error
        case serverTimestamp = "timestamp"
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

enum CooldownKind: CaseIterable {
    case drug, booster, medical

    var emoji: String {
        switch self {
        case .drug:    return "💊"
        case .booster: return "🧪"
        case .medical: return "🩹"
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
            drugEndsAt: cooldowns.drug > 0 ? anchor + cooldowns.drug : 0,
            boosterEndsAt: cooldowns.booster > 0 ? anchor + cooldowns.booster : 0,
            medicalEndsAt: cooldowns.medical > 0 ? anchor + cooldowns.medical : 0
        )
    }

    func endsAt(_ kind: CooldownKind) -> Int {
        switch kind {
        case .drug:    return drugEndsAt
        case .booster: return boosterEndsAt
        case .medical: return medicalEndsAt
        }
    }

    func remainingSeconds(_ kind: CooldownKind) -> Int {
        let target = endsAt(kind)
        guard target > 0 else { return 0 }
        return max(0, target - Int(Date().timeIntervalSince1970))
    }

    func soonestActive() -> (kind: CooldownKind, seconds: Int)? {
        CooldownKind.allCases
            .map { (kind: $0, seconds: remainingSeconds($0)) }
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
    func merged(with other: CooldownEnds, toleranceSeconds: Int = 3) -> CooldownEnds {
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

    /// Calculate remaining seconds based on fetch time (for live countdown)
    func remainingSeconds(from fetchTime: Date) -> Int {
        // Primary: Use timestamp directly if available (more accurate)
        if let timestamp = timestamp, timestamp > 0 {
            let now = Int(Date().timeIntervalSince1970)
            return max(0, timestamp - now)
        }

        // Fallback: Use timeLeft with fetchTime offset (backward compatibility)
        guard let timeLeft = timeLeft, timeLeft > 0 else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(fetchTime))
        return max(0, timeLeft - elapsed)
    }

    /// Calculate flight progress (0.0 to 1.0) based on fetch time
    func flightProgress(from fetchTime: Date) -> Double {
        guard let departed = departed, let timestamp = timestamp else { return 0 }
        let totalDuration = timestamp - departed
        guard totalDuration > 0 else { return 0 }
        let remaining = remainingSeconds(from: fetchTime)
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

    /// Approximate flight time in minutes
    var flightTimeMinutes: Int {
        switch self {
        case .mexico: return 26
        case .caymanIslands: return 35
        case .canada: return 41
        case .hawaii: return 134
        case .unitedKingdom: return 159
        case .argentina: return 167
        case .switzerland: return 175
        case .japan: return 225
        case .china: return 242
        case .uae: return 271
        case .southAfrica: return 297
        }
    }

    var flightTimeFormatted: String {
        let hours = flightTimeMinutes / 60
        let minutes = flightTimeMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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

// MARK: - Organized Crime
struct OrganizedCrime: Codable, Identifiable {
    let crimeId: Int
    let crimeName: String
    let participants: [OCParticipant]
    let timeStarted: Int
    let timeReady: Int
    let timeLeft: Int
    let initiated: Bool
    let plannerId: Int?
    let plannerName: String?

    var id: Int { crimeId }

    enum CodingKeys: String, CodingKey {
        case crimeId = "crime_id"
        case crimeName = "crime_name"
        case participants
        case timeStarted = "time_started"
        case timeReady = "time_ready"
        case timeLeft = "time_left"
        case initiated
        case plannerId = "planner_id"
        case plannerName = "planner_name"
    }

    init(crimeId: Int, crimeName: String, participants: [OCParticipant], timeStarted: Int, timeReady: Int, timeLeft: Int, initiated: Bool, plannerId: Int?, plannerName: String?) {
        self.crimeId = crimeId
        self.crimeName = crimeName
        self.participants = participants
        self.timeStarted = timeStarted
        self.timeReady = timeReady
        self.timeLeft = timeLeft
        self.initiated = initiated
        self.plannerId = plannerId
        self.plannerName = plannerName
    }

    var isReady: Bool {
        timeLeft <= 0 && initiated
    }

    var readyDate: Date? {
        guard timeReady > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timeReady))
    }
}

struct OCParticipant: Codable {
    let description: String?
    let state: String?
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
    
    func checkForUpdates(currentVersion: String) async -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            // Compare versions
            let versionString = release.tagName.replacingOccurrences(of: "v", with: "")
            
            if isVersion(versionString, greaterThan: currentVersion) {
                return release
            }
            
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func isVersion(_ newVersion: String, greaterThan currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
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
    static let selections = "basic,bars,cooldowns,travel,profile,events,messages,money,battlestats,attacks,properties,stocks"

    /// Build a Torn API URL with proper percent-encoding via URLComponents/URLQueryItem.
    /// String interpolation (the previous approach) would silently mangle keys that
    /// happen to contain `&`, `=`, or whitespace if pasted with junk.
    private static func build(_ urlString: String, query: [String: String]) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return comps.url
    }

    static func url(for apiKey: String) -> URL? {
        build(baseURL, query: ["selections": selections, "key": apiKey])
    }

    static func factionURL(for apiKey: String) -> URL? {
        build(factionURL, query: ["selections": "basic,chain,crimes", "key": apiKey])
    }

    static func marketURL(itemId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/market/\(itemId)",
              query: ["selections": "itemmarket,bazaar", "key": apiKey])
    }

    static func tornStocksURL(for apiKey: String) -> URL? {
        build(tornURL, query: ["selections": "stocks", "key": apiKey])
    }

    static func forumThreadURL(threadId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(threadId)/thread", query: ["key": apiKey])
    }

    static func forumCategoryThreadsURL(categoryId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(categoryId)/threads", query: ["key": apiKey])
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

struct ForumWatchConfig: Codable {
    var factionForumAutoMonitor: Bool
    var factionForumCategoryId: Int?
    var pollingIntervalSeconds: Int
    var knownFactionThreadIds: Set<Int>

    init(factionForumAutoMonitor: Bool = false, factionForumCategoryId: Int? = nil, pollingIntervalSeconds: Int = 180, knownFactionThreadIds: Set<Int> = []) {
        self.factionForumAutoMonitor = factionForumAutoMonitor
        self.factionForumCategoryId = factionForumCategoryId
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.knownFactionThreadIds = knownFactionThreadIds
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

// MARK: - Menu Bar Display

/// What the menu bar label should render at any given moment.
/// Priority: traveling > hospital > jail > soonest cooldown > fallback icon.
enum MenuBarDisplay: Equatable {
    case traveling(flag: String, seconds: Int)
    case hospitalAbroad(flag: String, seconds: Int)
    case hospitalAtHome(seconds: Int)
    case jail(seconds: Int)
    case cooldown(emoji: String, seconds: Int)
    case fallbackIcon
}
