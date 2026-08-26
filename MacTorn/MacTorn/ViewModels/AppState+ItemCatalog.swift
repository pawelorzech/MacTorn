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

extension AppState {
    private static var itemCatalogCacheKey: String { "itemCatalogCache" }
    private static var itemCatalogFetchedAtKey: String { "itemCatalogFetchedAt" }
    /// A week. Torn adds items occasionally, never hourly.
    private static var itemCatalogMaxAge: TimeInterval { 604_800 }
    private static var itemCatalogBackoffLadder: [TimeInterval] { [60, 300, 1_800] }

    // MARK: Cache

    func loadItemCatalogFromCache() {
        guard let data = defaults.data(forKey: Self.itemCatalogCacheKey),
              let cached = try? JSONDecoder().decode([Int: String].self, from: data) else {
            return
        }
        itemCatalog = cached
    }

    /// True when the catalogue is missing or old enough to be worth re-reading.
    private var itemCatalogIsStale: Bool {
        if itemCatalog.isEmpty { return true }
        let fetchedAt = defaults.double(forKey: Self.itemCatalogFetchedAtKey)
        guard fetchedAt > 0 else { return true }
        return Date().timeIntervalSince1970 - fetchedAt > Self.itemCatalogMaxAge
    }

    /// Refreshes the catalogue if it is stale and nothing is holding it back. Safe to call
    /// on every poll — it does nothing almost every time.
    func triggerItemCatalogFetchIfNeeded() {
        guard itemCatalogIsStale, !apiKey.isEmpty else { return }
        if let retryAfter = itemCatalogNextRetryAfter, Date() < retryAfter { return }
        guard itemCatalogTask == nil else { return }
        itemCatalogTask = Task { await self.fetchItemCatalog() }
    }

    // MARK: Fetch

    func fetchItemCatalog() async {
        defer { itemCatalogTask = nil }
        guard let url = endpointURL("torn.items"), reserveRequest("torn.items") else { return }
        let startTime = Date()

        do {
            let (data, _) = try await session.data(for: TornAPIClient.request(for: url))
            let parsed = AppState.parseItemCatalog(from: data, logger: logger)
            guard !parsed.isEmpty else {
                recordItemCatalogFailure()
                recordHealth("torn.items", outcome: .error, since: startTime,
                             bytes: data.count, errorClass: "malformedResponse")
                return
            }
            itemCatalog = parsed
            if let encoded = try? JSONEncoder().encode(parsed) {
                defaults.set(encoded, forKey: Self.itemCatalogCacheKey)
                defaults.set(Date().timeIntervalSince1970, forKey: Self.itemCatalogFetchedAtKey)
            }
            itemCatalogFailureCount = 0
            itemCatalogNextRetryAfter = nil
            backfillWatchlistNames()
            recordHealth("torn.items", outcome: .ok, since: startTime, bytes: data.count)
            logger.info("Item catalog loaded: \(parsed.count) items")
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordItemCatalogFailure()
            recordHealth("torn.items",
                         outcome: mapped?.classification == .offline ? .offline : .error,
                         since: startTime, bytes: 0,
                         errorClass: mapped?.classification.rawValue ?? "transport")
            logger.error("Failed to fetch item catalog: \(String(describing: type(of: error)))")
        }
    }

    func recordItemCatalogFailure() {
        itemCatalogFailureCount += 1
        let index = min(itemCatalogFailureCount - 1, Self.itemCatalogBackoffLadder.count - 1)
        itemCatalogNextRetryAfter = Date().addingTimeInterval(Self.itemCatalogBackoffLadder[index])
    }

    /// Decodes `TornItemsResponse` down to id → name.
    ///
    /// `nonisolated` and `static` so it can run off the main actor on a payload with well
    /// over a thousand entries, matching `parseStocksMetadata`.
    nonisolated static func parseItemCatalog(from data: Data, logger: Logger) -> [Int: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Item catalog: failed to parse JSON")
            return [:]
        }
        if tornAPIErrorMessage(in: json) != nil {
            logger.error("Item catalog API returned an error envelope")
            return [:]
        }
        guard let items = json["items"] as? [[String: Any]] else {
            logger.warning("Item catalog: no 'items' array in response")
            return [:]
        }
        var result: [Int: String] = [:]
        result.reserveCapacity(items.count)
        for item in items {
            guard let id = item["id"] as? Int,
                  let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            result[id] = name
        }
        return result
    }

    // MARK: Lookup

    /// The catalogue name for an item, falling back to the numbered placeholder the app
    /// used before the catalogue existed.
    func itemName(for itemID: Int) -> String {
        itemCatalog[itemID] ?? "Item #\(itemID)"
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
        for (id, name) in itemCatalog {
            let lowered = name.lowercased()
            if lowered.hasPrefix(needle) {
                prefixMatches.append(TornItemSummary(id: id, name: name))
            } else if lowered.contains(needle) {
                containsMatches.append(TornItemSummary(id: id, name: name))
            }
        }
        let byName: (TornItemSummary, TornItemSummary) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Array((prefixMatches.sorted(by: byName) + containsMatches.sorted(by: byName)).prefix(limit))
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
            guard item.name == "Item #\(item.id)", let real = itemCatalog[item.id] else { continue }
            watchlistItems[index] = item.renamed(to: real)
            changed = true
        }
        if changed {
            marketWatchService.save()
            logger.info("Backfilled watchlist item names from the catalog")
        }
    }
}
