import Foundation
import Observation

enum FactionServiceResult<Value> {
    case success(Value, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case malformed(responseBytes: Int)
}

@MainActor
protocol FactionServicing: AnyObject {
    var basic: FactionData? { get }
    var wars: [RankedWar] { get }
    var news: [FactionNews] { get }

    func loadBasic(from url: URL) async throws -> FactionServiceResult<FactionData>
    func loadWars(from url: URL) async throws -> FactionServiceResult<[RankedWar]>
    func loadNews(from url: URL) async throws -> FactionServiceResult<[FactionNews]>

    /// Called by the facade only after its account-generation check succeeds.
    func publishBasic(_ value: FactionData)
    func publishWars(_ value: [RankedWar])
    func publishNews(_ value: [FactionNews])
    func reset()
}

/// Owns faction state plus transport/decoding for the three faction sources.
///
/// Request budgets, endpoint health, throttling, row-source pauses and account
/// generation checks deliberately remain facade policy. Loads therefore return typed
/// results without publishing them; `AppState` publishes only after validating that
/// the response still belongs to the current account generation.
@MainActor
@Observable
final class FactionService: FactionServicing {
    private(set) var basic: FactionData?
    private(set) var wars: [RankedWar] = []
    private(set) var news: [FactionNews] = []

    @ObservationIgnored private let session: NetworkSession

    init(session: NetworkSession) {
        self.session = session
    }

    func loadBasic(from url: URL) async throws -> FactionServiceResult<FactionData> {
        let response = try await load(url)
        guard case .success(let data) = response else {
            return mapTransportFailure(response)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }

        // FactionData's decoder is intentionally forgiving for UI compatibility.
        // The service boundary must be stricter so `{}` never publishes a plausible
        // empty faction or silently erases a valid chain.
        guard json["name"] is String,
              json["ID"] is Int,
              json["respect"] is Int,
              let chain = json["chain"] as? [String: Any],
              chain["current"] is Int,
              chain["max"] is Int,
              chain["timeout"] is Int,
              chain["cooldown"] is Int,
              let decoded = try? JSONDecoder().decode(FactionData.self, from: data) else {
            return .malformed(responseBytes: data.count)
        }
        return .success(decoded, responseBytes: data.count)
    }

    func loadWars(from url: URL) async throws -> FactionServiceResult<[RankedWar]> {
        try await loadArray(from: url, key: "rankedwars")
    }

    func loadNews(from url: URL) async throws -> FactionServiceResult<[FactionNews]> {
        try await loadArray(from: url, key: "news")
    }

    func publishBasic(_ value: FactionData) {
        basic = value
    }

    func publishWars(_ value: [RankedWar]) {
        wars = value
    }

    func publishNews(_ value: [FactionNews]) {
        news = value
    }

    func reset() {
        basic = nil
        wars = []
        news = []
    }

    private enum TransportResponse {
        case success(Data)
        case httpError(statusCode: Int, data: Data)
    }

    private func load(_ url: URL) async throws -> TransportResponse {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return .httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                data: data
            )
        }
        return .success(data)
    }

    private func loadArray<Value: Decodable>(
        from url: URL,
        key: String
    ) async throws -> FactionServiceResult<[Value]> {
        let response = try await load(url)
        guard case .success(let data) = response else {
            return mapTransportFailure(response)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }
        guard let array = json[key] as? [Any],
              let encoded = try? JSONSerialization.data(withJSONObject: array),
              let decoded = try? JSONDecoder().decode([Value].self, from: encoded) else {
            return .malformed(responseBytes: data.count)
        }
        return .success(decoded, responseBytes: data.count)
    }

    private func mapTransportFailure<Value>(
        _ response: TransportResponse
    ) -> FactionServiceResult<Value> {
        switch response {
        case .success(let data):
            return .malformed(responseBytes: data.count)
        case .httpError(let statusCode, let data):
            return .httpError(statusCode: statusCode, responseBytes: data.count)
        }
    }
}
