import Foundation

extension TornEndpointRegistry {
    static let companion: [TornEndpoint] = [
        companionEndpoint("user.recruiting", path: "user/organizedcrimes", capability: "organizedcrimes", level: .minimal,
                          title: "Open OC slots", purpose: "Recruiting crimes and empty roles matching your CPR filter.", seconds: 300, faction: true),
        companionEndpoint("user.stocksv2", path: "user/stocks", capability: "stocks", level: .limited,
                          title: "Stock bonuses", purpose: "Holdings, cost basis and collectible stock bonuses.", seconds: 300),
        companionEndpoint("torn.stocksv2", path: "torn/stocks", capability: "stocks", level: .publicOnly,
                          title: "Stock prices and benefits", purpose: "Stock names, prices and benefit requirements.", seconds: 300, budget: .metadata),
        companionEndpoint("user.competition", path: "user/competition", capability: "competition", level: .publicOnly,
                          title: "Current competition", purpose: "Current event and your team, score and attacks.", seconds: 60),
        companionEndpoint("torn.elimination", path: "torn/elimination", capability: "elimination", level: .publicOnly,
                          title: "Elimination teams", purpose: "Team standings and attacks in the last completed minute; only during Elimination.", seconds: 60),
        companionEndpoint("user.trades", path: "user/trades", capability: "trades", level: .limited,
                          title: "Active trades", purpose: "Ongoing exchanges and change alerts.", seconds: 120, query: ["cat": "ongoing"]),
        companionEndpoint("user.trade", path: "user/{param}/trade", capability: "trade", level: .limited,
                          title: "Trade details", purpose: "Items offered by each participant in a trade; loaded on demand.", seconds: 30),
        companionEndpoint("torn.shops", path: "torn/items", capability: "items", level: .publicOnly,
                          title: "Travel shop catalog", purpose: "Country shop prices and catalog market values; no live stock guarantee.", seconds: 604800, budget: .metadata),
    ] + WarfareCategory.allCases.map { category in
        companionEndpoint("faction.\(category.rawValue)", path: "faction/\(category.rawValue)", capability: category.rawValue,
                          level: .publicOnly, title: category.title, purpose: "Conflict history, loaded on demand with bounded pages.", seconds: 300,
                          query: category == .chains ? ["cat": "complete", "sort": "DESC"] : (category == .bombs ? [:] : ["sort": "DESC"]),
                          rows: category == .bombs ? nil : 20, budget: .faction)
    }

    private static func companionEndpoint(_ id: String, path: String, capability: String,
        level: TornKeyAccessLevel, title: String, purpose: String, seconds: TimeInterval,
        query: [String: String] = [:], rows: Int? = nil, budget: TornBudgetCategory = .core,
        faction: Bool = false) -> TornEndpoint {
        TornEndpoint(id: id, name: title, version: .v2, path: "https://api.torn.com/v2/\(path)",
                     selections: [], extraQuery: query, minimumAccessLevel: level, purpose: purpose,
                     cadence: id.hasPrefix("faction.") ? "On demand" : "Opt-in; at least \(Int(seconds))s between background reads",
                     dataShape: rows == nil ? .pointInTime : .rowBased, recordLimit: rows,
                     sendsLimitQuery: rows != nil, budget: budget,
                     critical: false, requiredCapabilities: [capability], requiresFaction: faction)
    }
}
