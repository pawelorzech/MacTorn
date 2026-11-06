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
    func testLiveTimerStopsAtDeadlineAndRestartsForNewCooldown() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("{}".utf8))
        app.player.cooldownEnds = CooldownEnds(drugEndsAt: 1010, boosterEndsAt: 0, medicalEndsAt: 0)
        app.manageLiveTimer()
        XCTAssertNotNil(app.liveTimerCancellable)
        clock.advance(10)
        app.tick()
        XCTAssertNil(app.liveTimerCancellable)
        XCTAssertEqual(app.player.menuBarDisplay, .fallbackIcon)
        app.player.cooldownEnds = CooldownEnds(drugEndsAt: 1030, boosterEndsAt: 0, medicalEndsAt: 0)
        app.manageLiveTimer()
        XCTAssertNotNil(app.liveTimerCancellable)
        app.resetAccountScopedState()
    }

    @MainActor
    func testExpiredTravelStopsTimerWithoutConfirmingArrival() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data(#"{"travel":{"destination":"Japan","time_left":10,"timestamp":1010}}"#.utf8))
        app.manageLiveTimer()
        XCTAssertNotNil(app.liveTimerCancellable)
        clock.advance(10)
        app.tick()
        XCTAssertNil(app.liveTimerCancellable)
        XCTAssertEqual(app.player.menuBarDisplay, .traveling(destination: "Japan", seconds: 0))
        XCTAssertEqual(app.player.data?.travel?.isTraveling, true)
    }

    func testRetryBackoffLadderCapsAtThirtyMinutesAndClearsOnSuccess() {
        var backoff = RetryBackoff()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for expected: TimeInterval in [60, 300, 1_800, 1_800] {
            backoff.fail(at: t0)
            XCTAssertEqual(backoff.retryAfter, t0.addingTimeInterval(expected))
        }
        XCTAssertFalse(backoff.allows(at: t0.addingTimeInterval(1_799)))
        XCTAssertTrue(backoff.allows(at: t0.addingTimeInterval(1_800)))
        backoff.succeed()
        XCTAssertTrue(backoff.allows(at: t0))
    }
}

/// Test connectivity stub: always claims online so AppState code paths run.
private final class AlwaysOnlineConnectivity: NetworkConnectivity {
    var isConnected: Bool { true }
    var onConnectivityRestored: (() -> Void)?
}
