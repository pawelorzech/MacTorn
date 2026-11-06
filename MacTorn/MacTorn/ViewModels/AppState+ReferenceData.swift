import Foundation
import os.log

// MARK: - Item catalog (v2 /torn/items)
//
// Torn publishes the name of every item in the game. MacTorn never asked, so adding a
// watchlist entry meant knowing the numeric id *and* typing the name — and an item added
// by id was stored as "Item #206" and displayed that way forever. The panel papered over
// it with a hard-coded list of nine "popular" items, which is a guess at what a player
// trades and goes stale the moment Torn adds anything.
//
// The catalog is slow-changing reference data, so it follows exactly the shape
// `stocksMetadata` already established: fetch once, cache in UserDefaults, back off on
// failure, and never block anything on having it. Everything below degrades to the old
// "Item #id" behaviour when the catalog is absent.

/// One catalogue entry. Deliberately just the two fields the app uses: the payload for
/// every item in Torn runs to hundreds of kilobytes, and none of the rest of it earns a
/// place in a cache that lives in the user's preferences.
struct TornItemSummary: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let name: String
}

private struct CachedCatalogItem: Codable, Sendable {
    let name: String
    let marketPrice: Int
    let shops: [CachedCatalogShop]
}

private struct CachedCatalogShop: Codable, Sendable {
    let country: String
    let shop: String
    let buyPrice: Int?
    let sellPrice: Int?
}

enum ShopCatalogRefreshResult {
    case success([ShopItem])
    case pending([ShopItem])
    case denied(String, [ShopItem])
    case failed([ShopItem])
}

extension AppState {
    private static var stocksMetadataCacheKey: String { "stocksMetadataCache" }

    // MARK: - Stocks Metadata

    func loadStocksMetadataFromCache() {
        guard let data = defaults.data(forKey: Self.stocksMetadataCacheKey) else { return }
        guard let cached = try? JSONDecoder().decode([Int: StockMetadata].self, from: data) else {
            defaults.removeObject(forKey: Self.stocksMetadataCacheKey)
            stocksMetadata = [:]
            return
        }
        stocksMetadata = cached
    }

    func triggerStocksMetadataFetchIfNeeded() {
        guard stocksMetadata.isEmpty, !apiKey.isEmpty, stocksBackoff.allows(at: time.now),
              !requester.isInFlight("torn.stocks") else { return }
        accountSession.startTask(.stockMetadata) { await self.fetchStocksMetadata() }
    }

    func fetchStocksMetadata() async {
        await fetchReferenceData("torn.stocks", cacheKey: Self.stocksMetadataCacheKey,
                                 parse: { Self.parseStocksMetadata(json: $0, logger: $1) },
                                 onFailure: { stocksBackoff.fail(at: time.now) }) { parsed in
            stocksMetadata = parsed
            stocksBackoff.succeed()
        }
    }

    /// One request per reference source at a time. The parsed map is cached in defaults
    /// before it is published, so the next launch starts from it.
    func fetchReferenceData<Value: Codable & Sendable>(
        _ endpointID: String,
        cacheKey: String,
        parse: @escaping @Sendable ([String: Any], Logger) -> [Int: Value],
        onFailure: () -> Void,
        publish: ([Int: Value]) -> Void
    ) async {
        guard !requester.isInFlight(endpointID) else { return }
        let result = await requester.fetch(endpointID) { _, json -> ([Int: Value], Data)? in
            let parsed = parse(json, Self.appReferenceLogger)
            guard !parsed.isEmpty, let encoded = try? JSONEncoder().encode(parsed) else { return nil }
            return (parsed, encoded)
        }
        switch result {
        case .loaded(let (parsed, encoded)):
            defaults.set(encoded, forKey: cacheKey)
            publish(parsed)
        case .failed:
            onFailure()
        case .nothingToServe, .skipped, .superseded:
            break
        }
    }

    nonisolated private static let appReferenceLogger =
        Logger(subsystem: TornConstants.logSubsystem, category: "ReferenceData")

    nonisolated static func parseStocksMetadata(from data: Data, logger: Logger) -> [Int: StockMetadata] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Stocks metadata: failed to parse JSON")
            return [:]
        }
        return parseStocksMetadata(json: json, logger: logger)
    }

    nonisolated private static func parseStocksMetadata(json: [String: Any], logger: Logger) -> [Int: StockMetadata] {
        if tornAPIErrorMessage(in: json) != nil {
            logger.error("Stocks metadata API returned an error envelope")
            return [:]
        }
        guard let stocksDict = json["stocks"] as? [String: [String: Any]] else {
            logger.warning("Stocks metadata: no 'stocks' key in response")
            return [:]
        }
        var result: [Int: StockMetadata] = [:]
        for (key, stockData) in stocksDict {
            guard let id = Int(key) else { continue }
            let name = stockData["name"] as? String ?? ""
            let acronym = stockData["acronym"] as? String ?? ""
            let price: Double
            if let n = stockData["current_price"] as? NSNumber {
                price = n.doubleValue
            } else if let s = stockData["current_price"] as? String, let d = Double(s) {
                price = d
            } else {
                price = 0
            }
            guard StockMetadata.isValidPrice(price) else { return [:] }
            result[id] = StockMetadata(id: id, name: name, acronym: acronym, currentPrice: price)
        }
        return result
    }
}

