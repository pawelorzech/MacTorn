import Foundation

// Wire models for the optional API v2 modules (OpenAPI 6.13.8).
struct RecruitingCrime: Decodable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let slots: [Slot]
    struct Slot: Decodable {
        let position: String
        let positionInfo: Position
        let checkpointPassRate: Int
        let user: Participant?
        struct Position: Decodable { let id: String; let label: String }
        enum CodingKeys: String, CodingKey {
            case position, user
            case positionInfo = "position_info", checkpointPassRate = "checkpoint_pass_rate"
        }
    }
}
struct Participant: Decodable { let id: Int; let name: String? }
struct StockV2: Decodable, Identifiable {
    let id: Int
    let shares: Int
    let bonus: Bonus
    let transactions: [Transaction]
    struct Bonus: Decodable { let available: Bool; let increment: Int; let progress: Int; let frequency: Int }
    struct Transaction: Decodable { let id: Int; let shares: Int; let price: Double; let timestamp: Int }
    var costBasis: Double { transactions.reduce(0) { $0 + Double($1.shares) * $1.price } }
}
struct StockReferenceV2: Decodable, Identifiable {
    let id: Int
    let name: String
    let acronym: String
    let market: Market
    let bonus: Bonus
    struct Market: Decodable { let price: Double }
    struct Bonus: Decodable { let passive: Bool; let frequency: Int; let requirement: Int; let description: String }
}
/// One struct for all four `UserCompetitionResponse` variants (discriminated by `name`);
/// each variant fills only its own optionals.
struct CompetitionV2: Decodable {
    let name: String
    let score: Int?          // Elimination, Easter Egg Hunt
    let attacks: Int?
    let team: String?
    let teamId: Int?
    let status: String?      // Rock, Paper, Scissors: rock | paper | scissors
    let hp: HP?
    let treatsCollected: Int? // Halloween
    let basket: Basket?
    let total: Int?          // Easter Egg Hunt
    struct HP: Decodable { let current: Int; let maximum: Int }
    struct Basket: Decodable { let id: Int; let name: String }
    enum CodingKeys: String, CodingKey {
        case name, score, attacks, team, status, hp, basket, total
        case teamId = "team_id", treatsCollected = "treats_collected"
    }
    var isElimination: Bool { name == "Elimination" }
}
struct EliminationTeam: Decodable, Identifiable {
    let id: Int
    let name: String
    let participantsLeft: Int
    let position: Int
    let score: Int
    let lives: Int
    let eliminated: Bool
    let attackingSummary: [AttackSummary]
    struct AttackSummary: Decodable {
        let teamId: Int
        let attacks: Int
        enum CodingKeys: String, CodingKey { case attacks; case teamId = "team_id" }
    }
    enum CodingKeys: String, CodingKey {
        case id, name, position, score, lives, eliminated
        case participantsLeft = "participants_left", attackingSummary = "attacking_summary"
    }
}
struct TradeV2: Decodable, Identifiable {
    let id: Int
    let user: Participant
    let trader: Participant
    let description: String
    let completedAt: Int?
    let expiresAt: Int?
    let modifiedAt: Int?
    enum CodingKeys: String, CodingKey {
        case id, user, trader, description
        case completedAt = "completed_at", expiresAt = "expires_at", modifiedAt = "modified_at"
    }
    var signature: String { "\(modifiedAt ?? 0):\(completedAt ?? 0):\(expiresAt ?? 0):\(description)" }
}
struct ShopItem: Decodable, Identifiable {
    let id: Int
    let name: String
    let value: Value
    struct Value: Decodable {
        let marketPrice: Int
        let shops: [Shop]
        enum CodingKeys: String, CodingKey { case shops; case marketPrice = "market_price" }
    }
    struct Shop: Decodable {
        let country: String
        let shop: String
        let buyPrice: Int?
        let sellPrice: Int?
        enum CodingKeys: String, CodingKey { case country, shop; case buyPrice = "buy_price", sellPrice = "sell_price" }
    }
}

enum WarfareCategory: String, CaseIterable, Identifiable {
    case ranked = "warfareranked", raids = "warfareraids", territory = "warfareterritory"
    case chains = "warfarechains", bombs = "dirtybombs"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ranked: return "Ranked wars"
        case .raids: return "Raids"
        case .territory: return "Territory wars"
        case .chains: return "Completed chains"
        case .bombs: return "Dirty bombs"
        }
    }
}
struct WarfareEntry: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let timestamp: Int
}
struct WarfarePage {
    let entries: [WarfareEntry]
    let nextTo: Int?
    // Never follow server-provided URLs with a key: extract only the paging timestamp.
    static func parse(_ json: [String: Any], category: WarfareCategory) -> WarfarePage? {
        guard let rows = json[category.rawValue] as? [[String: Any]] else { return nil }
        var entries: [WarfareEntry] = []
        for row in rows {
            guard let id = row["id"] as? Int else { return nil }
            let faction = row["faction"] as? [String: Any]
            let aggressor = row["aggressor"] as? [String: Any]
            let defender = row["defender"] as? [String: Any]
            let factions = row["factions"] as? [[String: Any]]
            let names = factions?.compactMap { $0["name"] as? String }.joined(separator: " vs ")
            let title = names ?? [aggressor?["name"] as? String, defender?["name"] as? String]
                .compactMap { $0 }.joined(separator: " vs ")
            let end = row["end"] as? Int
            let timestamp = row["start"] as? Int ?? row["detonated_at"] as? Int ?? 0
            var detail = end == nil || end == 0 ? "Ongoing" : "Completed"
            if let result = row["result"] as? String { detail = result }
            if let chain = row["chain"] as? Int { detail = "\(chain) hits" }
            if let lost = faction?["respect_lost"] as? Int { detail = "\(lost) respect lost" }
            entries.append(WarfareEntry(id: id, title: title.isEmpty ? (faction?["name"] as? String ?? category.title) : title,
                                        detail: detail, timestamp: timestamp))
        }
        let links = (json["_metadata"] as? [String: Any])?["links"] as? [String: Any]
        let next = (links?["next"] as? String).flatMap { URLComponents(string: $0) }?
            .queryItems?.first(where: { $0.name == "to" })?.value.flatMap(Int.init)
        return WarfarePage(entries: entries, nextTo: next)
    }
}

