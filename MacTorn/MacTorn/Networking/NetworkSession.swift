import Foundation

/// Protocol for network session abstraction to enable dependency injection and testing
protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Extension to make URLSession conform to NetworkSession
extension URLSession: NetworkSession {}
