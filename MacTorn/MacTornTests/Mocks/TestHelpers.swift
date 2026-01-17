import Foundation
import XCTest
@testable import MacTorn

// MARK: - Test Helpers

/// Creates a Bar instance for testing
func makeBar(current: Int = 100, maximum: Int = 150, increment: Double? = 5.0, interval: Int? = 300, ticktime: Int? = 60, fulltime: Int? = 600) -> Bar {
    return Bar(current: current, maximum: maximum, increment: increment, interval: interval, ticktime: ticktime, fulltime: fulltime)
}

/// Creates a Travel instance for testing
func makeTravel(destination: String? = "Torn", timestamp: Int? = nil, departed: Int? = nil, timeLeft: Int? = 0) -> Travel {
    return Travel(destination: destination, timestamp: timestamp, departed: departed, timeLeft: timeLeft)
}

/// Creates a Status instance for testing
func makeStatus(description: String? = "Okay", details: String? = nil, state: String? = "Okay", until: Int? = nil) -> Status {
    return Status(description: description, details: details, state: state, until: until)
}

/// Creates a Chain instance for testing
func makeChain(current: Int? = 0, maximum: Int? = 10, timeout: Int? = 0, cooldown: Int? = 0) -> Chain {
    return Chain(current: current, maximum: maximum, timeout: timeout, cooldown: cooldown)
}

/// Creates a WatchlistItem instance for testing
func makeWatchlistItem(
    id: Int = 1,
    name: String = "Test Item",
    lowestPrice: Int = 1000,
    lowestPriceQuantity: Int = 5,
    secondLowestPrice: Int = 1100,
    lastUpdated: Date? = Date(),
    error: String? = nil
) -> WatchlistItem {
    return WatchlistItem(
        id: id,
        name: name,
        lowestPrice: lowestPrice,
        lowestPriceQuantity: lowestPriceQuantity,
        secondLowestPrice: secondLowestPrice,
        lastUpdated: lastUpdated,
        error: error
    )
}

// MARK: - JSON Decoding Helpers

extension XCTestCase {
    /// Decode JSON string to a Decodable type
    func decode<T: Decodable>(_ type: T.Type, from jsonString: String) throws -> T {
        let data = jsonString.data(using: .utf8)!
        return try JSONDecoder().decode(type, from: data)
    }

    /// Decode JSON dictionary to a Decodable type
    func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Run async test with timeout
    func runAsyncTest(timeout: TimeInterval = 5.0, testBlock: @escaping () async throws -> Void) {
        let expectation = XCTestExpectation(description: "Async test")

        Task {
            do {
                try await testBlock()
                expectation.fulfill()
            } catch {
                XCTFail("Async test failed with error: \(error)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout)
    }
}

// MARK: - UserDefaults Test Helpers

extension UserDefaults {
    /// Create a mock UserDefaults for testing
    static func createMockDefaults() -> UserDefaults {
        let suiteName = "com.mactorn.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return defaults
    }

    /// Clear all data in UserDefaults
    func clearAll() {
        dictionaryRepresentation().keys.forEach { key in
            removeObject(forKey: key)
        }
    }
}
