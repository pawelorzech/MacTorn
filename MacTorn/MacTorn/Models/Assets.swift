import Foundation

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

    var totalCostBasis: Int? {
        guard let txns = transactions else { return 0 }
        return NumericSafety.optionalTotal(txns.map { NumericSafety.product($0.shares, $0.boughtPrice) })
    }

    func marketValue(using metadata: [Int: StockMetadata]) -> Int? {
        guard let meta = metadata[stockId] else { return 0 }
        guard totalShares >= 0, StockMetadata.isValidPrice(meta.currentPrice) else { return nil }
        return NumericSafety.integerAmount(Double(totalShares) * meta.currentPrice)
    }
}

// MARK: - Stock Metadata (global lookup from torn/?selections=stocks)
struct StockMetadata: Codable, Identifiable, Equatable {
    static func isValidPrice(_ value: Double) -> Bool {
        NumericSafety.integerAmount(value) != nil
    }

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
        currentPrice = try container.decodeIfPresent(Double.self, forKey: .currentPrice) ?? 0
        guard Self.isValidPrice(currentPrice) else {
            throw DecodingError.dataCorruptedError(forKey: .currentPrice, in: container, debugDescription: "Invalid stock price")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .stockId)
        try container.encode(name, forKey: .name)
        try container.encode(acronym, forKey: .acronym)
        try container.encode(currentPrice, forKey: .currentPrice)
    }
}

// `torn/?selections=stocks` is parsed with JSONSerialization (`AppState.parseStocksMetadata(json:logger:)`)
// to stay resilient to extra or changing fields in the live response.

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