extension AppState {
    private static var itemCatalogCacheKey: String { "itemCatalogCache" }
    private static var itemCatalogFetchedAtKey: String { "itemCatalogFetchedAt" }
    /// A week. Torn adds items occasionally, never hourly.
    private static var itemCatalogMaxAge: TimeInterval { 604_800 }

    // MARK: Cache

    func loadItemCatalogFromCache() {
        guard let data = defaults.data(forKey: Self.itemCatalogCacheKey) else { return }
        if let cached = try? JSONDecoder().decode([Int: CachedCatalogItem].self, from: data) {
            itemCatalog = cached.mapValues(\.name)
            itemCatalogCacheExpanded = true
        } else if let legacy = try? JSONDecoder().decode([Int: String].self, from: data) {
            // Pre-shop cache migration: keep names immediately and refresh once to add
            // the public shop fields from the same `/torn/items` response.
            itemCatalog = legacy
            itemCatalogCacheExpanded = false
        }
        let fetchedAt = defaults.double(forKey: Self.itemCatalogFetchedAtKey)
        itemCatalogFetchedAt = fetchedAt > 0 ? Date(timeIntervalSince1970: fetchedAt) : nil
    }

    /// True when the catalogue is missing or old enough to be worth re-reading.
    ///
    /// Reads only in-memory state. The previous version decoded the whole persisted blob
    /// from `UserDefaults` here, and this runs ~2× per poll (audit W-1).
    private var itemCatalogIsStale: Bool {
        guard !itemCatalog.isEmpty, itemCatalogCacheExpanded,
              let fetchedAt = itemCatalogFetchedAt else { return true }
        return time.now.timeIntervalSince(fetchedAt) > Self.itemCatalogMaxAge
    }

    /// Refreshes the catalogue if it is stale and nothing is holding it back. Safe to call
    /// on every poll — it does nothing almost every time.
    func triggerItemCatalogFetchIfNeeded() {
        guard itemCatalogIsStale, !apiKey.isEmpty else { return }
        guard itemCatalogBackoff.allows(at: time.now), !requester.isInFlight("torn.items") else { return }
        accountSession.startTask(.itemCatalog) { _ = await self.fetchItemCatalog() }
    }

    // MARK: Fetch

    @discardableResult
    func fetchItemCatalog() async -> Bool {
        let previousFetchedAt = itemCatalogFetchedAt
        await fetchReferenceData("torn.items", cacheKey: Self.itemCatalogCacheKey,
                                 parse: { Self.parseExpandedItemCatalog(json: $0, logger: $1) },
                                 onFailure: { itemCatalogBackoff.fail(at: time.now) }) { parsed in
            itemCatalog = parsed.mapValues(\.name)
            let now = time.now
            itemCatalogFetchedAt = now
            itemCatalogCacheExpanded = true
            defaults.set(now.timeIntervalSince1970, forKey: Self.itemCatalogFetchedAtKey)
            itemCatalogBackoff.succeed()
            backfillWatchlistNames()
        }
        return itemCatalogFetchedAt != previousFetchedAt
    }

    /// Supplies the optional shop module from the same public catalogue/cache used by
    /// item-name search. A fresh catalogue never causes a second full download.
    func shopCatalogRefreshingIfNeeded() async -> ShopCatalogRefreshResult {
        loadItemCatalogFromCache()
        let cached = cachedShopItems()
        guard itemCatalogIsStale else { return .success(cached) }
        guard !requester.isInFlight("torn.items") else { return .pending(cached) }
        if let denial = requester.denial("torn.items") {
            return .denied(denial.userExplanation, cached)
        }
        guard itemCatalogBackoff.allows(at: time.now) else { return .pending(cached) }
        return await fetchItemCatalog() ? .success(cachedShopItems()) : .failed(cachedShopItems())
    }

