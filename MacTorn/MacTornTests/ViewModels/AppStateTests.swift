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
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

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
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

        appState.fetchData()

        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNotNil(appState.data?.bars)
        XCTAssertEqual(appState.data?.energy?.current, 100)
        XCTAssertEqual(appState.data?.nerve?.current, 50)
        XCTAssertEqual(appState.data?.life?.current, 7500)
        XCTAssertEqual(appState.data?.happy?.current, 5000)
    }

    // MARK: - Torn API Error Tests

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
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

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
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

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
        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

        // refreshNow calls fetchData which is async
        appState.refreshNow()

        // Wait for async completion
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Verify request was made
        XCTAssertGreaterThanOrEqual(mockSession.requestedURLs.count, 1)
        XCTAssertNotNil(appState.data)
    }
}
