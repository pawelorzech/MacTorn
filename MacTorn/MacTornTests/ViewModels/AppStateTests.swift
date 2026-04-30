import XCTest
@testable import MacTorn

@MainActor
final class AppStateTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession)
        // Clear any persisted data
        UserDefaults.standard.removeObject(forKey: "apiKey")
        UserDefaults.standard.removeObject(forKey: "watchlist")
        UserDefaults.standard.removeObject(forKey: "notificationRules")
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        try await super.tearDown()
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

    /// Falls back to local `Date()` if the API response doesn't include a top-level
    /// `timestamp` (older API versions / partial responses). Don't crash, don't drop
    /// the cooldowns — just lose the clock-skew correction.
    func testFetchData_cooldownEnds_fallbackToLocalNow_whenServerTimestampMissing() async throws {
        appState.apiKey = "valid_key"
        var json = TornAPIFixtures.responseWithCooldowns(
            timestamp: 0,
            drug: 0,
            booster: 600,
            medical: 0
        )
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

        XCTAssertEqual(appState.errorMsg, "API Error: Incorrect Key")
        XCTAssertNil(appState.data)
    }

    func testFetchData_tornAPIRateLimit() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIError(code: 5, message: "Too many requests")

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(appState.errorMsg, "API Error: Too many requests")
    }

    // MARK: - Network Error Tests

    func testFetchData_networkError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setNetworkError(MockNetworkError.connectionFailed)

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(appState.errorMsg)
        XCTAssertTrue(appState.errorMsg?.contains("Network error") ?? false)
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
        UserDefaults.standard.removeObject(forKey: "notificationRules")

        let newAppState = AppState(session: mockSession)

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
}
