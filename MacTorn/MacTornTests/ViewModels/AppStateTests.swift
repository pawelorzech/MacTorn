import XCTest
@testable import MacTorn

@MainActor
final class AppStateTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var appState: AppState!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults = .createMockDefaults()
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession, defaults: testDefaults)
        // Clear any persisted data
        testDefaults.removeObject(forKey: "apiKey")
        testDefaults.removeObject(forKey: "watchlist")
        testDefaults.removeObject(forKey: "notificationRules")
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        try await super.tearDown()
    }

    // MARK: - Etap D: request budget wiring + reconnect refresh

    func testFetchRecordsAgainstRequestBudget() {
        let conn = ControllableConnectivity(connected: true)
        let app = AppState(session: MockNetworkSession(), connectivity: conn, defaults: .createMockDefaults())
        app.apiKey = "valid_key"
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, 0)
        app.refreshNow()   // the accepted `/key/info` handshake is recorded synchronously
        XCTAssertGreaterThanOrEqual(app.pollingCoordinator.requestsInLastMinute, 1,
                                    "a poll must be recorded against the API budget")
        app.stopPolling()
    }

    func testReconnectTriggersRefresh() {
        let conn = ControllableConnectivity(connected: true)
        let app = AppState(session: MockNetworkSession(), connectivity: conn, defaults: .createMockDefaults())
        app.apiKey = "valid_key"
        XCTAssertNotNil(conn.onConnectivityRestored, "AppState wires the reconnect handler")

        let before = app.pollingCoordinator.requestsInLastMinute
        conn.goOffline()
        conn.restore()   // down→up edge → refreshNow records the ordered capability request
        XCTAssertGreaterThan(app.pollingCoordinator.requestsInLastMinute, before,
                             "a restored connection refreshes immediately")
        app.stopPolling()
    }

    func testOfflineFetchRecordsNothing() {
        let conn = ControllableConnectivity(connected: false)
        let app = AppState(session: MockNetworkSession(), connectivity: conn, defaults: .createMockDefaults())
        app.apiKey = "valid_key"
        app.refreshNow()   // fetchData bails on the connectivity guard before recording
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, 0)
        app.stopPolling()
    }

    // MARK: - Etap B: permanent key error halts polling (ISC-15)

    func testPermanentKeyErrorHaltsPolling() async throws {
        let conn = ControllableConnectivity(connected: true)
        let mock = MockNetworkSession()
        let app = AppState(session: mock, connectivity: conn, defaults: .createMockDefaults())
        app.apiKey = "bad_key"
        app.keyValidation = .validating
        app.moneyData = MoneyData(cash: 42)
        try mock.setSuccessResponse(json: ["code": 2, "error": "Incorrect key"]) // HTTP 200 + Torn envelope
        app.startPolling()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertTrue(app.keyHalted, "a code-2 error must halt polling")
        XCTAssertNil(app.data)
        XCTAssertNil(app.moneyData, "revoked credentials must not leave stale account data visible")
        XCTAssertNotNil(app.errorMsg)
        guard case .failure = app.keyValidation else {
            return XCTFail("a permanently rejected key must invalidate prior validation")
        }
        app.stopPolling()
    }

    func testChangingKeyClearsHalt() {
        let app = AppState(session: MockNetworkSession(), connectivity: ControllableConnectivity(), defaults: .createMockDefaults())
        app.apiKey = "bad_key"
        app.keyHalted = true
        app.apiKey = "fresh_key"   // didSet clears the halt
        XCTAssertFalse(app.keyHalted)
    }

    func testChangingKeyClearsPreviouslyAuthenticatedAccountData() throws {
        let app = AppState(session: MockNetworkSession(),
                           connectivity: ControllableConnectivity(),
                           defaults: .createMockDefaults())
        app.apiKey = "account_a"
        app.data = try JSONDecoder().decode(
            TornResponse.self,
            from: TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        )
        app.moneyData = MoneyData(cash: 1_000, vault: 2_000)
        app.activityEvents = try XCTUnwrap(app.data?.recentEvents)
        app.lastUpdated = Date()

        app.apiKey = "account_b"

        XCTAssertNil(app.data)
        XCTAssertNil(app.moneyData)
        XCTAssertTrue(app.activityEvents.isEmpty)
        XCTAssertNil(app.lastUpdated)
        XCTAssertEqual(app.menuBarDisplay, .fallbackIcon)
    }

    func testResponseFromPreviousKeyCannotOverwriteCurrentAccount() async throws {
        let delayed = try NonCooperativeDelayedNetworkSession(
            json: TornAPIFixtures.validFullResponse(),
            delay: 0.25
        )
        let app = AppState(session: delayed,
                           connectivity: ControllableConnectivity(),
                           defaults: .createMockDefaults())
        app.apiKey = "account_a"
        app.fetchData()
        try await Task.sleep(nanoseconds: 50_000_000)

        app.apiKey = "account_b"
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNil(app.data, "a non-cooperative response for account A must be discarded")
        XCTAssertNil(app.lastUpdated)
        XCTAssertFalse(app.isLoading)
    }

    func testKeyValidationFromPreviousKeyCannotOverwriteCurrentAccount() async throws {
        let delayed = try NonCooperativeDelayedNetworkSession(
            json: [
                "info": [
                    "access": [
                        "level": 4, "type": "Full Access",
                        "faction": true, "company": false
                    ],
                    "user": [
                        "id": 42, "faction_id": 100,
                        "company_id": NSNull()
                    ],
                    "selections": [
                        "user": [], "faction": [], "market": [],
                        "property": [], "torn": [], "racing": [],
                        "forum": [], "key": ["info"], "company": []
                    ]
                ]
            ],
            delay: 0.25
        )
        let app = AppState(session: delayed,
                           connectivity: ControllableConnectivity(),
                           defaults: .createMockDefaults())
        app.apiKey = "account_a"
        let validation = Task { await app.validateKey() }
        try await Task.sleep(nanoseconds: 50_000_000)

        app.apiKey = "account_b"
        await validation.value

        XCTAssertEqual(app.keyValidation, .idle)
        XCTAssertNil(app.keyInfo)
    }

    func testHaltedPollingIssuesNoRequests() {
        let app = AppState(session: MockNetworkSession(), connectivity: ControllableConnectivity(), defaults: .createMockDefaults())
        app.apiKey = "key"
        app.keyHalted = true       // set after apiKey (which would otherwise clear it)
        let before = app.pollingCoordinator.requestsInLastMinute
        app.startPolling()         // must early-return without issuing a request
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, before)
        app.stopPolling()
    }

    // MARK: - API Key Validation Tests

    func testFetchData_emptyAPIKey() async {
        appState.apiKey = ""

        appState.fetchData()

        // Wait for async completion
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(appState.errorMsg, "API Key required")
        XCTAssertNil(appState.data)
    }

    // These two used to assert `errorMsg == "Invalid API Key"` and `data == nil` for a
    // transport-level 403/404. That contract was wrong and is now inverted (audit
    // finding C-02): Torn reports a rejected key as HTTP 200 with an `error` envelope,
    // handled by `handlePermanentKeyError`. A 403/404 comes from the edge/CDN and is
    // transient — blaming the key sent users off to regenerate a working one, and
    // clearing `data` blanked every panel until the next poll.

    func testHTTP403IsTreatedAsTransientAndKeepsTheLastGoodSnapshot() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNotNil(appState.data, "precondition: a good snapshot is on screen")

        mockSession.setHTTPError(statusCode: 403)
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "HTTP Error: 403",
                       "an edge/CDN rejection must not be reported as a bad key")
        XCTAssertNotNil(appState.data,
                        "a transient HTTP error must not wipe the last good snapshot")
        XCTAssertFalse(appState.keyHalted, "polling must keep running")
    }

    func testHTTP404IsTreatedAsTransientAndKeepsTheLastGoodSnapshot() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNotNil(appState.data)

        mockSession.setHTTPError(statusCode: 404)
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "HTTP Error: 404")
        XCTAssertNotNil(appState.data)
        XCTAssertFalse(appState.keyHalted)
    }

    /// The genuine bad-key path is unchanged and still halts — pinned here so the
    /// relaxation above cannot quietly swallow a real credential failure.
    func testTornErrorEnvelopeStillHaltsOnBadKey() async throws {
        appState.apiKey = "bad_key"
        try mockSession.setSuccessResponse(json: ["code": 2, "error": "Incorrect key"])

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertTrue(appState.keyHalted)
        XCTAssertNil(appState.data)
    }

    // MARK: - Fetch Success Tests

    func testFetchData_success() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())

        appState.fetchData()

        // Wait for async completion
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(appState.data)
        XCTAssertEqual(appState.data?.name, "TestPlayer")
        XCTAssertEqual(appState.data?.playerId, 123456)
        XCTAssertNil(appState.errorMsg)
        XCTAssertNotNil(appState.lastUpdated)
    }

    func testMalformedResponseDoesNotAdvanceLastSuccessfulRefresh() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: ["energy": "not-an-object"])

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNil(appState.lastUpdated)
        XCTAssertEqual(appState.errorMsg, "Failed to decode user data")
        XCTAssertEqual(appState.endpointHealth.latest(for: "user.fast")?.outcome, .error)
    }

    func testEmptyResponsePreservesLastGoodSnapshotAndTimestamp() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let goodSnapshot = try XCTUnwrap(appState.data)
        let goodTimestamp = try XCTUnwrap(appState.lastUpdated)

        try mockSession.setSuccessResponse(json: [:])
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.data?.playerId, goodSnapshot.playerId)
        XCTAssertEqual(appState.data?.name, goodSnapshot.name)
        XCTAssertEqual(appState.lastUpdated, goodTimestamp)
        XCTAssertEqual(appState.errorMsg, "Failed to decode user data")
        XCTAssertEqual(appState.endpointHealth.latest(for: "user.fast")?.outcome, .error)
    }

    func testNetworkErrorMessageNeverEchoesSensitiveLocalizedDescription() async throws {
        appState.apiKey = "valid_key"
        let secret = "TOP_SECRET_API_KEY"
        mockSession.setNetworkError(
            NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "failed https://api.torn.com/user/?key=\(secret)"
            ])
        )

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(appState.errorMsg)
        XCTAssertFalse(appState.errorMsg?.contains(secret) == true)
    }

    func testAllRequestPathsRespectInjectedHardCap() async throws {
        let coordinator = PollingCoordinator(hardCapPerMinute: 1)
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: TornAPIFixtures.validFullResponse())
        let app = AppState(session: mock,
                           connectivity: ControllableConnectivity(),
                           defaults: .createMockDefaults(),
                           pollingCoordinator: coordinator)
        app.apiKey = "valid_key"

        await app.validateKey()
        let countAtCap = mock.requestedURLs.count
        app.addToWatchlist(itemId: 206, name: "Xanax")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(countAtCap, 1)
        XCTAssertEqual(mock.requestedURLs.count, 1,
                       "market refresh must not bypass the shared per-minute cap")
        XCTAssertEqual(app.watchlistItems.first?.error, "Request limit reached")
    }

    func testInvalidPersistedRefreshIntervalFallsBackToSafeDefault() {
        let defaults = UserDefaults.createMockDefaults()
        defaults.set(0, forKey: "refreshInterval")

        let app = AppState(session: MockNetworkSession(), defaults: defaults)

        XCTAssertEqual(app.refreshInterval, 30)
    }

    func testRuntimeRefreshIntervalRejectsUnsafeValue() {
        appState.refreshInterval = -1

        XCTAssertEqual(appState.refreshInterval, 30)
        XCTAssertEqual(testDefaults.integer(forKey: "refreshInterval"), 30)
    }

    func testFetchData_parsesAllBars() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(appState.data?.bars)
        XCTAssertEqual(appState.data?.energy?.current, 100)
        XCTAssertEqual(appState.data?.nerve?.current, 50)
        XCTAssertEqual(appState.data?.life?.current, 7500)
        XCTAssertEqual(appState.data?.happy?.current, 5000)
    }

    // MARK: - Torn API Error Tests

    // MARK: - Cooldown End-Time Conversion

    /// The whole point of `cooldownEnds`: at fetch time we convert each relative
    /// cooldown duration into an absolute server-time end-timestamp, so countdowns
    /// stay matched to torn.com regardless of Mac↔server clock skew or how long
    /// has passed since the fetch.
    func testFetchData_cooldownEnds_computedFromServerTimestampPlusDuration() async throws {
        let serverTs = 1_730_000_000  // arbitrary, not "now" — proves we use the API value, not Date()
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.responseWithCooldowns(
                timestamp: serverTs,
                drug: 0,
                booster: 3600,
                medical: 1200
            )
        )

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let ends = try XCTUnwrap(appState.cooldownEnds)
        XCTAssertEqual(ends.drugEndsAt, 0, "Inactive cooldown (drug=0) should be stored as 0, not anchor+0")
        XCTAssertEqual(ends.boosterEndsAt, serverTs + 3600)
        XCTAssertEqual(ends.medicalEndsAt, serverTs + 1200)
    }

    /// Falls back to local `Date()` if the API response includes neither `server_time`
    /// nor the legacy `timestamp` (partial responses). Don't crash, don't drop the
    /// cooldowns — just lose the clock-skew correction.
    func testFetchData_cooldownEnds_fallbackToLocalNow_whenServerTimestampMissing() async throws {
        appState.apiKey = "valid_key"
        var json = TornAPIFixtures.responseWithCooldowns(
            timestamp: 0,
            drug: 0,
            booster: 600,
            medical: 0
        )
        json.removeValue(forKey: "server_time")
        json.removeValue(forKey: "timestamp")
        try mockSession.setSuccessResponse(json: json)

        let before = Int(Date().timeIntervalSince1970)
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let after = Int(Date().timeIntervalSince1970)

        let ends = try XCTUnwrap(appState.cooldownEnds)
        XCTAssertGreaterThanOrEqual(ends.boosterEndsAt, before + 600)
        XCTAssertLessThanOrEqual(ends.boosterEndsAt, after + 600)
    }

    /// Regression: the live API anchors on `server_time`, but a response carrying only
    /// the legacy `timestamp` key must still anchor on it (dual-key decode), not fall
    /// back to local `Date()`. Guards the fallback path added alongside the server_time fix.
    func testFetchData_cooldownEnds_anchorsOnLegacyTimestamp_whenServerTimeMissing() async throws {
        let legacyTs = 1_730_000_000  // arbitrary, not "now"
        appState.apiKey = "valid_key"
        var json = TornAPIFixtures.responseWithCooldowns(
            timestamp: 0, drug: 0, booster: 3600, medical: 0
        )
        json.removeValue(forKey: "server_time")
        json["timestamp"] = legacyTs
        try mockSession.setSuccessResponse(json: json)

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let ends = try XCTUnwrap(appState.cooldownEnds)
        XCTAssertEqual(ends.boosterEndsAt, legacyTs + 3600,
                       "legacy `timestamp` must anchor cooldowns when `server_time` is absent")
    }

    // MARK: - API v2 user data (own organized crime)

    /// End-to-end: the combined v2 user response flows through `fetchData` into
    /// `organizedCrime`. Guards the fetch→decode→state wiring that replaced the dead
    /// v1 `faction/crimes` (OC 1.0) feature. The mock returns the same body for every
    /// request; the v1 parse degrades gracefully, but `fetchUserV2Data` picks up the OC.
    func testFetchData_populatesOwnOrganizedCrime_fromV2() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.userV2Response())

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let oc = try XCTUnwrap(appState.organizedCrime, "v2 organized crime should be parsed")
        XCTAssertEqual(oc.name, "Clinical Precision")
        XCTAssertEqual(oc.difficulty, 8)
        XCTAssertEqual(oc.filledSlots, 2)
        XCTAssertEqual(oc.myProgress(playerId: 2362436), 100)
    }

    /// A bounty in the v2 response lands in `bountiesOnMe` for the alert badge.
    func testFetchData_populatesBountiesOnMe_fromV2() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.userV2Response(bounties: [TornAPIFixtures.bountyOnMe(reward: 3_000_000)])
        )

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.bountiesOnMe.count, 1)
        XCTAssertEqual(appState.bountiesOnMe.first?.reward, 3_000_000)
    }

    func testMalformedUserV2SectionPreservesLastGoodState() throws {
        let existing = try JSONDecoder().decode(
            Bounty.self,
            from: TornAPIFixtures.toData(TornAPIFixtures.bountyOnMe(reward: 9_000_000))
        )
        appState.bountiesOnMe = [existing]
        appState.notificationCounts = TornNotifications(messages: 7)

        appState.applyUserV2Payload(UserV2Payload(
            organizedCrime: .unchanged,
            refills: .unchanged,
            education: .unchanged,
            bounties: .unchanged,
            notifications: .replace(TornNotifications(messages: 2)),
            malformedSelections: ["bounties"]
        ))

        XCTAssertEqual(appState.bountiesOnMe, [existing])
        XCTAssertEqual(appState.notificationCounts?.messages, 2,
                       "a valid sibling section must still update")
    }

    // MARK: - Bounty notification dedup (#53)

    /// The bug: `notifiedBountyKeys` was an in-memory `Set`, so it was empty at every
    /// launch and every bounty still hanging on the player re-announced itself. Five open
    /// bounties meant five banners, on every single start.
    func testBountyNotification_dedupSurvivesRelaunch() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.userV2Response(bounties: [TornAPIFixtures.bountyOnMe(reward: 3_000_000)])
        )

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let bounty = try XCTUnwrap(appState.bountiesOnMe.first)
        let key = "bounty.\(bounty.id)"

        // The fetch consumed the one-shot, so asking again must report "already fired".
        XCTAssertFalse(
            appState.notificationCoordinator.shouldFireOnce(key, epoch: bounty.id),
            "the bounty should have announced itself during the fetch and latched"
        )

        // A second AppState over the SAME defaults is a relaunch. Before this fix the
        // in-memory set started empty here and the bounty fired again.
        let relaunched = AppState(session: MockNetworkSession(), defaults: testDefaults)
        XCTAssertFalse(
            relaunched.notificationCoordinator.shouldFireOnce(key, epoch: bounty.id),
            "dedup must survive a relaunch — this is the whole of #53"
        )
    }

    /// Several new bounties in one poll collapse into one summary banner rather than a
    /// stack of them, the way `flushPendingPriceAlerts()` handles price alerts.
    func testBountyBanner_aggregatesWhenMoreThanOneIsNew() throws {
        let one = try XCTUnwrap(TornAPIFixtures.decodedBounty(reward: 1_000_000))
        let two = try XCTUnwrap(TornAPIFixtures.decodedBounty(reward: 2_500_000, targetId: 999))

        XCTAssertNil(AppState.bountyBanner(for: []), "nothing new means no banner at all")

        // Amounts are compared through the same formatter rather than against a literal
        // like "1,000,000". `AppState.decimalFormatter` has no explicit locale, so it
        // follows `Locale.current` — on a machine with German regional settings it emits
        // "1.000.000" and a hardcoded assertion fails for a reason that has nothing to do
        // with the behaviour under test.
        let expected = { (v: Int) in AppState.decimalFormatter.string(from: NSNumber(value: v)) ?? "\(v)" }

        let single = try XCTUnwrap(AppState.bountyBanner(for: [one]))
        XCTAssertEqual(single.title, "⚠️ Bounty on you")
        XCTAssertTrue(
            single.body.contains(expected(1_000_000)),
            "single banner keeps the amount, got \(single.body)"
        )

        let summary = try XCTUnwrap(AppState.bountyBanner(for: [one, two]))
        XCTAssertEqual(summary.title, "⚠️ 2 bounties on you")
        XCTAssertTrue(
            summary.body.contains(expected(3_500_000)),
            "summary totals both rewards, got \(summary.body)"
        )
    }

    /// Regression: rewards are untrusted API integers. Recording each bounty as seen
    /// must not be followed by a process trap when their display-only total exceeds Int.
    func testBountyBanner_handlesCombinedRewardsAboveIntMaxAfterDedup() throws {
        let maximum = try XCTUnwrap(TornAPIFixtures.decodedBounty(reward: .max))
        let one = try XCTUnwrap(TornAPIFixtures.decodedBounty(reward: 1, targetId: 999))
        let fresh = [maximum, one]

        for bounty in fresh {
            XCTAssertTrue(
                appState.notificationCoordinator.shouldFireOnce("bounty.\(bounty.id)", epoch: bounty.id)
            )
        }

        let summary = try XCTUnwrap(AppState.bountyBanner(for: fresh))
        let total = Decimal(Int.max) + 1
        let totalText = AppState.decimalFormatter.string(from: NSDecimalNumber(decimal: total)) ?? "\(total)"
        XCTAssertEqual(summary.body, "$\(totalText) total")

        for bounty in fresh {
            XCTAssertFalse(
                appState.notificationCoordinator.shouldFireOnce("bounty.\(bounty.id)", epoch: bounty.id)
            )
        }
    }

    /// Ranked wars from the dedicated v2 faction endpoint land in `rankedWars`.
    func testFetchData_populatesRankedWars_fromV2Faction() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertTrue(appState.rankedWars.contains { $0.isActive },
                      "the active ranked war should be parsed from the v2 faction call")
    }

    /// Ranked wars + news are heavy and slow-changing, so back-to-back polls must not
    /// re-fetch them within the 60s throttle — only the first poll hits the endpoint.
    func testFetchData_throttlesFactionV2Calls_withinInterval() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        appState.fetchData()  // second poll, well within the 60s window
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let rankedWarCalls = mockSession.requestedURLs.filter { $0.path.contains("rankedwars") }.count
        XCTAssertEqual(rankedWarCalls, 1, "the second poll within 60s must not re-fetch ranked wars")
    }

    // MARK: - CooldownEnds.from overflow guard (issue #87)

    /// The ordinary case must be untouched by the guard.
    func testCooldownEndsFrom_normalResponseIsUnchanged() {
        let anchor = 1_786_104_547
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: 3600, medical: 0, booster: 120), anchor: anchor)

        XCTAssertEqual(ends.drugEndsAt, anchor + 3600)
        XCTAssertEqual(ends.boosterEndsAt, anchor + 120)
        XCTAssertEqual(ends.medicalEndsAt, 0, "an inactive cooldown stays 0")
    }

    /// `anchor + duration` on raw API integers used to trap the process (SIGTRAP,
    /// exit 133). An unusable number must degrade that cooldown to "not active"
    /// rather than crash a display-only menu bar app.
    func testCooldownEndsFrom_hugeDurationDoesNotTrap() {
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: Int.max, medical: 0, booster: 0),
            anchor: 1_786_104_547)

        XCTAssertEqual(ends.drugEndsAt, 0, "overflow degrades to the not-active sentinel")
    }

    /// Every operand comes from the same untrusted payload, so the anchor can be
    /// hostile too — and all three cooldowns must be guarded, not just the first.
    func testCooldownEndsFrom_hugeAnchorDoesNotTrap() {
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: 60, medical: 60, booster: 60), anchor: Int.max)

        XCTAssertEqual(ends.drugEndsAt, 0)
        XCTAssertEqual(ends.boosterEndsAt, 0)
        XCTAssertEqual(ends.medicalEndsAt, 0)
    }

    /// Underflow is the same defect with the sign flipped.
    func testCooldownEndsFrom_negativeAnchorDoesNotTrap() {
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: Int.min, medical: 0, booster: 0), anchor: -1)

        XCTAssertEqual(ends.drugEndsAt, 0, "drug is guarded by duration > 0 before the add")
    }

    /// One bad cooldown must not take the other two with it — the guard is per field.
    func testCooldownEndsFrom_overflowIsIsolatedPerCooldown() {
        let anchor = 1_786_104_547
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: Int.max, medical: 300, booster: 600), anchor: anchor)

        XCTAssertEqual(ends.drugEndsAt, 0, "the bad one degrades")
        XCTAssertEqual(ends.medicalEndsAt, anchor + 300, "the good ones survive")
        XCTAssertEqual(ends.boosterEndsAt, anchor + 600)
    }

    /// A degraded cooldown must read as inactive to every consumer, not as an
    /// end-timestamp in 1970.
    func testCooldownEndsFrom_degradedCooldownReadsAsInactive() {
        let ends = CooldownEnds.from(
            cooldowns: Cooldowns(drug: Int.max, medical: 0, booster: 0),
            anchor: 1_786_104_547)
        let now = Date(timeIntervalSince1970: 1_786_104_547)

        XCTAssertEqual(ends.remainingSeconds(.drug, at: now), 0)
        XCTAssertNil(ends.soonestActive(at: now), "nothing is counting down")
    }

    // MARK: - CooldownEnds.merged (pure model)

    /// Per-poll jitter ≤ tolerance keeps the previously pinned `endsAt`. Without this,
    /// every poll re-derives `endsAt = serverTimestamp + cooldowns.{kind}`, and any
    /// ±1–3 s wobble in the API integers or in network latency reshuffles the
    /// displayed countdown — Paweł sees this as the menu bar jumping each ~30 s.
    func testCooldownEndsMerged_keepsOldWhenWithinTolerance() {
        let pinned = CooldownEnds(drugEndsAt: 1000, boosterEndsAt: 2000, medicalEndsAt: 3000)
        let jittered = CooldownEnds(drugEndsAt: 1002, boosterEndsAt: 1998, medicalEndsAt: 3001)

        let merged = pinned.merged(with: jittered)

        XCTAssertEqual(merged.drugEndsAt, 1000, "drug within ±3 s → keep pinned")
        XCTAssertEqual(merged.boosterEndsAt, 2000, "booster within ±3 s → keep pinned")
        XCTAssertEqual(merged.medicalEndsAt, 3000, "medical within ±3 s → keep pinned")
    }

    /// Beyond tolerance the cooldown was almost certainly reset (new booster taken,
    /// drug applied, medical cooldown after a hospital trip). Adopt the new value
    /// or the menu bar would freeze on a stale `endsAt`.
    func testCooldownEndsMerged_replacesWhenBeyondTolerance() {
        let pinned = CooldownEnds(drugEndsAt: 1000, boosterEndsAt: 2000, medicalEndsAt: 3000)
        let reset  = CooldownEnds(drugEndsAt: 5000, boosterEndsAt: 2004, medicalEndsAt: 3000)

        let merged = pinned.merged(with: reset)

        XCTAssertEqual(merged.drugEndsAt, 5000, "drug jumped 4000 s → adopt new")
        XCTAssertEqual(merged.boosterEndsAt, 2004, "booster +4 s → outside tolerance, adopt new")
        XCTAssertEqual(merged.medicalEndsAt, 3000, "medical unchanged → keep")
    }

    /// `0 → nonzero` means a cooldown just started; we want the menu bar to start
    /// counting down immediately, not pin to the `0`.
    func testCooldownEndsMerged_zeroToNonzero_takesNew() {
        let inactive = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 0, medicalEndsAt: 0)
        let started  = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 5400, medicalEndsAt: 0)

        let merged = inactive.merged(with: started)

        XCTAssertEqual(merged.boosterEndsAt, 5400)
    }

    /// `nonzero → 0` means the cooldown ended (server stopped reporting it); the
    /// pin must release so we don't keep showing a phantom countdown.
    func testCooldownEndsMerged_nonzeroToZero_takesNew() {
        let pinned   = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 5400, medicalEndsAt: 0)
        let inactive = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 0, medicalEndsAt: 0)

        let merged = pinned.merged(with: inactive)

        XCTAssertEqual(merged.boosterEndsAt, 0)
    }

    /// Custom tolerance lets callers tune the pin sensitivity if Torn's API jitter
    /// turns out to be larger than the 3 s default in practice.
    func testCooldownEndsMerged_respectsCustomTolerance() {
        let pinned = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 2000, medicalEndsAt: 0)
        let drift  = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 2008, medicalEndsAt: 0)

        XCTAssertEqual(pinned.merged(with: drift, toleranceSeconds: 3).boosterEndsAt, 2008,
                       "8 s > 3 s default → replace")
        XCTAssertEqual(pinned.merged(with: drift, toleranceSeconds: 10).boosterEndsAt, 2000,
                       "8 s ≤ 10 s relaxed → keep pinned")
    }

    // MARK: - Cooldown end-time pinning across polls (integration)

    /// End-to-end: simulate two consecutive polls where the server's `(timestamp,
    /// cooldowns.booster)` pair wobbles by 2 s — the boundary case where the second
    /// poll computes a slightly different `endsAt` than the first. AppState must
    /// keep the original pinned `endsAt` so the menu bar countdown does not jump.
    func testFetchData_cooldownEnds_pinnedAcrossPollsWithinTolerance() async throws {
        appState.apiKey = "valid_key"

        // Poll 1: serverTimestamp = T, booster = 3600 → endsAt = T + 3600
        let firstTs = 1_730_000_000
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.responseWithCooldowns(
                timestamp: firstTs, drug: 0, booster: 3600, medical: 0
            )
        )
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let firstEndsAt = try XCTUnwrap(appState.cooldownEnds?.boosterEndsAt)
        XCTAssertEqual(firstEndsAt, firstTs + 3600)

        // Poll 2 ~30 s later, but booster was rounded by API such that the recomputed
        // endsAt is 2 s earlier (typical integer-truncation jitter).
        // serverTimestamp += 30, booster = 3568 → fresh endsAt = T + 30 + 3568 = T + 3598
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.responseWithCooldowns(
                timestamp: firstTs + 30, drug: 0, booster: 3568, medical: 0
            )
        )
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let secondEndsAt = try XCTUnwrap(appState.cooldownEnds?.boosterEndsAt)
        XCTAssertEqual(secondEndsAt, firstEndsAt,
                       "Within ±3 s tolerance, the pinned endsAt must survive the next poll")
    }

    /// If the second poll diverges beyond tolerance (cooldown was reset / new booster
    /// taken), the pin must release and the new `endsAt` take over. Otherwise the
    /// menu bar would freeze on a stale value forever.
    func testFetchData_cooldownEnds_replacedAcrossPollsWhenCooldownReset() async throws {
        appState.apiKey = "valid_key"

        let firstTs = 1_730_000_000
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.responseWithCooldowns(
                timestamp: firstTs, drug: 0, booster: 600, medical: 0
            )
        )
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(appState.cooldownEnds?.boosterEndsAt, firstTs + 600)

        // Poll 2: user took a new booster — fresh endsAt is far in the future.
        try mockSession.setSuccessResponse(
            json: TornAPIFixtures.responseWithCooldowns(
                timestamp: firstTs + 30, drug: 0, booster: 18000, medical: 0
            )
        )
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.cooldownEnds?.boosterEndsAt, firstTs + 30 + 18000,
                       "Reset detected (>3 s gap) → adopt the new endsAt instead of pinning")
    }

    func testFetchData_tornAPIError() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIError(code: 2, message: "Incorrect Key")

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Etap B: code 2 is a permanent key error — polling now halts and the classified
        // message surfaces (previously this showed "API Error: Incorrect Key" and kept
        // retrying a dead key forever).
        XCTAssertTrue(appState.keyHalted)
        XCTAssertEqual(appState.errorMsg, "Incorrect Key")
        XCTAssertNil(appState.data)
    }

    func testFetchData_tornAPIRateLimit() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIError(code: 5, message: "Too many requests")

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "Too many requests — backing off.")
        XCTAssertEqual(mockSession.requestedURLs.count, 1,
                       "a rate-limited main response must not fan out optional requests")
        XCTAssertTrue(appState.isRowSourcePaused("forum.thread"),
                      "Torn's per-user rate limit must pause independent forum polling too")
    }

    func testFetchData_permissionErrorRefreshesCapabilitiesWithoutInvalidatingKey() async throws {
        appState.apiKey = "valid_but_limited_key"
        try mockSession.setTornAPIError(code: 16, message: "Access level too low")

        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertFalse(appState.keyHalted)
        XCTAssertEqual(appState.errorMsg, "Access level too low")
        XCTAssertLessThanOrEqual(mockSession.requestedURLs.count, 3,
                                 "a persistent code 16 must not create a capability-refresh loop")
    }

    // MARK: - Network Error Tests

    func testFetchData_networkError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setNetworkError(MockNetworkError.connectionFailed)

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "Network request failed. Please try again.")
    }

    // MARK: - HTTP Error Tests

    func testFetchData_HTTP500() async throws {
        appState.apiKey = "valid_key"
        mockSession.setHTTPError(statusCode: 500)

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "HTTP Error: 500")
    }

    func testFetchData_HTTP502() async throws {
        appState.apiKey = "valid_key"
        mockSession.setHTTPError(statusCode: 502)

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "HTTP Error: 502")
    }

    // MARK: - Polling Tests

    func testStartPolling_fetchesData() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())

        appState.startPolling()

        // Initial fetch should happen immediately
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertTrue(mockSession.requestedURLs.count >= 1)
        XCTAssertNotNil(appState.data)
    }

    func testStopPolling_stopsTimer() {
        appState.apiKey = "valid_key"
        appState.startPolling()

        appState.stopPolling()

        // Timer should be cancelled
        // No way to directly verify timer is nil, but we can verify no more requests happen
    }

    // MARK: - Loading State Tests

    func testFetchData_setsLoadingState() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())

        appState.fetchData()

        // Wait for completion - fetchData is async so loading transitions happen inside the Task
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // After completion, loading should be false
        XCTAssertFalse(appState.isLoading)
        // And we should have data
        XCTAssertNotNil(appState.data)
    }

    // MARK: - Notification Rules Tests

    func testLoadNotificationRules_defaults() {
        // Clear existing rules
        testDefaults.removeObject(forKey: "notificationRules")

        let newAppState = AppState(session: mockSession, defaults: testDefaults)

        XCTAssertFalse(newAppState.notificationRules.isEmpty)
        // Should have default rules
    }

    func testSaveNotificationRules() {
        let rule = NotificationRule(
            id: "test_rule",
            barType: .energy,
            threshold: 80,
            enabled: true,
            soundName: "default"
        )
        appState.notificationRules = [rule]
        appState.saveNotificationRules()

        // Reload
        appState.loadNotificationRules()

        XCTAssertEqual(appState.notificationRules.count, 1)
        XCTAssertEqual(appState.notificationRules.first?.id, "test_rule")
    }

    func testUpdateRule() {
        appState.notificationRules = NotificationRule.defaults

        var rule = appState.notificationRules.first!
        rule.enabled = false
        appState.updateRule(rule)

        XCTAssertFalse(appState.notificationRules.first!.enabled)
    }

    // MARK: - Refresh Now Tests

    func testRefreshNow_triggersFetch() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())

        // refreshNow calls fetchData which is async
        appState.refreshNow()

        // Wait for async completion
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Verify request was made
        XCTAssertGreaterThanOrEqual(mockSession.requestedURLs.count, 1)
        XCTAssertNotNil(appState.data)
    }

    func testRefreshNow_debouncesBurstAndAcceptsBoundaryAtThreeSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableTimeSource(start)
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults(),
            time: clock
        )
        app.apiKey = "debounce-\(UUID().uuidString)"
        // This test isolates the three-second manual debounce; first-session capability
        // ordering is covered by FirstPollOrderingTests.
        app.keyInfo = TornKeyInfo.testFixture()

        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 1)

        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 1, "a held shortcut must not start another poll")

        clock.advance(2.999)
        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 1, "the debounce remains closed before 3 seconds")

        clock.set(start.addingTimeInterval(3))
        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 2, "the boundary at 3 seconds accepts a new poll")
        app.stopPolling()
    }

    func testRefreshNow_newAccountBypassesPreviousAccountsDebounce() {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults(),
            time: clock
        )
        app.apiKey = "account-a-\(UUID().uuidString)"
        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 1)

        app.apiKey = "account-b-\(UUID().uuidString)"
        app.refreshNow()

        XCTAssertEqual(app.pollSequence, 2,
                       "saving a different key must refresh immediately at the same clock instant")
        app.stopPolling()
    }

    func testOfflineRefreshDoesNotConsumeDebounceBeforeReconnect() {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let connectivity = ControllableConnectivity(connected: false)
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: connectivity,
            defaults: .createMockDefaults(),
            time: clock
        )
        app.apiKey = "offline-\(UUID().uuidString)"

        app.refreshNow()
        XCTAssertEqual(app.pollSequence, 0, "an offline attempt never starts a poll")

        connectivity.restore()
        XCTAssertEqual(app.pollSequence, 1,
                       "the connectivity callback must refresh immediately without waiting 3 seconds")
        app.stopPolling()
    }

    func testOfflineTransportFailureReopensDebounceForReconnect() async throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let connectivity = ControllableConnectivity(connected: true)
        let service = ControlledHTTPErrorUserSnapshotService()
        defer { service.drain() }
        let firstStarted = expectation(description: "manual poll started")
        let reconnectStarted = expectation(description: "reconnect poll started")
        service.onLoad = { index in
            if index == 0 { firstStarted.fulfill() }
            if index == 1 { reconnectStarted.fulfill() }
        }
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: connectivity,
            defaults: .createMockDefaults(),
            time: clock,
            userSnapshotService: service
        )
        app.apiKey = "transport-offline-\(UUID().uuidString)"

        app.refreshNow()
        await fulfillment(of: [firstStarted], timeout: 1)
        service.fail(index: 0, error: URLError(.notConnectedToInternet))

        for _ in 0..<50 where app.errorMsg != TornAPIError.offline.userMessage {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(app.errorMsg, TornAPIError.offline.userMessage)

        connectivity.goOffline()
        connectivity.restore()
        XCTAssertEqual(app.pollSequence, 2,
                       "a real transport-offline failure must not debounce the reconnect callback")
        await fulfillment(of: [reconnectStarted], timeout: 1)
        service.complete(index: 1)
        app.stopPolling()
    }

    func testLatestAutomaticOfflineFailureReopensSupersededManualDebounce() async throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let connectivity = ControllableConnectivity(connected: true)
        let service = ControlledHTTPErrorUserSnapshotService()
        defer { service.drain() }
        let manualStarted = expectation(description: "manual poll started")
        let automaticStarted = expectation(description: "automatic poll started")
        let reconnectStarted = expectation(description: "reconnect poll started")
        service.onLoad = { index in
            if index == 0 { manualStarted.fulfill() }
            if index == 1 { automaticStarted.fulfill() }
            if index == 2 { reconnectStarted.fulfill() }
        }
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: connectivity,
            defaults: .createMockDefaults(),
            time: clock,
            userSnapshotService: service
        )
        app.apiKey = "superseded-offline-\(UUID().uuidString)"

        app.refreshNow()
        await fulfillment(of: [manualStarted], timeout: 1)
        app.fetchData()
        await fulfillment(of: [automaticStarted], timeout: 1)
        service.fail(index: 1, error: URLError(.notConnectedToInternet))

        for _ in 0..<50 where app.errorMsg != TornAPIError.offline.userMessage {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(app.errorMsg, TornAPIError.offline.userMessage)

        connectivity.goOffline()
        connectivity.restore()
        XCTAssertEqual(app.pollSequence, 3,
                       "the latest automatic failure must reopen the superseded manual debounce")
        await fulfillment(of: [reconnectStarted], timeout: 1)

        service.complete(index: 0)
        service.complete(index: 2)
        app.stopPolling()
    }

    func testRefreshNowDoesNotReplaceTheAutomaticPollingTimer() throws {
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults()
        )
        app.apiKey = "timer-\(UUID().uuidString)"
        app.startPolling()
        let timer = try XCTUnwrap(app.timerCancellable)

        app.refreshNow()

        XCTAssertTrue(app.timerCancellable === timer,
                      "manual refresh must not cancel and recreate the automatic timer")
        app.stopPolling()
    }

    func testRefreshNowRestoresMissingAutomaticTimerAfterKeyIsSaved() {
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults()
        )
        app.apiKey = "timer-restore-\(UUID().uuidString)"
        XCTAssertNil(app.timerCancellable)

        app.refreshNow()

        XCTAssertNotNil(app.timerCancellable,
                        "saving a key after polling was stopped must resume automatic polling")
        app.stopPolling()
    }

    func testCancelledPollCleanupCannotHideNewerPollSpinner() async throws {
        let service = ControlledHTTPErrorUserSnapshotService()
        defer { service.drain() }
        let firstStarted = expectation(description: "first poll started")
        let secondStarted = expectation(description: "second poll started")
        service.onLoad = { index in
            if index == 0 { firstStarted.fulfill() }
            if index == 1 { secondStarted.fulfill() }
        }
        let app = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults(),
            userSnapshotService: service
        )
        app.apiKey = "spinner-\(UUID().uuidString)"

        app.fetchData()
        await fulfillment(of: [firstStarted], timeout: 1)
        app.fetchData()
        await fulfillment(of: [secondStarted], timeout: 1)

        service.complete(index: 0)

        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(app.isLoading,
                      "the first poll's delayed cleanup must not hide the second poll's spinner")

        service.complete(index: 1)
        for _ in 0..<100 where app.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(app.isLoading, "the current poll must still clear loading on its error path")
        XCTAssertEqual(app.pollSequence, 2)
        app.stopPolling()
    }

    // MARK: - Menu Bar Display Tests

    /// Helper: build a fixture from `validFullResponse` with a custom travel/status/cooldowns slice.
    private func fixture(
        travel: [String: Any]? = nil,
        status: [String: Any]? = nil,
        cooldowns: [String: Any]? = nil
    ) -> [String: Any] {
        var json = TornAPIFixtures.validFullResponse()
        if let travel = travel { json["travel"] = travel }
        if let status = status { json["status"] = status }
        if let cooldowns = cooldowns { json["cooldowns"] = cooldowns }
        return json
    }

    private func fetch(_ json: [String: Any]) async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: json)
        appState.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func testMenuBarDisplay_traveling() async throws {
        try await fetch(fixture(travel: TornAPIFixtures.travelTraveling))

        guard case .traveling(let destination, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .traveling, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(destination, "Japan")
        // The rendered glyph is derived from the name, so the menu bar still shows the flag.
        XCTAssertEqual(TornDestination.flag(for: destination ?? ""), "🇯🇵")
        XCTAssertGreaterThan(seconds, 0)
        XCTAssertLessThanOrEqual(seconds, 600)
    }

    func testMenuBarDisplay_hospitalAbroad() async throws {
        let abroad: [String: Any] = [
            "destination": "Mexico", "timestamp": 0, "departed": 0, "time_left": 0
        ]
        let hospital: [String: Any] = [
            "description": "In hospital", "details": "", "state": "Hospital",
            "until": Int(Date().timeIntervalSince1970) + 600
        ]
        try await fetch(fixture(travel: abroad, status: hospital))

        guard case .hospitalAbroad(let destination, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .hospitalAbroad, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(destination, "Mexico")
        XCTAssertEqual(TornDestination.flag(for: destination ?? ""), "🇲🇽")
        XCTAssertGreaterThan(seconds, 500)
        XCTAssertLessThanOrEqual(seconds, 600)
    }

    func testMenuBarDisplay_hospitalAtHome() async throws {
        let hospital: [String: Any] = [
            "description": "In hospital", "details": "", "state": "Hospital",
            "until": Int(Date().timeIntervalSince1970) + 300
        ]
        try await fetch(fixture(status: hospital))

        guard case .hospitalAtHome(let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .hospitalAtHome, got \(appState.menuBarDisplay)")
        }
        XCTAssertGreaterThan(seconds, 200)
        XCTAssertLessThanOrEqual(seconds, 300)
    }

    func testMenuBarDisplay_jail() async throws {
        let jail: [String: Any] = [
            "description": "In jail", "details": "", "state": "Jail",
            "until": Int(Date().timeIntervalSince1970) + 450
        ]
        try await fetch(fixture(status: jail))

        guard case .jail(let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .jail, got \(appState.menuBarDisplay)")
        }
        XCTAssertGreaterThan(seconds, 350)
        XCTAssertLessThanOrEqual(seconds, 450)
    }

    func testMenuBarDisplay_idleSoonestCooldown() async throws {
        // Medical (60s) is soonest — drug 300, booster 1200
        try await fetch(fixture(cooldowns: ["drug": 300, "booster": 1200, "medical": 60]))

        guard case .cooldown(let kind, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .cooldown, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(kind, .medical)
        XCTAssertEqual(kind.emoji, "🩹")
        XCTAssertGreaterThan(seconds, 50)
        XCTAssertLessThanOrEqual(seconds, 60)
    }

    func testMenuBarDisplay_idleNoCooldowns_fallsBack() async throws {
        try await fetch(TornAPIFixtures.validFullResponse()) // all cooldowns 0, status Okay, in Torn

        XCTAssertEqual(appState.menuBarDisplay, .fallbackIcon)
    }

    func testMenuBarDisplay_travelingBeatsHospital() async throws {
        // Player is traveling; even with hospital status, travel takes priority.
        let hospital: [String: Any] = [
            "description": "In hospital", "details": "", "state": "Hospital",
            "until": Int(Date().timeIntervalSince1970) + 600
        ]
        try await fetch(fixture(travel: TornAPIFixtures.travelTraveling, status: hospital))

        if case .traveling = appState.menuBarDisplay { /* ok */ }
        else { XCTFail("Expected .traveling to win, got \(appState.menuBarDisplay)") }
    }

    // MARK: - ISC-15.1: daily-row-limit pauses only the offending row source

    /// A code-14 "daily read limit" on the fan-out pauses the row-based sources
    /// (`user.activity`, `faction.news`) but NOT the point-in-time `faction.basic` that
    /// drives the chain alert.
    func testDailyRowLimitPausesOnlyRowSources() async throws {
        let clock = MutableTimeSource()
        let mock = try DailyRowLimitNetworkSession()
        let state = AppState(session: mock,
                             connectivity: ControllableConnectivity(connected: true),
                             defaults: .createMockDefaults(),
                             time: clock)
        state.apiKey = "sample-value"

        state.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertTrue(state.isRowSourcePaused("user.activity"), "activity should pause on code 14")
        XCTAssertTrue(state.isRowSourcePaused("faction.news"), "faction news should pause on code 14")
        XCTAssertFalse(state.isRowSourcePaused("faction.basic"),
                       "point-in-time faction/chain must keep running")
        state.stopPolling()
    }

    /// The pause re-arms once its window elapses (driven by the injected clock).
    func testRowSourcePauseReArmsAfterWindow() async throws {
        let clock = MutableTimeSource()
        let mock = try DailyRowLimitNetworkSession()
        let state = AppState(session: mock,
                             connectivity: ControllableConnectivity(connected: true),
                             defaults: .createMockDefaults(),
                             time: clock)
        state.apiKey = "sample-value"

        state.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertTrue(state.isRowSourcePaused("user.activity"))

        clock.advance(3601)   // just past the 1 h pause window
        XCTAssertFalse(state.isRowSourcePaused("user.activity"), "pause should re-arm after the window")
        state.stopPolling()
    }

    // MARK: - F-02: endpoint health across the poll fan-out

    /// A successful poll records health for every fan-out endpoint, not just the fast poll.
    func testFetchDataRecordsHealthForFanOutEndpoints() async throws {
        let session = try FanOutSuccessNetworkSession()
        let state = AppState(
            session: session,
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults()
        )
        state.apiKey = "valid_key"

        state.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        for id in ["user.fast", "faction.basic", "user.v2", "user.activity",
                   "faction.rankedwars", "faction.news"] {
            XCTAssertEqual(state.endpointHealth.latest(for: id)?.outcome, .ok,
                           "health should be recorded (ok) for \(id)")
        }
    }

    /// A successful stocks-metadata fetch records endpoint health (F-02 completion).
    func testFetchStocksMetadataRecordsHealth() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.stocksData)

        await appState.fetchStocksMetadata()

        XCTAssertEqual(appState.endpointHealth.latest(for: "torn.stocks")?.outcome, .ok)
    }

    // MARK: - ISC-18: OC-ready dedup routed through the coordinator (persistent)

    /// OC-ready fires once per distinct OC id, and the dedup survives a relaunch (the old
    /// in-memory `previousOCReadyId` re-alerted after restart). A new OC id re-arms.
    func testOCReadyDedupIsPerIdAndPersistsAcrossRestart() {
        let defaults = UserDefaults.createMockDefaults()
        let mock = MockNetworkSession()
        let state = AppState(session: mock,
                             connectivity: ControllableConnectivity(connected: true),
                             defaults: defaults)

        let now = Int(Date().timeIntervalSince1970)
        let ready5 = OrganizedCrime2(id: 5, name: "Test OC", readyAt: now - 10)

        XCTAssertTrue(state.shouldNotifyOCReady(ready5), "first ready id should fire")
        XCTAssertFalse(state.shouldNotifyOCReady(ready5), "the same id should be suppressed")

        let planning = OrganizedCrime2(id: 7, name: "Planning", readyAt: now + 3600)
        XCTAssertFalse(state.shouldNotifyOCReady(planning), "a not-ready OC never fires")
        XCTAssertFalse(state.shouldNotifyOCReady(nil), "nil OC never fires")

        // Relaunch on the same store: id 5 stays deduped; a new OC id re-arms.
        let relaunched = AppState(session: mock,
                                  connectivity: ControllableConnectivity(connected: true),
                                  defaults: defaults)
        XCTAssertFalse(relaunched.shouldNotifyOCReady(ready5), "dedup persists across restart")
        let ready6 = OrganizedCrime2(id: 6, name: "New OC", readyAt: now - 10)
        XCTAssertTrue(relaunched.shouldNotifyOCReady(ready6), "a new OC id re-arms")
    }
}

