import XCTest
@testable import MacTorn

/// Etap E — the dedup primitives, their persistence, and the AppState chain wiring.
@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = .createMockDefaults()
    }

    // MARK: - Edge latch

    func testEdgeFiresOnceWhileActive() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true), "first entry into danger fires")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true), "still in danger — no re-fire")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true))
    }

    func testEdgeReArmsAfterClearing() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true))
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: false), "leaving danger doesn't fire")
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true), "new danger window fires again")
    }

    func testEdgeStartingInactiveDoesNotFire() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: false))
    }

    func testEdgeKeysAreIndependent() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true))
        XCTAssertTrue(coord.shouldFireOnEdge("landing", active: true), "different key, own latch")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true))
    }

    func testEdgeLatchSurvivesRestart() {
        NotificationCoordinator(defaults: defaults).shouldFireOnEdge("chain", active: true)
        // Simulate relaunch: a fresh coordinator over the same store.
        let relaunched = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(relaunched.isLatched("chain"))
        XCTAssertFalse(relaunched.shouldFireOnEdge("chain", active: true),
                       "relaunch mid-danger must not re-alert")
        XCTAssertTrue(relaunched.shouldFireOnEdge("chain", active: false) == false)
        XCTAssertTrue(relaunched.shouldFireOnEdge("chain", active: true), "re-arms after clearing post-restart")
    }

    // MARK: - Epoch dedup

    func testOnceFiresPerDistinctEpoch() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "123"))
        XCTAssertFalse(coord.shouldFireOnce("oc", epoch: "123"), "same epoch suppressed")
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "456"), "new epoch fires")
    }

    func testOnceSurvivesRestart() {
        NotificationCoordinator(defaults: defaults).shouldFireOnce("oc", epoch: "123")
        let relaunched = NotificationCoordinator(defaults: defaults)
        XCTAssertFalse(relaunched.shouldFireOnce("oc", epoch: "123"), "dedup persists across restart")
    }

    func testResetClearsState() {
        let coord = NotificationCoordinator(defaults: defaults)
        coord.shouldFireOnEdge("chain", active: true)
        coord.shouldFireOnce("oc", epoch: "1")
        coord.reset()
        XCTAssertFalse(coord.isLatched("chain"))
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "1"), "reset forgets the epoch")
    }

    // MARK: - AppState chain-expiring regression (the reported bug)

    private func chain(inSeconds seconds: Int, current: Int = 5) -> Chain {
        // `timeout` is an absolute Unix timestamp; timeoutRemaining = timeout - now.
        makeChain(current: current, timeout: Int(Date().timeIntervalSince1970) + seconds)
    }

    func testChainAlertFiresOnceAcrossManySubThresholdPolls() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        // Poll repeatedly while the chain sits in the danger window.
        var fireCount = 0
        for _ in 0..<10 {
            if appState.chainExpiringShouldFire(chain(inSeconds: 45)) { fireCount += 1 }
        }
        XCTAssertEqual(fireCount, 1, "exactly one alert while timeout stays < 60s")
    }

    func testChainAlertReArmsAfterMemberHits() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        XCTAssertTrue(appState.chainExpiringShouldFire(chain(inSeconds: 40)), "enters danger → fire")
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 40)), "still in danger → silent")
        // A member hits — timeout jumps back above the threshold.
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 300)), "safe again → silent + re-arm")
        // Timer winds down into the danger window again.
        XCTAssertTrue(appState.chainExpiringShouldFire(chain(inSeconds: 30)), "new danger window → fire again")
    }

    func testChainAlertDoesNotFireWhenInactiveOrAboveThreshold() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        XCTAssertFalse(appState.chainExpiringShouldFire(nil))
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 300)), "above threshold")
        XCTAssertFalse(appState.chainExpiringShouldFire(makeChain(current: 0, timeout: 0)), "inactive chain")
    }
}
