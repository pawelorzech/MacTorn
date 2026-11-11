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
    ///
    /// Torn raised the item-market global cache from 30 seconds to one hour on 2026-11-11
    /// and the live response now reports `cache_delay: 3600`. Two hours leaves room for
    /// that without trusting an arbitrary number; the old five-minute cap turned every
    /// hourly snapshot into twelve identical requests.
    static let maxCacheDelay: TimeInterval = 2 * 60 * 60

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
    var items: [WatchlistItem] = [] {
        didSet { onItemsChanged() }
    }
    /// AppState keeps the price-alert timer in step with the thresholds through this.
    @ObservationIgnored var onItemsChanged: () -> Void = {}

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    @ObservationIgnored private var stored = PersistedList<WatchlistItem>(key: "watchlist")

    func load() {
        if let saved = stored.load(from: defaults) { items = saved }
    }

    func save() {
        stored.save(items, to: defaults)
    }

    private func allowPersistenceAfterUserEdit() {
        stored.userEdited()
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
        guard items.reinsert(item, at: originalIndex) else { return false }
        allowPersistenceAfterUserEdit()
        save()
        return true
    }

    /// Records one answer from Torn, read at `now`. Returns the alert it latched, if any.
    func apply(_ snapshot: MarketPriceSnapshot, to itemID: Int, at now: Date) -> MarketPriceAlert? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        var item = items[index]
        let previousRead = item.lastFetchedAt
        item.lastFetchedAt = now
        item.cacheDelay = snapshot.cacheDelay
        if let incoming = snapshot.dataTimestamp,
           let current = item.dataTimestamp,
           incoming <= current {
            item.error = nil
            items[index] = item
            return nil
        }
        // Torn moved to a newer snapshot some time after `previousRead`, which still got
        // the old one. Snapshots are a full `cacheDelay` apart, so the next cannot show up
        // before `previousRead + cacheDelay` (`WatchlistItem.isRefreshDue`). A first
        // price, or one without a timestamp, says nothing about when the change happened.
        if snapshot.dataTimestamp != nil, item.dataTimestamp != nil,
           let previousRead, let delay = snapshot.cacheDelay {
            item.refreshNotBefore = previousRead.addingTimeInterval(delay)
        } else {
            item.refreshNotBefore = nil
        }
        item.lowestPrice = snapshot.lowestPrice
        item.lowestPriceQuantity = snapshot.lowestPriceQuantity
        item.secondLowestPrice = snapshot.secondLowestPrice
        item.dataTimestamp = snapshot.dataTimestamp ?? now
        item.lastUpdated = item.dataTimestamp
        item.error = nil
        items[index] = item
        return latchAlert(for: itemID)
    }

    /// Latches the alert the held price has earned, if it has not been announced yet.
    ///
    /// Called for every new snapshot, and also for prices that were not re-read: a
    /// threshold set since the last read can already be met, and with Torn's hourly cache
    /// the next new snapshot may be an hour away. A row showing an error is left alone —
    /// its price is the last one known, not necessarily Torn's current one.
    func latchAlert(for itemID: Int) -> MarketPriceAlert? {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].error == nil, items[index].shouldFirePriceAlert else { return nil }
        items[index].lastAlertedPrice = items[index].lowestPrice
        return MarketPriceAlert(name: items[index].name, price: items[index].lowestPrice)
    }

    /// How far behind the live market Torn publishes these prices, for the one line that
    /// tells the user so. `nil` while nothing has been priced, or while the delay is too
    /// short to matter to anyone watching a price.
    var publishedPriceLag: TimeInterval? {
        guard let delay = items.compactMap(\.cacheDelay).max(), delay >= 300 else { return nil }
        return delay
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