/// Holds each request until the test completes it. A cancelled request can therefore
/// finish after its replacement started, reproducing issue #71 deterministically.
private final class ControlledHTTPErrorUserSnapshotService: UserSnapshotServicing, @unchecked Sendable {
    typealias LoadContinuation = CheckedContinuation<UserHTTPResponse, Error>

    private let lock = NSLock()
    private var loadIndex = 0
    private var continuations: [Int: LoadContinuation] = [:]
    var onLoad: (@Sendable (Int) -> Void)?

    func load(_ url: URL) async throws -> UserHTTPResponse {
        let index = lock.withLock {
            let index = loadIndex
            loadIndex += 1
            return index
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                continuations[index] = continuation
            }
            onLoad?(index)
        }
    }

    func complete(index: Int) {
        let continuation = lock.withLock { continuations.removeValue(forKey: index) }
        guard let continuation else {
            XCTFail("No pending load at index \(index)")
            return
        }
        continuation.resume(returning: UserHTTPResponse(data: Data(), statusCode: 503))
    }

    func fail(index: Int, error: Error) {
        let continuation = lock.withLock { continuations.removeValue(forKey: index) }
        guard let continuation else {
            XCTFail("No pending load at index \(index)")
            return
        }
        continuation.resume(throwing: error)
    }

    func drain() {
        let pending = lock.withLock {
            let pending = continuations.values
            continuations.removeAll()
            return Array(pending)
        }
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
    }

    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> UserServiceResult<UserSnapshotPayload> {
        .malformed(responseBytes: data.count)
    }

    func loadActivity(_ url: URL) async throws -> UserServiceResult<UserActivityPayload> {
        .malformed(responseBytes: 0)
    }

    func loadUserV2(_ url: URL) async throws -> UserServiceResult<UserV2Payload> {
        .malformed(responseBytes: 0)
    }

    func loadVirus(_ url: URL) async throws -> UserServiceResult<VirusProgramming?> {
        .success(nil, responseBytes: 0)
    }
}

