import Foundation
@testable import MacTorn

/// Mock network session for testing API calls
final class MockNetworkSession: NetworkSession, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var requestedURLs: [URL] = []

    init(mockData: Data? = nil, mockResponse: URLResponse? = nil, mockError: Error? = nil) {
        self.mockData = mockData
        self.mockResponse = mockResponse
        self.mockError = mockError
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url {
            requestedURLs.append(url)
        }

        if let error = mockError {
            throw error
        }

        let response = mockResponse ?? HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.torn.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (mockData ?? Data(), response)
    }

    // MARK: - Helper Methods

    /// Set up successful response with JSON data
    func setSuccessResponse(json: [String: Any]) throws {
        mockData = try JSONSerialization.data(withJSONObject: json)
        mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.torn.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockError = nil
    }

    /// Set up HTTP error response
    func setHTTPError(statusCode: Int) {
        mockData = Data()
        mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.torn.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
        mockError = nil
    }

    /// Set up Torn API error response
    func setTornAPIError(code: Int, message: String) throws {
        let errorJSON: [String: Any] = [
            "error": [
                "code": code,
                "error": message
            ]
        ]
        mockData = try JSONSerialization.data(withJSONObject: errorJSON)
        mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.torn.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockError = nil
    }

    /// Set up network error
    func setNetworkError(_ error: Error) {
        mockData = nil
        mockResponse = nil
        mockError = error
    }

    /// Reset all mock data
    func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        requestedURLs.removeAll()
    }
}

// MARK: - Test Errors

enum MockNetworkError: Error {
    case connectionFailed
    case timeout
    case noInternet
}
