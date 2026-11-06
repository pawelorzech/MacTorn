import XCTest
@testable import MacTorn

/// The 1 s live countdown runs only while something is counting down.
final class LiveTimerTests: XCTestCase {

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
}
