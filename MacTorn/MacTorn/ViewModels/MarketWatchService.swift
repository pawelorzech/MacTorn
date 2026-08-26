import Foundation
import Observation

struct MarketPriceSnapshot: Equatable {
    let lowestPrice: Int
    let lowestPriceQuantity: Int
    let secondLowestPrice: Int
}

enum MarketPriceResult {
    case success(MarketPriceSnapshot, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case noListings(responseBytes: Int)
    case malformed(responseBytes: Int)
}

struct MarketPriceAlert: Equatable {
    let name: String
    let price: Int
}

@MainActor
protocol MarketWatchServicing: AnyObject {
    var items: [WatchlistItem] { get set }

    func load()
    func save()
    func add(itemID: Int, name: String) -> Bool
    func remove(itemID: Int)
    func restore(_ item: WatchlistItem, at originalIndex: Int) -> Bool
    func apply(_ snapshot: MarketPriceSnapshot, to itemID: Int) -> MarketPriceAlert?
    func setError(_ error: String, for itemID: Int)
    func fetchPrice(from url: URL) async throws -> MarketPriceResult
}

/// Owns watchlist state, persistence and market-response decoding. Request budgets,
/// account identity, bounded fan-out and notification delivery remain AppState policy.
@MainActor
@Observable
final class MarketWatchService: MarketWatchServicing {
    var items: [WatchlistItem] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: NetworkSession

    init(defaults: UserDefaults, session: NetworkSession) {
        self.defaults = defaults
        self.session = session
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
            name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)
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
        item.lowestPrice = snapshot.lowestPrice
        item.lowestPriceQuantity = snapshot.lowestPriceQuantity
        item.secondLowestPrice = snapshot.secondLowestPrice
        item.lastUpdated = Date()
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

    func fetchPrice(from url: URL) async throws -> MarketPriceResult {
        let request = TornAPIClient.request(for: url)
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .httpError(statusCode: http.statusCode, responseBytes: data.count)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }

        // Item-market listings only. The `bazaar` selection was dropped from the request:
        // on API v2 it returns a directory of the bazaars stocking an item, never their
        // prices, so the branch that read `cost`/`quantity` out of it could not match the
        // shape it was given and contributed nothing. See `TornAPI.marketURL`.
        var listings: [(price: Int, amount: Int)] = []
        if let itemMarket = json["itemmarket"] as? [String: Any],
           let array = itemMarket["listings"] as? [[String: Any]] {
            listings += array.compactMap {
                guard let price = $0["price"] as? Int else { return nil }
                return (price, $0["amount"] as? Int ?? 1)
            }
        } else if let array = json["itemmarket"] as? [[String: Any]] {
            listings += array.compactMap {
                guard let price = $0["cost"] as? Int else { return nil }
                return (price, $0["quantity"] as? Int ?? 1)
            }
        }
        let sorted = listings.sorted { $0.price < $1.price }
        guard let best = sorted.first else {
            return .noListings(responseBytes: data.count)
        }
        return .success(
            MarketPriceSnapshot(
                lowestPrice: best.price,
                lowestPriceQuantity: best.amount,
                secondLowestPrice: sorted.count > 1 ? sorted[1].price : 0
            ),
            responseBytes: data.count
        )
    }
}
