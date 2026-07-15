import XCTest
@testable import MacTorn

/// Unit coverage for the deterministic UI-test harness (Etap G / ISC-20). The XCUITest
/// suite proves the harness end-to-end; these pin its pure routing/decoding contract so a
/// regression is caught in milliseconds without launching the app.
#if DEBUG
final class UITestHarnessTests: XCTestCase {

    private let fakeKey = "sample-harness-value"

    // MARK: - Fixture routing

    func testFullScenarioServesDecodableUserResponse() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)

        let decoded = try JSONDecoder().decode(TornResponse.self, from: data)
        XCTAssertEqual(decoded.name, "TestPlayer")
        XCTAssertNotNil(decoded.bars, "The full fixture should populate bars")
    }

    func testInvalidKeyScenarioServesErrorEnvelope() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .invalidKey)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 2, "Invalid-key fixture must carry Torn code 2")
    }

    func testEmptyScenarioServesEmptyObject() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .empty)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Empty scenario should serve {}")
    }

    /// Only the fast user call (which carries the `bars` selection) gets the rich fixture;
    /// the faction call must not be mistaken for it.
    func testFactionEndpointServesEmptyObjectEvenInFullScenario() throws {
        let url = TornAPI.factionURL(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Faction endpoint should not receive the user fixture")
    }

    /// The row-based activity call also hits the `/user/` path but without `bars`; it must
    /// not be served the fast-user fixture (which would double-count / mis-decode).
    func testUserActivityCallIsNotServedFastFixture() throws {
        let url = TornAPI.activityURL(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Activity call must not get the fast-user fixture")
    }

    func testNilURLDoesNotCrashAndServesEmpty() {
        let data = FixtureNetworkSession.body(for: nil, scenario: .full)
        XCTAssertFalse(data.isEmpty, "A nil URL should still yield a valid (empty-object) body")
    }

    // MARK: - Scenario parsing

    func testFixtureScenarioRawValues() {
        XCTAssertEqual(FixtureScenario(rawValue: "full"), .full)
        XCTAssertEqual(FixtureScenario(rawValue: "invalidKey"), .invalidKey)
        XCTAssertEqual(FixtureScenario(rawValue: "empty"), .empty)
        XCTAssertNil(FixtureScenario(rawValue: "nonsense"))
    }
}
#endif
