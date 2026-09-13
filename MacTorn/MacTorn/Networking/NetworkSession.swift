import Foundation

/// Protocol for network session abstraction to enable dependency injection and testing
protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Extension to make URLSession conform to NetworkSession
extension URLSession: NetworkSession {}

enum TornServiceResult<Value> {
    case success(Value, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case malformed(responseBytes: Int)
}

extension TornAPIClient {
    /// Transport and decoding run outside the main actor; only callers publish state.
    static func loadJSON<Value>(
        from url: URL,
        session: NetworkSession,
        decode: @Sendable (Data, [String: Any]) -> Value?
    ) async throws -> TornServiceResult<Value> {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request(for: url))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return .httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                              responseBytes: data.count)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let error = tornAPIError(in: json) {
            return .apiError(error, responseBytes: data.count)
        }
        guard let value = decode(data, json) else { return .malformed(responseBytes: data.count) }
        try Task.checkCancellation()
        return .success(value, responseBytes: data.count)
    }
}
