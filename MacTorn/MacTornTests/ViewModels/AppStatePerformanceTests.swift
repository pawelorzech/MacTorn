import XCTest
import os.log
@testable import MacTorn

/// Performance baselines + regression guards for the perf-sensitive paths flagged in
/// `Plans/performance-optimization-review-unified-clarke.md`. These tests do not assert
/// absolute timings (they vary across machines); they record a baseline via XCTest's
/// `measure { }` so future regressions surface as CI failures vs. the recorded baseline.
final class AppStatePerformanceTests: XCTestCase {

    // MARK: - JSON decode microbenchmarks

    func testDecodeFullResponsePerformance() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        measure {
            for _ in 0..<50 {
                _ = try? JSONDecoder().decode(TornResponse.self, from: data)
            }
        }
    }

    func testParseStocksMetadataPerformance() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.stocksData)
        let logger = Logger(subsystem: "com.mactorn.app.tests.perf", category: "perf")
        measure {
            for _ in 0..<50 {
                _ = AppState.parseStocksMetadata(from: data, logger: logger)
            }
        }
    }

    // MARK: - Backoff ladder regression

    @MainActor
    func testStocksMetadataBackoffLadder() async {
        let appState = AppState(session: MockNetworkSession(), connectivity: AlwaysOnlineConnectivity(), defaults: .createMockDefaults())

        let t0 = Date()
        appState.recordStocksMetadataFailure()
        let r1 = appState.stocksNextRetryAfter
        XCTAssertNotNil(r1)
        XCTAssertGreaterThanOrEqual(r1!.timeIntervalSince(t0), 60 - 1)
        XCTAssertLessThan(r1!.timeIntervalSince(t0), 60 + 5)

        appState.recordStocksMetadataFailure()
        let r2 = appState.stocksNextRetryAfter
        XCTAssertGreaterThanOrEqual(r2!.timeIntervalSince(t0), 300 - 1)
        XCTAssertLessThan(r2!.timeIntervalSince(t0), 300 + 5)

        appState.recordStocksMetadataFailure()
        let r3 = appState.stocksNextRetryAfter
        XCTAssertGreaterThanOrEqual(r3!.timeIntervalSince(t0), 1800 - 1)
        XCTAssertLessThan(r3!.timeIntervalSince(t0), 1800 + 5)

        // Cap: 4th failure should still produce ~1800s, not grow further.
        appState.recordStocksMetadataFailure()
        let r4 = appState.stocksNextRetryAfter
        XCTAssertGreaterThanOrEqual(r4!.timeIntervalSince(t0), 1800 - 1)
        XCTAssertLessThan(r4!.timeIntervalSince(t0), 1800 + 5)
    }
}

/// Test connectivity stub: always claims online so AppState code paths run.
private final class AlwaysOnlineConnectivity: NetworkConnectivity {
    var isConnected: Bool { true }
}