/// Simulates URLSession work that completes even after its caller is cancelled. This
/// proves account isolation does not rely on cooperative task cancellation.
private final class NonCooperativeDelayedNetworkSession: NetworkSession, @unchecked Sendable {
    private let responseData: Data
    private let delay: TimeInterval

    init(json: [String: Any], delay: TimeInterval) throws {
        self.responseData = try JSONSerialization.data(withJSONObject: json)
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.torn.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                continuation.resume(returning: (self.responseData, response))
            }
        }
    }
}

/// Returns a successful point-in-time poll while applying Torn code 14 only to the two
/// row-based fan-out endpoints. A code-14 envelope on `user.fast` is not representative:
/// that endpoint requests no row selections and now correctly stops fan-out on any main
/// error rather than issuing more requests into a limited API.
private final class DailyRowLimitNetworkSession: NetworkSession, @unchecked Sendable {
    private let userFastData: Data
    private let factionBasicData: Data
    private let userV2Data: Data
    private let rankedWarsData: Data
    private let dailyLimitData: Data

    init() throws {
        userFastData = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        factionBasicData = try TornAPIFixtures.toData([
            "name": "Test Faction",
            "ID": 123,
            "respect": 456,
            "chain": ["current": 0, "max": 0, "timeout": 0, "cooldown": 0]
        ])
        userV2Data = try TornAPIFixtures.toData(TornAPIFixtures.userV2Response())
        rankedWarsData = try TornAPIFixtures.toData(["rankedwars": []])
        dailyLimitData = try TornAPIFixtures.toData([
            "error": ["code": 14, "error": "Daily read limit reached"]
        ])
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://api.torn.com")!
        let selections = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "selections" })?
            .value ?? ""

        let data: Data
        if url.path.contains("/v2/faction/news") {
            data = dailyLimitData
        } else if url.path.contains("/v2/faction/rankedwars") {
            data = rankedWarsData
        } else if url.path == "/v2/user" {
            data = userV2Data
        } else if url.pathComponents.contains("faction") {
            data = factionBasicData
        } else if selections.contains("events") {
            data = dailyLimitData
        } else {
            data = userFastData
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

/// Returns the correct successful schema for every endpoint in the poll fan-out.
/// A single generic user payload is intentionally insufficient now that each extracted
/// service owns strict semantic decoding for its endpoint.
private final class FanOutSuccessNetworkSession: NetworkSession, @unchecked Sendable {
    private let userData: Data
    private let factionBasicData: Data
    private let userV2Data: Data
    private let rankedWarsData: Data
    private let factionNewsData: Data

    init() throws {
        userData = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        factionBasicData = try TornAPIFixtures.toData([
            "name": "Test Faction",
            "ID": 123,
            "respect": 456,
            "chain": ["current": 0, "max": 0, "timeout": 0, "cooldown": 0],
        ])
        userV2Data = try TornAPIFixtures.toData(TornAPIFixtures.userV2Response())
        rankedWarsData = try TornAPIFixtures.toData(TornAPIFixtures.rankedWarsResponse())
        factionNewsData = try TornAPIFixtures.toData(TornAPIFixtures.factionNewsResponse)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://api.torn.com")!
        let data: Data
        if url.path.contains("/v2/faction/news") {
            data = factionNewsData
        } else if url.path.contains("/v2/faction/rankedwars") {
            data = rankedWarsData
        } else if url.path == "/v2/user" {
            data = userV2Data
        } else if url.pathComponents.contains("faction") {
            data = factionBasicData
        } else {
            data = userData
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Menu-bar accessibility (audit 2026-08-01, A-01)
//
// The menu-bar label is the only always-visible surface of this app. `MenuBarDisplay`
// used to carry presentation glyphs only (flag emoji, cooldown emoji), which left no
// name for VoiceOver to speak. These tests pin the spoken form of every case.

final class MenuBarAccessibilityTests: XCTestCase {

    func testSpokenDurationDropsEmptyLeadingComponents() {
        XCTAssertEqual(MenuBarDisplay.spokenDuration(0), "0 seconds")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(1), "1 second")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(45), "45 seconds")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(60), "1 minute")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(155), "2 minutes 35 seconds")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(3600), "1 hour")
        XCTAssertEqual(MenuBarDisplay.spokenDuration(3840), "1 hour 4 minutes")
    }

    func testNegativeDurationDoesNotProduceNegativeSpeech() {
        XCTAssertEqual(MenuBarDisplay.spokenDuration(-30), "0 seconds")
    }

    func testEveryCaseSpeaksItsMeaningNotItsGlyph() {
        let cases: [MenuBarDisplay] = [
            .traveling(destination: "Japan", seconds: 155),
            .hospitalAbroad(destination: "Mexico", seconds: 600),
            .hospitalAtHome(seconds: 300),
            .jail(seconds: 90),
            .cooldown(kind: .medical, seconds: 60),
            .fallbackIcon
        ]

        for display in cases {
            let spoken = display.accessibilityDescription
            XCTAssertFalse(spoken.isEmpty, "\(display) has no spoken form")
            // No case may fall back to reading out a bare glyph.
            for glyph in ["🇯🇵", "🇲🇽", "✈️", "🏥", "🚓", "💊", "🧪", "🩹"] {
                XCTAssertFalse(spoken.contains(glyph),
                               "\(display) leaks glyph \(glyph) into speech: \(spoken)")
            }
        }
    }

    func testSpokenFormsNameTheDestinationAndCooldownKind() {
        XCTAssertEqual(MenuBarDisplay.traveling(destination: "Japan", seconds: 155)
            .accessibilityDescription,
                       "Traveling to Japan, arriving in 2 minutes 35 seconds")
        XCTAssertEqual(MenuBarDisplay.hospitalAbroad(destination: "Mexico", seconds: 600)
            .accessibilityDescription,
                       "In hospital in Mexico, 10 minutes remaining")
        XCTAssertEqual(MenuBarDisplay.cooldown(kind: .drug, seconds: 60)
            .accessibilityDescription,
                       "Drug cooldown, 1 minute remaining")
    }

    func testUnknownDestinationStillSpeaksSomethingUseful() {
        let spoken = MenuBarDisplay.traveling(destination: nil, seconds: 30)
            .accessibilityDescription
        XCTAssertEqual(spoken, "Traveling, arriving in 30 seconds")
        XCTAssertFalse(spoken.contains("Unknown"))
        XCTAssertFalse(spoken.contains("nil"))
    }
}

