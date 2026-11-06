import Foundation
import Observation

struct MarketPriceSnapshot: Equatable {
    let lowestPrice: Int
    let lowestPriceQuantity: Int
    let secondLowestPrice: Int
    let dataTimestamp: Date?
    let cacheDelay: TimeInterval?

    init(lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int,
         dataTimestamp: Date? = nil, cacheDelay: TimeInterval? = nil) {
        self.lowestPrice = lowestPrice
        self.lowestPriceQuantity = lowestPriceQuantity
        self.secondLowestPrice = secondLowestPrice
        self.dataTimestamp = dataTimestamp
        self.cacheDelay = cacheDelay
    }

    /// Longest `cache_delay` honoured. The value comes off the wire and is persisted, so an
    /// absurd one would otherwise freeze the item's refresh indefinitely.
    static let maxCacheDelay: TimeInterval = 300

    /// Re-expresses Torn's `cache_timestamp` (server clock) on the Mac's clock and clamps
    /// the delay, so the refresh filter and the "Price data from … ago" label — both of
    /// which compare against `Date()` — stay correct when the Mac clock is skewed.
    func localized(using clock: ServerClock) -> MarketPriceSnapshot {
        MarketPriceSnapshot(
            lowestPrice: lowestPrice,
            lowestPriceQuantity: lowestPriceQuantity,
            secondLowestPrice: secondLowestPrice,
            dataTimestamp: dataTimestamp.map {
                clock.localDate(forServerTimestamp: Int($0.timeIntervalSince1970))
            },
            cacheDelay: cacheDelay.map { min(max($0, 0), Self.maxCacheDelay) }
        )
    }
}

struct MarketPriceAlert: Equatable {
    let name: String
    let price: Int
}

/// Owns watchlist state, persistence and market-response decoding. Request budgets,
/// account identity, bounded fan-out and notification delivery remain AppState policy.
@MainActor
@Observable
final class MarketWatchService {
    var items: [WatchlistItem] = []

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Set when a stored blob exists but could not be decoded. While true, `save()`
    /// refuses to write — otherwise the first background price refresh would overwrite
    /// a recoverable blob with the empty in-memory list and destroy the user's watchlist
    /// permanently (audit finding D-01). Any deliberate user edit clears the flag.
    @ObservationIgnored private var loadFailed = false

    private static let storageKey = "watchlist"

    func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            // No key at all — a legitimate first run, not a failure.
            loadFailed = false
            return
        }
        guard let decoded = try? JSONDecoder().decode([WatchlistItem].self, from: data) else {
            // The blob is there but unreadable (corruption, or a model change in a
            // newer build). Keep it: a later app version may still be able to read it.
            loadFailed = true
            defaults.set(data, forKey: "\(Self.storageKey).unreadable")
            return
        }
        loadFailed = false
        items = decoded
    }

    func save() {
        guard !loadFailed else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// A deliberate user edit takes ownership of the list, so persistence resumes even
    /// if the previous blob was unreadable.
    private func allowPersistenceAfterUserEdit() {
        loadFailed = false
    }

    /// Upper bound for Torn item ids. Exposed so the UI can tell the user *why* an id
    /// was rejected instead of guessing; see `AppState.WatchlistAddOutcome`.
    static let maximumItemID = 100_000

    func add(itemID: Int, name: String) -> Bool {
        guard itemID > 0, itemID < Self.maximumItemID else { return false }
        let trimmed = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WatchlistItem.maximumNameLength)
        )
        guard !trimmed.isEmpty,
              !items.contains(where: { $0.id == itemID }) else {
            return false
        }
        items.append(
            WatchlistItem(
                id: itemID,
                name: trimmed,
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: nil
            )
        )
        allowPersistenceAfterUserEdit()
        save()
        return true
    }

    func remove(itemID: Int) {
        items.removeAll { $0.id == itemID }
        allowPersistenceAfterUserEdit()
        save()
    }

    func restore(_ item: WatchlistItem, at originalIndex: Int) -> Bool {
        guard !items.contains(where: { $0.id == item.id }) else { return false }
        let insertionIndex = min(max(originalIndex, 0), items.count)
        items.insert(item, at: insertionIndex)
        allowPersistenceAfterUserEdit()
        save()
        return true
    }

    func apply(_ snapshot: MarketPriceSnapshot, to itemID: Int) -> MarketPriceAlert? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        var item = items[index]
        let fetchedAt = Date()
        item.lastFetchedAt = fetchedAt
        item.cacheDelay = snapshot.cacheDelay
        if let incoming = snapshot.dataTimestamp,
           let current = item.dataTimestamp,
           incoming <= current {
            item.error = nil
            items[index] = item
            return nil
        }
        item.lowestPrice = snapshot.lowestPrice
        item.lowestPriceQuantity = snapshot.lowestPriceQuantity
        item.secondLowestPrice = snapshot.secondLowestPrice
        item.dataTimestamp = snapshot.dataTimestamp ?? fetchedAt
        item.lastUpdated = item.dataTimestamp
        item.error = nil
        items[index] = item

        guard items[index].shouldFirePriceAlert else { return nil }
        items[index].lastAlertedPrice = snapshot.lowestPrice
        return MarketPriceAlert(name: item.name, price: snapshot.lowestPrice)
    }

    func setError(_ error: String, for itemID: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].error = error
    }

    /// The lowest item-market listings, or `.some(nil)` when nobody is selling. `nil` is a
    /// response MacTorn cannot read: one malformed listing rejects the whole answer.
    nonisolated static func decodePrice(_ data: Data, _ json: [String: Any]) -> MarketPriceSnapshot?? {
        let listings: [(price: Int, amount: Int)]
        let market = json["itemmarket"] as? [String: Any]
        if let rows = market?["listings"] as? [[String: Any]] {
            listings = rows.compactMap { row in
                (row["price"] as? Int).map { ($0, row["amount"] as? Int ?? 1) }
            }
            guard listings.count == rows.count else { return nil }
        } else if let rows = json["itemmarket"] as? [[String: Any]] {
            listings = rows.compactMap { row in
                (row["cost"] as? Int).map { ($0, row["quantity"] as? Int ?? 1) }
            }
            guard listings.count == rows.count else { return nil }
        } else {
            return nil
        }
        let sorted = listings.sorted { $0.price < $1.price }
        guard let best = sorted.first else { return .some(nil) }
        return MarketPriceSnapshot(
            lowestPrice: best.price,
            lowestPriceQuantity: best.amount,
            secondLowestPrice: sorted.count > 1 ? sorted[1].price : 0,
            dataTimestamp: (market?["cache_timestamp"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            cacheDelay: (market?["cache_delay"] as? Int).map(TimeInterval.init)
        )
    }
}