struct RecruitingResponse: Decodable { let organizedcrimes: [RecruitingCrime] }
struct StocksV2Response: Decodable { let stocks: [StockV2] }
struct StockReferencesResponse: Decodable { let stocks: [StockReferenceV2] }
struct CompetitionResponse: Decodable { let competition: CompetitionV2? }
struct TornCalendarResponse: Decodable {
    let calendar: Calendar
    struct Calendar: Decodable { let competitions: [CalendarActivity]; let events: [CalendarActivity] }
}
struct UserCalendarResponse: Decodable {
    let calendar: Calendar
    struct Calendar: Decodable { let startTime: String?; enum CodingKeys: String, CodingKey { case startTime = "start_time" } }
}
struct CalendarActivity: Decodable {
    let title: String
    let description: String
    let start: Int
    let end: Int
    let fixedStartTime: Bool?
    enum CodingKeys: String, CodingKey { case title, description, start, end; case fixedStartTime = "fixed_start_time" }
}
/// An activity with trustworthy dates. Torn reports activities already past this year with
/// `start` moved to NEXT year's occurrence while `end` stays in this year (`end < start`);
/// the duration then is `end - (start shifted back a year)` and the occurrence ends at
/// `start + duration`.
struct CalendarEntry: Equatable {
    let title: String
    let isCompetition: Bool
    let start: Date
    let end: Date

    /// `personalOffset` (seconds after 00:00 TCT) applies to activities that are not fixed-time.
    init(_ raw: CalendarActivity, isCompetition: Bool, personalOffset: TimeInterval?) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var start = Date(timeIntervalSince1970: TimeInterval(raw.start))
        var end = Date(timeIntervalSince1970: TimeInterval(raw.end))
        if end < start {
            let previous = utc.date(byAdding: .year, value: -1, to: start) ?? start
            end = start.addingTimeInterval(max(0, end.timeIntervalSince(previous)))
        }
        if raw.fixedStartTime == false, let personalOffset {
            start.addTimeInterval(personalOffset); end.addTimeInterval(personalOffset)
        }
        self.title = raw.title; self.isCompetition = isCompetition; self.start = start; self.end = end
    }

    /// "HH:MM TCT" -> seconds after midnight; anything else -> nil (no shift).
    static func offset(from startTime: String?) -> TimeInterval? {
        guard let startTime else { return nil }
        let parts = startTime.split(separator: " ")
        guard parts.count == 2, parts[1] == "TCT" else { return nil }
        let clock = parts[0].split(separator: ":")
        guard clock.count == 2, let hours = Int(clock[0]), let minutes = Int(clock[1]),
              (0..<24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60)
    }

    /// Activities running at `now` (soonest end first) and the next `limit` to start.
    static func select(_ entries: [CalendarEntry], now: Date, limit: Int = 3) -> (active: [CalendarEntry], upcoming: [CalendarEntry]) {
        let active = entries.filter { $0.start <= now && now < $0.end }.sorted { $0.end < $1.end }
        let upcoming = entries.filter { $0.start > now }.sorted { $0.start < $1.start }.prefix(limit)
        return (active, Array(upcoming))
    }
}
struct EliminationResponse: Decodable { let elimination: [EliminationTeam] }
struct TradesResponse: Decodable { let trades: [TradeV2] }
struct ShopsResponse: Decodable { let items: [ShopItem] }

struct TradeDetailResponse: Decodable {
    let trade: Detail
    struct Detail: Decodable { let id: Int; let items: [TradeDetailItem] }
}
struct TradeDetailItem: Decodable {
    let userId: Int
    let type: String
    let details: Details
    struct Details: Decodable {
        let id: Int?
        let name: String?
        let amount: Int?
        let days: Int?
    }
    enum CodingKeys: String, CodingKey { case type, details; case userId = "user_id" }
    var summary: String {
        let label = details.name ?? details.id.map { "#\($0)" } ?? ""
        let quantity = details.amount.map { " × \($0.formatted())" } ?? details.days.map { " \($0) days" } ?? ""
        return "\(type) \(label)\(quantity) · Player #\(userId)"
    }
}