// MARK: - Browser open policy (audit 2026-08-01, S-01)
//
// `BrowserManager.open` used to fall through to `NSWorkspace.shared.open` for every
// non-http scheme, so a remotely-supplied string (GitHub release `html_url`) could
// reach an arbitrary registered URL handler. Only web URLs may leave this app.

final class BrowserManagerPolicyTests: XCTestCase {

    func testAcceptsOnlyWebURLs() {
        XCTAssertTrue(BrowserManager.isWebURL(URL(string: "https://www.torn.com/")!))
        XCTAssertTrue(BrowserManager.isWebURL(URL(string: "http://example.com/x?y=1")!))
        XCTAssertTrue(BrowserManager.isWebURL(URL(string: "HTTPS://WWW.TORN.COM/")!))
    }

    func testRejectsNonWebSchemes() {
        let hostile = [
            "file:///Applications/Calculator.app",
            "ssh://user@host",
            "ftp://example.com/x",
            "x-apple-helpbook://blah",
            "javascript:alert(1)",
            "mailto:someone@example.com",
            "custom-scheme://do-something"
        ]
        for raw in hostile {
            guard let url = URL(string: raw) else { continue }
            XCTAssertFalse(BrowserManager.isWebURL(url), "\(raw) must not be openable")
        }
    }

