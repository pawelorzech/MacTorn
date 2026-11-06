import XCTest
import os.log
@testable import MacTorn

/// Live-timer lifecycle and retry back-off regression guards.
final class AppStatePerformanceTests: XCTestCase {

    @MainActor
    func testLiveTimerStopsAtDeadlineAndRestartsForNewCooldown() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("{}".utf8))
        app.player.cooldownEnds = CooldownEnds(drugEndsAt: 1010, boosterEndsAt: 0, medicalEndsAt: 0)
        app.manageLiveTimer()
        XCTAssertTrue(app.liveTimer.isRunning)
        clock.advance(10)
        app.tick()
        XCTAssertFalse(app.liveTimer.isRunning)
        XCTAssertEqual(app.player.menuBarDisplay, .fallbackIcon)
        app.player.cooldownEnds = CooldownEnds(drugEndsAt: 1030, boosterEndsAt: 0, medicalEndsAt: 0)
        app.manageLiveTimer()
        XCTAssertTrue(app.liveTimer.isRunning)
        app.resetAccountScopedState()
    }

    @MainActor
    func testExpiredTravelStopsTimerWithoutConfirmingArrival() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data(#"{"travel":{"destination":"Japan","time_left":10,"timestamp":1010}}"#.utf8))
        app.manageLiveTimer()
        XCTAssertTrue(app.liveTimer.isRunning)
        clock.advance(10)
        app.tick()
        XCTAssertFalse(app.liveTimer.isRunning)
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
