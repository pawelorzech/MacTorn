import XCTest
@testable import MacTorn

final class UserSnapshotServiceTests: XCTestCase {
    func testParsesValidSnapshotIntoTypedPayload() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        var json = TornAPIFixtures.validFullResponse()
        json["money_onhand"] = 123
        json["strength"] = 456
        let data = try TornAPIFixtures.toData(json)

        let result = await service.parseSnapshot(
            data: data,
            requestedSelections: ["basic", "bars", "money", "battlestats"],
            grantedSelections: nil
        )

        guard case .success(let payload, let bytes) = result else {
            return XCTFail("Expected a typed snapshot payload")
        }
        XCTAssertEqual(payload.snapshot.name, "TestPlayer")
        XCTAssertEqual(payload.money.cash, 123)
        XCTAssertEqual(payload.battleStats.strength, 456)
        XCTAssertEqual(bytes, data.count)
    }

    func testRejectsEmptySnapshotWithoutPublishingDefaults() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        let data = try TornAPIFixtures.toData([:])

        let result = await service.parseSnapshot(
            data: data,
            requestedSelections: ["basic", "bars"],
            grantedSelections: nil
        )

        guard case .malformed(let bytes) = result else {
            return XCTFail("Expected malformed response")
        }
        XCTAssertEqual(bytes, data.count)
    }

    func testGrantedProfileSelectionDoesNotRequireBars() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        let data = try TornAPIFixtures.toData([
            "name": "ProfileOnly",
            "player_id": 42
        ])

        let result = await service.parseSnapshot(
            data: data,
            requestedSelections: ["basic", "bars"],
            grantedSelections: ["basic"]
        )

        guard case .success(let payload, _) = result else {
            return XCTFail("Expected profile-only payload")
        }
        XCTAssertEqual(payload.snapshot.name, "ProfileOnly")
    }

    func testLoadsActivityThroughInjectedSession() async throws {
        let mock = MockNetworkSession()
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        mock.mockData = data
        let service = UserSnapshotService(session: mock)

        let result = try await service.loadActivity(
            URL(string: "https://api.torn.com/user")!
        )

        guard case .success(let payload, let bytes) = result else {
            return XCTFail("Expected activity payload")
        }
        XCTAssertEqual(payload.events?.count, 1)
        XCTAssertEqual(payload.unreadMessages, 1)
        XCTAssertEqual(bytes, data.count)
    }

    func testLoadsUserV2SectionsIndependently() async throws {
        let mock = MockNetworkSession()
        let data = try TornAPIFixtures.toData(
            TornAPIFixtures.userV2Response(
                bounties: [TornAPIFixtures.bountyOnMe()]
            )
        )
        mock.mockData = data
        let service = UserSnapshotService(session: mock)

        let result = try await service.loadUserV2(
            URL(string: "https://api.torn.com/v2/user")!
        )

        guard case .success(let payload, let bytes) = result else {
            return XCTFail("Expected v2 payload")
        }
        XCTAssertEqual(payload.organizedCrime?.id, 1_836_033)
        XCTAssertEqual(payload.bounties.count, 1)
        XCTAssertNotNil(payload.refills)
        XCTAssertNotNil(payload.education)
        XCTAssertEqual(bytes, data.count)
    }

    func testReportsTornAPIErrorWithoutDecodingPayload() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIError(code: 14, message: "Daily read limit reached")
        let service = UserSnapshotService(session: mock)

        let result = try await service.loadActivity(
            URL(string: "https://api.torn.com/user")!
        )

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected Torn API error")
        }
        XCTAssertTrue(error.haltsCategoryOnly)
    }
}