    func testRejectsWebSchemeWithoutHost() {
        XCTAssertFalse(BrowserManager.isWebURL(URL(string: "https://")!))
        XCTAssertFalse(BrowserManager.isWebURL(URL(string: "http:///path")!))
    }
}

// MARK: - Chain alert source of truth (audit 2026-08-01, C-01)
//
// The chain-expiring alert, the Next Action chain entry and the Status chain card all
// read `data?.chain` — the *user* snapshot. Torn's v1 `user` endpoint has no `chain`
// selection and `user.fast` never asked for one, so that field was permanently nil in
// production and all three surfaces were dead. The DEBUG UI fixture invented the key,
// which is why every test stayed green. These tests pin the real wiring.

@MainActor
final class ChainSourceTests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(session: MockNetworkSession(),
                 connectivity: ControllableConnectivity(connected: true),
                 defaults: .createMockDefaults())
    }

    func testUserFastEndpointDoesNotRequestChain() throws {
        let userFast = try XCTUnwrap(TornEndpointRegistry.all.first { $0.id == "user.fast" })
        XCTAssertFalse(userFast.selections.contains("chain"),
                       "Torn's v1 user endpoint has no chain selection — the alert must not depend on it")
        let factionBasic = try XCTUnwrap(TornEndpointRegistry.all.first { $0.id == "faction.basic" })
        XCTAssertTrue(factionBasic.selections.contains("chain"),
                      "chain is faction data — this is the endpoint that carries it")
    }

    func testLiveChainIsNilUntilFactionDataArrives() {
        let app = makeAppState()
        XCTAssertNil(app.liveChain, "no faction payload yet — nothing to report")
    }

    func testLiveChainMirrorsFactionPayload() throws {
        let app = makeAppState()
        let timeout = Int(Date().timeIntervalSince1970) + 30
        app.factionService.publishBasic(
            FactionData(name: "Test", factionId: 1, respect: 10,
                        chain: FactionChain(current: 25, max: 100, timeout: timeout, cooldown: 0))
        )

        let chain = try XCTUnwrap(app.liveChain, "faction chain must surface as the live chain")
        XCTAssertEqual(chain.current, 25)
        XCTAssertEqual(chain.maximum, 100)
        XCTAssertEqual(chain.timeout, timeout, "timeout is an absolute Unix timestamp on both models")
        XCTAssertTrue(chain.isActive)
        XCTAssertGreaterThan(chain.timeoutRemaining, 0)
    }

    func testChainAlertFiresFromFactionDataInsideDangerWindow() {
        let app = makeAppState()
        let soon = Int(Date().timeIntervalSince1970) + 30   // < chainWarningThreshold (60)
        app.factionService.publishBasic(
            FactionData(chain: FactionChain(current: 25, max: 100, timeout: soon, cooldown: 0))
        )

        XCTAssertTrue(app.chainExpiringShouldFire(app.liveChain),
                      "a chain sourced from faction data must arm the alert")
        XCTAssertFalse(app.chainExpiringShouldFire(app.liveChain),
                       "the persistent edge latch must collapse repeats on later polls")
    }

    func testChainAlertStaysSilentOutsideDangerWindow() {
        let app = makeAppState()
        let far = Int(Date().timeIntervalSince1970) + 600
        app.factionService.publishBasic(
            FactionData(chain: FactionChain(current: 25, max: 100, timeout: far, cooldown: 0))
        )
        XCTAssertFalse(app.chainExpiringShouldFire(app.liveChain))
    }

    func testInactiveChainNeverFires() {
        let app = makeAppState()
        app.factionService.publishBasic(
            FactionData(chain: FactionChain(current: 0, max: 100, timeout: 0, cooldown: 0))
        )
        let chain = app.liveChain
        XCTAssertEqual(chain?.isActive, false, "current == 0 is not an active chain")
        XCTAssertFalse(app.chainExpiringShouldFire(chain))
    }

    func testNextActionTimelineTakesChainFromFactionData() {
        let app = makeAppState()
        let timeout = Int(Date().timeIntervalSince1970) + 300
        app.factionService.publishBasic(
            FactionData(chain: FactionChain(current: 25, max: 100, timeout: timeout, cooldown: 0))
        )
        let snapshot = app.makeNextActionSnapshot()
        XCTAssertEqual(snapshot.chainTimeoutAt, timeout,
                       "the Next Action timeline must see the faction-sourced chain")
    }
}
