import XCTest
@testable import MacTorn

/// Etap C / ISC-16 — key-info decoding, the pure availability validator, and
/// `AppState.validateKey` over a mock session. The wire shape is pinned to the verified
/// Torn v2 `/key/info` schema.
final class KeyValidationTests: XCTestCase {

    private let fullUserSelections = [
        "basic", "bars", "cooldowns", "travel", "profile", "money", "battlestats",
        "properties", "stocks", "organizedcrime", "refills", "education", "bounties",
        "events", "messages", "attacks",
    ]

    /// Builds a spec-accurate `/key/info` payload.
    private func keyInfoJSON(level: Int,
                             type: String,
                             userSelections: [String],
                             factionSelections: [String] = ["basic", "chain"],
                             marketSelections: [String] = ["itemmarket", "bazaar"],
                             tornSelections: [String] = ["stocks"],
                             playerID: Int = 42,
                             factionID: Int? = 100) -> [String: Any] {
        [
            "info": [
                "access": ["level": level, "type": type, "faction": true, "company": false,
                           "log": ["custom_permissions": false, "available": []]],
                "user": ["id": playerID,
                         "faction_id": factionID.map { $0 as Any } ?? NSNull(),
                         "company_id": NSNull()],
                "selections": [
                    "user": userSelections,
                    "faction": factionSelections,
                    "market": marketSelections,
                    "property": [],
                    "torn": tornSelections,
                    "racing": [],
                    "forum": [],
                    "key": ["info"],
                    "company": [],
                ],
            ],
        ]
    }

    private func decode(_ json: [String: Any]) throws -> TornKeyInfo {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(TornKeyInfo.Response.self, from: data).info
    }

    // MARK: - Decoding

    func testDecodesVerifiedSchema() throws {
        let info = try decode(keyInfoJSON(level: 4, type: "Full Access", userSelections: fullUserSelections))
        XCTAssertEqual(info.access.type, "Full Access")
        XCTAssertEqual(info.access.level, 4)
        XCTAssertTrue(info.access.faction)
        XCTAssertEqual(info.user.id, 42)
        XCTAssertEqual(info.user.factionId, 100)
        XCTAssertNil(info.user.companyId)
        XCTAssertTrue(info.selections.user.contains("battlestats"))
        XCTAssertEqual(info.selections.market, ["itemmarket", "bazaar"])
    }

    func testDecodesNullFactionId() throws {
        let info = try decode(keyInfoJSON(level: 3, type: "Limited Access",
                                          userSelections: fullUserSelections, factionID: nil))
        XCTAssertNil(info.user.factionId)
    }

    // MARK: - Validator

    func testFullKeyMakesEveryEndpointAvailable() throws {
        let info = try decode(keyInfoJSON(level: 4, type: "Full Access", userSelections: fullUserSelections))
        let result = KeyValidator.validate(info)
        XCTAssertTrue(result.allCriticalAvailable)
        XCTAssertEqual(result.unavailableCount, 0)
        XCTAssertEqual(result.playerID, 42)
        XCTAssertTrue(result.inFaction)
    }

    func testMissingUserSelectionBlocksTheCriticalFastPoll() throws {
        // A Custom key that omits battlestats.
        let selections = fullUserSelections.filter { $0 != "battlestats" }
        let info = try decode(keyInfoJSON(level: 3, type: "Custom", userSelections: selections))
        let result = KeyValidator.validate(info)

        let fast = try XCTUnwrap(result.availability.first { $0.endpointID == "user.fast" })
        XCTAssertFalse(fast.available)
        XCTAssertEqual(fast.missingSelections, ["battlestats"])
        XCTAssertFalse(result.allCriticalAvailable, "user.fast is critical")
    }

    func testEmptyFactionSelectionsBlocksFaction() throws {
        let info = try decode(keyInfoJSON(level: 3, type: "Limited Access",
                                          userSelections: fullUserSelections, factionSelections: []))
        let result = KeyValidator.validate(info)
        let faction = try XCTUnwrap(result.availability.first { $0.endpointID == "faction.basic" })
        XCTAssertFalse(faction.available)
        XCTAssertEqual(Set(faction.missingSelections), Set(["basic", "chain"]))
    }

    func testParameterizedEndpointsAreAvailableRegardlessOfSelections() throws {
        // A public-only key with no user selections still reaches selection-less endpoints.
        let info = try decode(keyInfoJSON(level: 1, type: "Public Only", userSelections: []))
        let result = KeyValidator.validate(info)
        for id in ["forum.thread", "forum.threads", "faction.rankedwars", "key.info"] {
            let ep = try XCTUnwrap(result.availability.first { $0.endpointID == id })
            XCTAssertTrue(ep.available, "\(id) takes no selections and should be available")
        }
    }

    func testCategoryMapping() throws {
        func category(_ id: String) throws -> TornKeyInfo.Category {
            KeyValidator.category(for: try XCTUnwrap(TornEndpointRegistry.endpoint(id: id)))
        }
        XCTAssertEqual(try category("user.fast"), .user)
        XCTAssertEqual(try category("user.v2"), .user)
        XCTAssertEqual(try category("faction.basic"), .faction)
        XCTAssertEqual(try category("market.item"), .market)
        XCTAssertEqual(try category("torn.stocks"), .torn)
        XCTAssertEqual(try category("forum.thread"), .forum)
    }

    // MARK: - AppState.validateKey

    @MainActor
    private func makeState(_ mock: MockNetworkSession) -> AppState {
        AppState(session: mock,
                 connectivity: ControllableConnectivity(connected: true),
                 defaults: .createMockDefaults())
    }

    @MainActor
    func testValidateKeyPublishesSuccess() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: keyInfoJSON(level: 4, type: "Full Access",
                                                      userSelections: fullUserSelections))
        let state = makeState(mock)
        state.apiKey = "sample-onboarding-value"

        await state.validateKey()

        guard case .success(let result) = state.keyValidation else {
            return XCTFail("expected success, got \(state.keyValidation)")
        }
        XCTAssertEqual(result.accessType, "Full Access")
        XCTAssertEqual(result.playerID, 42)
        XCTAssertTrue(result.allCriticalAvailable)
        XCTAssertNotNil(state.keyInfo)
    }

    @MainActor
    func testValidateKeyClassifiesErrorEnvelope() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIErrorV2(code: 2, message: "Incorrect key")
        let state = makeState(mock)
        state.apiKey = "sample-onboarding-value"

        await state.validateKey()

        guard case .failure = state.keyValidation else {
            return XCTFail("expected failure for a bad key")
        }
        XCTAssertNil(state.keyInfo, "a failed validation must not leave stale key info")
    }

    @MainActor
    func testValidateKeyWithEmptyKeyFailsWithoutNetwork() async {
        let mock = MockNetworkSession()
        let state = makeState(mock)
        state.apiKey = ""

        await state.validateKey()

        guard case .failure = state.keyValidation else {
            return XCTFail("empty key should fail fast")
        }
        XCTAssertTrue(mock.requestedURLs.isEmpty, "no request should be made for an empty key")
    }

    @MainActor
    func testChangingKeyResetsValidation() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: keyInfoJSON(level: 4, type: "Full Access",
                                                      userSelections: fullUserSelections))
        let state = makeState(mock)
        state.apiKey = "sample-onboarding-value"
        await state.validateKey()
        XCTAssertNotNil(state.keyInfo)

        state.apiKey = "sample-different-value"
        XCTAssertEqual(state.keyValidation, .idle)
        XCTAssertNil(state.keyInfo)
    }
}
