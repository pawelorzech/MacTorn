import XCTest
@testable import MacTorn

/// The gate is the only thing standing between MacTorn and a request it already knows
/// cannot produce data. These tests pin the two directions that matter: it must refuse on
/// facts it has, and it must never refuse on a fact it lacks.
@MainActor
final class TornEndpointGateTests: XCTestCase {

    private var clock: MutableTimeSource!
    private var gate: TornEndpointGate!
    private var coordinator: PollingCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        clock = MutableTimeSource()
        gate = TornEndpointGate(time: clock)
        coordinator = PollingCoordinator(time: clock)
    }

    // MARK: - Fixtures

    /// A spec-accurate `/key/info` payload, decoded through the real decoder so these
    /// tests exercise the same shape production does.
    private func keyInfo(userSelections: [String] = [
                            "basic", "bars", "cooldowns", "travel", "profile", "money",
                            "battlestats", "properties", "stocks", "organizedcrime",
                            "refills", "education", "bounties", "events", "messages", "attacks",
                         ],
                         factionID: Int? = 100,
                         accessLevel: Int = 3,
                         factionAccess: Bool = true) throws -> TornKeyInfo {
        let json: [String: Any] = [
            "info": [
                "access": ["level": accessLevel, "type": "Limited Access",
                           "faction": factionAccess, "company": false,
                           "log": ["custom_permissions": false, "available": []]],
                "user": ["id": 42,
                         "faction_id": factionID.map { $0 as Any } ?? NSNull(),
                         "company_id": NSNull()],
                "selections": [
                    "user": userSelections,
                    "faction": ["basic", "chain", "rankedwars", "news"],
                    "market": ["itemmarket", "bazaar"],
                    "property": [],
                    "torn": ["stocks"],
                    "racing": [],
                    "forum": [],
                    "key": ["info"],
                    "company": [],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(TornKeyInfo.Response.self, from: data).info
    }

    private func denial(_ id: String, keyInfo: TornKeyInfo? = nil) -> TornEndpointDenial? {
        gate.denial(for: id, keyInfo: keyInfo, coordinator: coordinator)
    }

    // MARK: - Never refuse on missing knowledge

    func testUnvalidatedKeyBlocksNothing() {
        for endpoint in TornEndpointRegistry.all {
            XCTAssertNil(denial(endpoint.id),
                         "\(endpoint.id) must be allowed while the key is unvalidated")
        }
    }

    func testUnknownEndpointIsReportedRatherThanSilentlyAllowed() {
        XCTAssertEqual(denial("does.not.exist"), .unknownEndpoint)
    }

    // MARK: - Key-derived refusals

    func testFactionEndpointsAreSkippedForAFactionlessPlayer() throws {
        let info = try keyInfo(factionID: nil)
        let factionEndpoints = TornEndpointRegistry.all.filter(\.requiresFaction)
        XCTAssertFalse(factionEndpoints.isEmpty, "the registry should mark faction endpoints")
        for endpoint in factionEndpoints {
            XCTAssertEqual(denial(endpoint.id, keyInfo: info), .notInFaction,
                           "\(endpoint.id) should not be requested without a faction")
        }
    }

    func testFactionEndpointsRunForAPlayerInAFaction() throws {
        XCTAssertNil(denial("faction.basic", keyInfo: try keyInfo(factionID: 12345)))
    }

    func testEndpointIsRefusedOnlyWhenEverySelectionIsUngranted() throws {
        let fastPoll = TornEndpointRegistry.endpoint(id: "user.fast")!

        // A key that can read nothing under `user` cannot serve the fast poll at all.
        let barren = try keyInfo(userSelections: [])
        XCTAssertEqual(denial("user.fast", keyInfo: barren),
                       .keyLacksSelections(fastPoll.selections))

        // …but one readable selection is enough to be worth the call. The request itself
        // is narrowed to that selection by `TornEndpoint.url(granted:)`, so the user keeps
        // their bars instead of losing the whole poll to one forbidden selection.
        let minimal = try keyInfo(userSelections: ["bars"])
        XCTAssertNil(denial("user.fast", keyInfo: minimal),
                     "a key that can read bars must still get its bars")
    }

    func testDedicatedMinimalEndpointIsRefusedForPublicOnlyKey() throws {
        XCTAssertEqual(denial("user.virus", keyInfo: try keyInfo(accessLevel: 1)),
                       .keyAccessLevelTooLow(required: .minimal))
    }

    func testFactionNewsIsRefusedWithoutFactionAPIPermission() throws {
        XCTAssertEqual(denial("faction.news", keyInfo: try keyInfo(factionAccess: false)),
                       .factionAPIAccessDisabled)
    }

    // MARK: - Cool-offs

    func testPauseHoldsForTheErrorsDurationAndThenLifts() throws {
        let error = TornAPIError.classify(code: 14, message: "")
        let pause = try XCTUnwrap(error.pauseDuration)
        gate.note(error, for: "user.activity")
        XCTAssertTrue(gate.isPaused("user.activity"))
        XCTAssertNil(denial("user.fast"), "one paused endpoint must not stop the others")

        clock.advance(pause - 1)
        XCTAssertTrue(gate.isPaused("user.activity"))

        clock.advance(2)
        XCTAssertFalse(gate.isPaused("user.activity"))
        XCTAssertNil(denial("user.activity"))
    }

    func testShorterCoolOffNeverShortensALongerOne() {
        gate.note(TornAPIError.classify(code: 8, message: ""), for: "user.fast")   // 1 h IP block
        gate.note(TornAPIError.classify(code: 5, message: ""), for: "user.fast")   // 1 min rate limit

        clock.advance(120)
        XCTAssertTrue(gate.isPaused("user.fast"),
                      "a rate-limit blip must not release an hour-long IP block early")
    }

    func testErrorsWithNoCoolOffLeaveNoMark() {
        gate.note(.transport(detail: "timeout"), for: "user.fast")
        gate.note(TornAPIError.classify(code: 17, message: ""), for: "user.fast")
        XCTAssertFalse(gate.isPaused("user.fast"),
                       "the next poll tick is already the retry for a transient failure")
    }

    /// An IP block, suspended key and per-user rate limit refuse everything. Pausing only the endpoint that
    /// noticed would leave the rest firing into the same wall.
    func testAnAccountWideFailurePausesEveryEndpoint() {
        gate.noteAccountWideFailure(TornAPIError.classify(code: 8, message: ""))
        for endpoint in TornEndpointRegistry.all {
            XCTAssertTrue(gate.isPaused(endpoint.id), "\(endpoint.id) kept running through an IP block")
        }
        clock.advance(3_601)
        for endpoint in TornEndpointRegistry.all {
            XCTAssertFalse(gate.isPaused(endpoint.id), "\(endpoint.id) never came back")
        }
    }


    func testPerUserRateLimitPausesEveryEndpoint() {
        gate.noteAccountWideFailure(TornAPIError.classify(code: 5, message: ""))
        for endpoint in TornEndpointRegistry.all {
            XCTAssertTrue(gate.isPaused(endpoint.id), "\(endpoint.id) kept running through a per-user limit")
        }
        clock.advance(61)
        XCTAssertTrue(gate.activePauses().isEmpty)
    }

    func testAnAccountWideFailureWithNoCoolOffPausesNothing() {
        gate.noteAccountWideFailure(.transport(detail: "timeout"))
        XCTAssertTrue(gate.activePauses().isEmpty)
    }

    func testResetClearsEveryPause() {
        gate.note(TornAPIError.classify(code: 14, message: ""), for: "user.activity")
        gate.reset()
        XCTAssertFalse(gate.isPaused("user.activity"))
        XCTAssertTrue(gate.activePauses().isEmpty)
    }

    func testPermissionRefreshRetriesOnlyOnceUntilSuccess() {
        XCTAssertTrue(gate.beginPermissionRetry(for: "user.v2"))
        XCTAssertFalse(gate.beginPermissionRetry(for: "user.v2"),
                       "a persistent code 16 must not recurse forever")
        gate.noteSuccess(for: "user.v2")
        XCTAssertTrue(gate.beginPermissionRetry(for: "user.v2"),
                      "a later successful response re-arms recovery")
    }

    // MARK: - Budgets

    func testRowBudgetIsEnforcedAndNotMerelyMeasured() {
        let activity = TornEndpointRegistry.endpoint(id: "user.activity")!
        let callsToExhaust = coordinator.recordBudgetPerDayPerCategory / activity.recordsPerCall + 1
        for _ in 0..<callsToExhaust {
            coordinator.record(activity)
            clock.advance(60) // stay clear of the per-minute cap
        }
        XCTAssertEqual(denial("user.activity"), .rowBudgetExhausted(.activity))
        XCTAssertNil(denial("user.fast"),
                     "a point-in-time endpoint spends no rows and must keep running")
    }

    func testPerMinuteCapIsTheLastGate() {
        let fast = TornEndpointRegistry.endpoint(id: "user.fast")!
        for _ in 0..<coordinator.hardCapPerMinute { coordinator.record(fast) }
        XCTAssertEqual(denial("user.fast"), .perMinuteCapReached)
    }

    // MARK: - Diagnostics surface

    func testActivePausesPrunesExpiredEntries() {
        gate.note(TornAPIError.classify(code: 5, message: ""), for: "user.fast")
        XCTAssertEqual(gate.activePauses().count, 1)
        clock.advance(3_600)
        XCTAssertTrue(gate.activePauses().isEmpty)
    }

    /// Every denial has to be able to answer "why is this tab empty?" in words.
    func testEveryDenialExplainsItselfInPlainWords() {
        let denials: [TornEndpointDenial] = [
            .paused(until: clock.now.addingTimeInterval(600), reason: .dailyRowLimit),
            .paused(until: clock.now.addingTimeInterval(30), reason: .rateLimit),
            .keyLacksSelections(["battlestats"]),
            .keyAccessLevelTooLow(required: .minimal),
            .factionAPIAccessDisabled,
            .notInFaction,
            .rowBudgetExhausted(.activity),
            .perMinuteCapReached,
            .unknownEndpoint,
        ]
        for denial in denials {
            let explanation = denial.userExplanation
            XCTAssertFalse(explanation.isEmpty)
            XCTAssertFalse(explanation.contains("("), "\(explanation) still reads like a log line")
            XCTAssertFalse(explanation.contains("\n"))
        }
    }

    func testDenialLabelsAreShortAndSingleLine() throws {
        let labels: [String] = [
            try XCTUnwrap(denial("user.fast", keyInfo: try keyInfo(userSelections: []))).label,
            TornEndpointDenial.notInFaction.label,
            TornEndpointDenial.perMinuteCapReached.label,
            TornEndpointDenial.rowBudgetExhausted(.activity).label,
        ]
        for label in labels {
            XCTAssertFalse(label.contains("\n"), "denial labels go straight into os_log")
            XCTAssertFalse(label.isEmpty)
        }
    }
}
