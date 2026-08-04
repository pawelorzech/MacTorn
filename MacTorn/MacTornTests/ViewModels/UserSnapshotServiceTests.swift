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

    /// Issue #84: a 200 body that simply omits the row-based selections must report
    /// *absent* (nil) for every field, so `AppState.fetchActivityData`'s `if let`
    /// guards leave the last known events/messages/attacks alone. Reporting `[]`/`0`
    /// here silently wipes the user's event list on any partial response.
    func testActivityBodyWithoutRowSelectionsReportsEveryFieldAsAbsent() async throws {
        let mock = MockNetworkSession()
        mock.mockData = try TornAPIFixtures.toData([:])
        let service = UserSnapshotService(session: mock)

        let result = try await service.loadActivity(
            URL(string: "https://api.torn.com/user")!
        )

        guard case .success(let payload, _) = result else {
            return XCTFail("Expected activity payload")
        }
        XCTAssertNil(payload.events, "A missing \"events\" key must not decode to []")
        XCTAssertNil(payload.unreadMessages, "A missing \"messages\" key must not decode to 0")
        XCTAssertNil(payload.recentAttacks, "A missing \"attacks\" key must not decode to []")
    }

    /// The mirror image of the test above: when the keys *are* present but empty, the
    /// endpoint really is saying "zero rows", and that must overwrite stale state.
    func testActivityBodyWithEmptyRowSelectionsReportsZeroRatherThanAbsent() async throws {
        let mock = MockNetworkSession()
        mock.mockData = try TornAPIFixtures.toData([
            "events": [String: Any](),
            "messages": [String: Any](),
            "attacks": [String: Any]()
        ])
        let service = UserSnapshotService(session: mock)

        let result = try await service.loadActivity(
            URL(string: "https://api.torn.com/user")!
        )

        guard case .success(let payload, _) = result else {
            return XCTFail("Expected activity payload")
        }
        XCTAssertEqual(payload.events?.isEmpty, true)
        XCTAssertEqual(payload.unreadMessages, 0)
        XCTAssertEqual(payload.recentAttacks?.isEmpty, true)
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

    func testParsePropertiesSortsDeterministicallyByPropertyId() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        let data = try TornAPIFixtures.toData([
            "name": "TestPlayer",
            "player_id": 1,
            "bars": [
                "energy": ["current": 10, "maximum": 10],
                "nerve": ["current": 10, "maximum": 10],
                "life": ["current": 10, "maximum": 10],
                "happy": ["current": 10, "maximum": 10]
            ],
            "properties": [
                "100": ["property_id": 100, "property": "Castle", "cost": 500],
                "10": ["property_id": 10, "property": "Shack", "cost": 100],
                "50": ["property_id": 50, "property": "Ranch", "cost": 300]
            ]
        ])

        let result = await service.parseSnapshot(
            data: data,
            requestedSelections: ["basic", "bars", "properties"],
            grantedSelections: nil
        )

        guard case .success(let payload, _) = result, let properties = payload.properties else {
            return XCTFail("Expected properties in payload")
        }
        XCTAssertEqual(properties.map(\.id), [10, 50, 100])
    }

    func testParseStocksSortsDeterministicallyByStockId() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        let data = try TornAPIFixtures.toData([
            "name": "TestPlayer",
            "player_id": 1,
            "bars": [
                "energy": ["current": 10, "maximum": 10],
                "nerve": ["current": 10, "maximum": 10],
                "life": ["current": 10, "maximum": 10],
                "happy": ["current": 10, "maximum": 10]
            ],
            "stocks": [
                "25": ["stock_id": 25, "total_shares": 500],
                "3": ["stock_id": 3, "total_shares": 100],
                "12": ["stock_id": 12, "total_shares": 200]
            ]
        ])

        let result = await service.parseSnapshot(
            data: data,
            requestedSelections: ["basic", "bars", "stocks"],
            grantedSelections: nil
        )

        guard case .success(let payload, _) = result else {
            return XCTFail("Expected stocks in payload")
        }
        XCTAssertEqual(payload.stocks.map(\.stockId), [3, 12, 25])
    }
}
