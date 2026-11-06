import Foundation

struct WatchlistItem: Codable, Identifiable {
    let id: Int
    let name: String
    var lowestPrice: Int
    var lowestPriceQuantity: Int
    var secondLowestPrice: Int
    var lastUpdated: Date?
    var lastFetchedAt: Date?
    var dataTimestamp: Date?
    var cacheDelay: TimeInterval?
    var error: String?
    var priceThreshold: Int?
    var lastAlertedPrice: Int?

    init(id: Int, name: String, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, lastUpdated: Date?, error: String?, priceThreshold: Int? = nil, lastAlertedPrice: Int? = nil, lastFetchedAt: Date? = nil, dataTimestamp: Date? = nil, cacheDelay: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.lowestPrice = lowestPrice
        self.lowestPriceQuantity = lowestPriceQuantity
        self.secondLowestPrice = secondLowestPrice
        self.lastUpdated = lastUpdated
        self.lastFetchedAt = lastFetchedAt
        self.dataTimestamp = dataTimestamp
        self.cacheDelay = cacheDelay
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
        lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        dataTimestamp = try container.decodeIfPresent(Date.self, forKey: .dataTimestamp) ?? lastUpdated
        cacheDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .cacheDelay)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        priceThreshold = try container.decodeIfPresent(Int.self, forKey: .priceThreshold)
        lastAlertedPrice = try container.decodeIfPresent(Int.self, forKey: .lastAlertedPrice)
    }

    /// Longest display name a watchlist entry may carry, whether typed or arriving from Torn's item
    /// catalog.
    static let maximumNameLength = 64

    /// A copy under a different display name. `id` is the identity: renaming an entry
    /// keeps its prices, its threshold and its alert history intact.
    ///
    /// The new name is trimmed and capped as a typed one is, so a hostile or MITM'd `/v2/torn/items`
    /// response cannot write unbounded server text into the persisted watchlist.
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
                      lastAlertedPrice: lastAlertedPrice,
                      lastFetchedAt: lastFetchedAt,
                      dataTimestamp: dataTimestamp,
                      cacheDelay: cacheDelay)
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
