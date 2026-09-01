import XCTest
@testable import MacTorn

/// Torn's v1 `faction/?selections=chain` sends `timeout` as **seconds remaining** and
/// `end` as the absolute expiry (verified live 2026-09-01). The app's consumers compare
/// `timeout` against the server clock as an absolute timestamp, so the value has to be
/// resolved at the fetch boundary. These tests pin that contract; before the fix the
/// chain card read 0:00, the alert never fired and Next Action pointed at 1970.
@MainActor
final class FactionChainExpiryTests: XCTestCase {
    /// Verbatim live payload shape from 2026-09-01 (server_time 1_788_292_436).
    private let liveChainJSON: [String: Any] = [
        "current": 1,
        "max": 10,
        "timeout": 146,
        "modifier": 1,
        "cooldown": 0,
        "start": 1_788_292_282,
        "end": 1_788_292_582,
    ]

    private func decode(_ json: [String: Any]) throws -> FactionChain {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(FactionChain.self, from: data)
    }

    // MARK: - Decoding

    func testDecodesEndAndKeepsRawTimeout() throws {
        let chain = try decode(liveChainJSON)
        XCTAssertEqual(chain.timeout, 146, "raw wire value is seconds remaining")
        XCTAssertEqual(chain.end, 1_788_292_582)
    }

    func testMissingOrZeroEndDecodesAsNil() throws {
        XCTAssertNil(try decode(["current": 1, "max": 10, "timeout": 30, "cooldown": 0]).end)
        XCTAssertNil(try decode(["current": 0, "max": 10, "timeout": 0, "cooldown": 0, "end": 0]).end)
    }

    // MARK: - Resolution

    func testResolvingExpiryPrefersTornEndTimestamp() throws {
        let chain = try decode(liveChainJSON)
        let resolved = chain.resolvingExpiry(fetchedAt: Date(), clock: .synchronized)
        XCTAssertEqual(resolved.timeout, 1_788_292_582, "`end` is Torn's own absolute expiry")
        XCTAssertEqual(resolved.end, 1_788_292_582)
        XCTAssertEqual(resolved.current, 1)
        XCTAssertEqual(resolved.max, 10)
    }

    func testResolvingExpiryAnchorsRelativeTimeoutToServerClockWhenEndIsAbsent() throws {
        let chain = try decode(["current": 42, "max": 100, "timeout": 250, "cooldown": 0])
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = ServerClock(offset: 90)   // Mac is 90 s behind Torn
        let resolved = chain.resolvingExpiry(fetchedAt: fetchedAt, clock: clock)
        XCTAssertEqual(resolved.timeout, 1_700_000_000 + 90 + 250,
                       "seconds remaining are anchored to Torn's now at receipt, not the Mac's")
        XCTAssertEqual(resolved.end, resolved.timeout)
    }

    func testInactiveChainIsLeftUntouched() throws {
        let idle = try decode(["current": 0, "max": 10, "timeout": 0, "cooldown": 0])
        let resolved = idle.resolvingExpiry(fetchedAt: Date(), clock: .synchronized)
        XCTAssertEqual(resolved.timeout, 0, "no chain, no expiry to invent")
        XCTAssertNil(resolved.end)

        let cooling = try decode(["current": 0, "max": 10, "timeout": 0, "cooldown": 3_600])
        XCTAssertEqual(cooling.resolvingExpiry(fetchedAt: Date(), clock: .synchronized).cooldown, 3_600)
    }

    // MARK: - End to end through the fetch boundary

    func testFetchResolvesLiveWireShapeSoChainSurfacesAreAlive() async throws {
        let mock = MockNetworkSession()
        let app = AppState(session: mock)
        app.serverClock = .synchronized
        let now = Int(Date().timeIntervalSince1970)
        try mock.setSuccessResponse(json: [
            "name": "The Masters",
            "ID": 11_559,
            "respect": 5_056_869,
            "chain": [
                "current": 1, "max": 10, "timeout": 146, "modifier": 1, "cooldown": 0,
                "start": now - 154, "end": now + 146,
            ],
        ])

        let payload = try await app.factionService.loadBasic(from: URL(string: "https://api.torn.com/faction/?selections=basic,chain")!)
        guard case .success(let data, _) = payload else { return XCTFail("expected a decoded faction payload") }
        app.factionService.publishBasic(data.resolvingChainExpiry(fetchedAt: Date(), clock: app.serverClock))

        let chain = try XCTUnwrap(app.liveChain)
        XCTAssertTrue(chain.isActive)
        let remaining = chain.timeoutRemaining(at: app.serverNow)
        XCTAssertGreaterThan(remaining, 140, "a 146 s chain must not read as expired")
        XCTAssertLessThanOrEqual(remaining, 146)
        XCTAssertEqual(app.makeNextActionSnapshot().chainTimeoutAt, now + 146,
                       "Next Action sees the absolute expiry, not 146 seconds after 1970")
    }
}
