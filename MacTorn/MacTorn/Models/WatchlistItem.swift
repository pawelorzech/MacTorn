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
    /// Earliest moment Torn can be serving a newer snapshot than the one held, learned
    /// from watching it change. See `isRefreshDue(at:)`.
    var refreshNotBefore: Date?
    var error: String?
    var priceThreshold: Int?
    var lastAlertedPrice: Int?

    init(id: Int, name: String, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, lastUpdated: Date?, error: String?, priceThreshold: Int? = nil, lastAlertedPrice: Int? = nil, lastFetchedAt: Date? = nil, dataTimestamp: Date? = nil, cacheDelay: TimeInterval? = nil, refreshNotBefore: Date? = nil) {
        self.id = id
        self.name = name
        self.lowestPrice = lowestPrice
        self.lowestPriceQuantity = lowestPriceQuantity
        self.secondLowestPrice = secondLowestPrice
        self.lastUpdated = lastUpdated
        self.lastFetchedAt = lastFetchedAt
        self.dataTimestamp = dataTimestamp
        self.cacheDelay = cacheDelay
        self.refreshNotBefore = refreshNotBefore
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
        refreshNotBefore = try container.decodeIfPresent(Date.self, forKey: .refreshNotBefore)
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
                      cacheDelay: cacheDelay,
                      refreshNotBefore: refreshNotBefore)
    }

    var priceDifference: Int {
        guard secondLowestPrice > 0 && lowestPrice > 0 else { return 0 }
        return secondLowestPrice - lowestPrice
    }

    var isLoading: Bool {
        lowestPrice == 0 && error == nil
    }

    /// Shortest gap between two reads of the same item. Just under the price-alert tick
    /// (`AppState.priceAlertPollInterval`) so a tick is never skipped because the previous
    /// answer arrived a second late, yet reopening the tab does not re-ask for every item.
    static let minimumRecheckInterval: TimeInterval = 240

    /// Whether asking Torn for this item now can return anything MacTorn does not hold.
    ///
    /// Item-market data is globally cached: every key gets the same snapshot and no
    /// request can bypass it. Three bounds, the latest of which wins:
    ///
    /// - `dataTimestamp + cacheDelay`: Torn's documented minimum before the snapshot can
    ///   change.
    /// - `refreshNotBefore`: snapshots are a full `cacheDelay` apart, so once one has been
    ///   seen to change, the next cannot appear sooner than `cacheDelay` after the last
    ///   read that still returned the old one. Measured 2026-11-11: Torn serves a
    ///   snapshot from `cache_timestamp + cache_delay` until `+ 2 × cache_delay`, so the
    ///   documented minimum alone has always passed and would re-ask on every tick.
    /// - `lastFetchedAt + minimumRecheckInterval`: while waiting for a change, ask at the
    ///   alert cadence and no faster.
    ///
    /// A read dated in the future, or a wait longer than one cache window, cannot come
    /// from Torn; it means the Mac's clock moved, and the item is due rather than frozen.
    func isRefreshDue(at now: Date) -> Bool {
        guard let dataTimestamp, let cacheDelay else { return true }
        if let lastFetchedAt, lastFetchedAt > now { return true }
        var earliest = dataTimestamp.addingTimeInterval(cacheDelay)
        if let refreshNotBefore { earliest = max(earliest, refreshNotBefore) }
        if let lastFetchedAt, error == nil {
            earliest = max(earliest, lastFetchedAt.addingTimeInterval(Self.minimumRecheckInterval))
        }
        guard earliest.timeIntervalSince(now) <= max(cacheDelay, Self.minimumRecheckInterval) else { return true }
        return now >= earliest
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