    func cachedShopItems() -> [ShopItem] {
        guard let cached = cachedCatalogItems() else { return [] }
        return cached.compactMap { id, item in
            guard !item.shops.isEmpty else { return nil }
            return ShopItem(
                id: id,
                name: item.name,
                value: ShopItem.Value(
                    marketPrice: item.marketPrice,
                    shops: item.shops.map {
                        ShopItem.Shop(country: $0.country, shop: $0.shop,
                                      buyPrice: $0.buyPrice, sellPrice: $0.sellPrice)
                    }
                )
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func cachedCatalogItems() -> [Int: CachedCatalogItem]? {
        guard let data = defaults.data(forKey: Self.itemCatalogCacheKey) else { return nil }
        return try? JSONDecoder().decode([Int: CachedCatalogItem].self, from: data)
    }

    /// Most entries MacTorn will keep from one catalog response.
    ///
    /// Torn ships on the order of 1,500 items, so this is generous headroom rather than a
    /// working limit. It exists because the parsed map is written straight into
    /// UserDefaults, which macOS materialises in full at every launch: without a ceiling a
    /// hostile or MITM'd response could persist an arbitrarily large blob that reloads on
    /// every start and only clears on the next *successful* fetch.
    nonisolated static let itemCatalogMaxEntries = 5_000

    /// Decodes `TornItemsResponse` down to id → name.
    ///
    /// `nonisolated` and `static` so it can run off the main actor on a payload with well
    /// over a thousand entries, matching `parseStocksMetadata`.
    ///
    /// Names are trimmed and capped at the same length a user-typed watchlist name is.
    /// These strings end up in the user's persisted watchlist via `backfillWatchlistNames`,
    /// so they get the discipline that path already applied to typed input.
    nonisolated static func parseItemCatalog(from data: Data, logger: Logger) -> [Int: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Item catalog: failed to parse JSON")
            return [:]
        }
        return parseExpandedItemCatalog(json: json, logger: logger).mapValues(\.name)
    }

    nonisolated private static func parseExpandedItemCatalog(json: [String: Any], logger: Logger) -> [Int: CachedCatalogItem] {
        if tornAPIErrorMessage(in: json) != nil {
            logger.error("Item catalog API returned an error envelope")
            return [:]
        }
        guard let items = json["items"] as? [[String: Any]] else {
            logger.warning("Item catalog: no 'items' array in response")
            return [:]
        }
        var result: [Int: CachedCatalogItem] = [:]
        result.reserveCapacity(min(items.count, itemCatalogMaxEntries))
        for item in items {
            guard result.count < itemCatalogMaxEntries else {
                logger.warning("Item catalog truncated at \(itemCatalogMaxEntries) entries")
                break
            }
            guard let id = item["id"] as? Int,
                  let raw = item["name"] as? String else { continue }
            let name = String(
                raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(WatchlistItem.maximumNameLength)
            )
            guard !name.isEmpty else { continue }
            var shops: [CachedCatalogShop] = []
            var marketPrice = 0
            if let value = item["value"] as? [String: Any] {
                marketPrice = value["market_price"] as? Int ?? 0
                if let rows = value["shops"] as? [[String: Any]] {
                    shops = rows.compactMap { row in
                        guard let country = row["country"] as? String,
                              let shop = row["shop"] as? String else { return nil }
                        return CachedCatalogShop(country: country, shop: shop,
                                                 buyPrice: row["buy_price"] as? Int,
                                                 sellPrice: row["sell_price"] as? Int)
                    }
                }
            }
            result[id] = CachedCatalogItem(name: name, marketPrice: marketPrice, shops: shops)
        }
        return result
    }

    // MARK: Lookup

    /// The catalogue name for an item, falling back to the numbered placeholder the app
    /// used before the catalogue existed.
    func itemName(for itemID: Int) -> String {
        itemCatalog[itemID] ?? Self.placeholderItemName(for: itemID)
    }

    /// The fallback label for an item MacTorn has no catalogue entry for. One definition,
    /// used by both the lookup and the backfill's "is this still a placeholder?" guard
    /// (audit D-8).
    static func placeholderItemName(for itemID: Int) -> String {
        "Item #\(itemID)"
    }

    /// Catalogue entries whose name contains `query`, best matches first: names that start
    /// with the query come before names that merely contain it, then alphabetical.
    ///
    /// `limit` keeps the result small enough to render in a menu-bar popover — a bare
    /// substring search over the whole catalogue otherwise returns hundreds of rows for a
    /// two-letter query.
    func searchItems(_ query: String, limit: Int = 12) -> [TornItemSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var prefixMatches: [TornItemSummary] = []
        var containsMatches: [TornItemSummary] = []
        for entry in itemSearchIndex {
            if entry.lowered.hasPrefix(needle) {
                prefixMatches.append(TornItemSummary(id: entry.id, name: entry.name))
            } else if entry.lowered.contains(needle) {
                containsMatches.append(TornItemSummary(id: entry.id, name: entry.name))
            }
        }
        let byName: (TornItemSummary, TornItemSummary) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Array((prefixMatches.sorted(by: byName) + containsMatches.sorted(by: byName)).prefix(limit))
    }

    /// Rebuilds the lowercased search mirror. Called only when `itemCatalog` changes.
    func rebuildItemSearchIndex() {
        itemSearchIndex = itemCatalog.map { (id: $0.key, name: $0.value, lowered: $0.value.lowercased()) }
    }

    /// Replaces the `Item #id` placeholders on the watchlist once real names are known.
    ///
    /// Only placeholders are touched. A name the user typed themselves is theirs, and
    /// having the catalogue arrive is no reason to overwrite it.
    func backfillWatchlistNames() {
        guard !itemCatalog.isEmpty else { return }
        var changed = false
        for index in watchlistItems.indices {
            let item = watchlistItems[index]
            guard item.name == Self.placeholderItemName(for: item.id), let real = itemCatalog[item.id] else { continue }
            watchlistItems[index] = item.renamed(to: real)
            changed = true
        }
        if changed {
            watchlist.save()
            logger.info("Backfilled watchlist item names from the catalog")
        }
    }
}
