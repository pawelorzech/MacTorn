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

    func load() {
        guard let data = defaults.data(forKey: "watchlist"),
              let decoded = try? JSONDecoder().decode([WatchlistItem].self, from: data) else {
            return
        }
        items = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: "watchlist")
    }

    func add(itemID: Int, name: String) -> Bool {
        guard itemID > 0, itemID < 100_000 else { return false }
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
        save()
        return true
    }

    func remove(itemID: Int) {
        items.removeAll { $0.id == itemID }
        save()
    }

    func restore(_ item: WatchlistItem, at originalIndex: Int) -> Bool {
        guard !items.contains(where: { $0.id == item.id }) else { return false }
        let insertionIndex = min(max(originalIndex, 0), items.count)
        items.insert(item, at: insertionIndex)
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
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
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
        if let array = json["bazaar"] as? [[String: Any]] {
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
