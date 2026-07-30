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
        app.refreshNow()   // fetchData records "user.fast" synchronously before spawning its task
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
        conn.restore()   // down→up edge → refreshNow → fetchData records a request
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

    func testFetchData_invalidAPIKey_HTTP403() async throws {
        appState.apiKey = "invalid_key"
        mockSession.setHTTPError(statusCode: 403)

        appState.fetchData()

        // Wait for async completion
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "Invalid API Key")
        XCTAssertNil(appState.data)
    }

    func testFetchData_invalidAPIKey_HTTP404() async throws {
        appState.apiKey = "invalid_key"
        mockSession.setHTTPError(statusCode: 404)

        appState.fetchData()

        // Wait for async completion
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "Invalid API Key")
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

        guard case .traveling(let flag, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .traveling, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(flag, "🇯🇵")
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

        guard case .hospitalAbroad(let flag, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .hospitalAbroad, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(flag, "🇲🇽")
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

        guard case .cooldown(let emoji, let seconds) = appState.menuBarDisplay else {
            return XCTFail("Expected .cooldown, got \(appState.menuBarDisplay)")
        }
        XCTAssertEqual(emoji, "🩹") // medical
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
        userV2Data = try TornAPIFixtures.toData([:])
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
        userV2Data = try TornAPIFixtures.toData([:])
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
