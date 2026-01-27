import XCTest
@testable import MacTorn

@MainActor
final class AppStateFeedbackTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        UserDefaults.standard.removeObject(forKey: "appFeedbackState")
        appState = AppState(session: mockSession)
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        UserDefaults.standard.removeObject(forKey: "appFeedbackState")
        try await super.tearDown()
    }

    // MARK: - First Launch

    func testFirstLaunch_createsFeedbackState() {
        XCTAssertNotNil(appState.feedbackState)
        XCTAssertFalse(appState.feedbackState!.hasResponded)
        XCTAssertEqual(appState.feedbackState!.dismissCount, 0)
        XCTAssertNil(appState.feedbackState!.lastDismissedDate)
    }

    // MARK: - Threshold Logic

    func testBeforeOneHour_promptDoesNotShow() {
        // firstLaunchDate is just now, so less than 1 hour has elapsed
        appState.checkFeedbackPrompt()
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    func testAfterOneHour_promptShows() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-3601)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertTrue(appState.showFeedbackPrompt)
    }

    func testAfterDismissOnce_needsOneWeek() {
        // Set first launch to 2 hours ago, dismiss once
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-2 * 3600)
        appState.feedbackState?.dismissCount = 1
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-600) // 10 min ago (past cooldown)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        // 2 hours < 1 week, so should not show
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    func testAfterDismissOnce_afterOneWeek_promptShows() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-8 * 86400) // 8 days ago
        appState.feedbackState?.dismissCount = 1
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-600)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertTrue(appState.showFeedbackPrompt)
    }

    func testAfterDismissTwice_needsOneMonth() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-14 * 86400) // 14 days ago
        appState.feedbackState?.dismissCount = 2
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-600)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        // 14 days < 30 days, so should not show
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    func testAfterDismissTwice_afterOneMonth_promptShows() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-31 * 86400) // 31 days ago
        appState.feedbackState?.dismissCount = 2
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-600)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertTrue(appState.showFeedbackPrompt)
    }

    func testAfterDismissThreeTimes_neverShows() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-365 * 86400) // 1 year ago
        appState.feedbackState?.dismissCount = 3
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    // MARK: - Responses

    func testPositiveResponse_setsHasRespondedAndHidesPrompt() {
        appState.showFeedbackPrompt = true
        appState.feedbackRespondedPositive()

        XCTAssertTrue(appState.feedbackState!.hasResponded)
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    func testNegativeResponse_setsHasRespondedAndHidesPrompt() {
        appState.showFeedbackPrompt = true
        appState.feedbackRespondedNegative()

        XCTAssertTrue(appState.feedbackState!.hasResponded)
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    // MARK: - Dismiss

    func testDismiss_incrementsDismissCount() {
        XCTAssertEqual(appState.feedbackState!.dismissCount, 0)

        appState.feedbackDismissed()

        XCTAssertEqual(appState.feedbackState!.dismissCount, 1)
        XCTAssertFalse(appState.showFeedbackPrompt)
        XCTAssertNotNil(appState.feedbackState!.lastDismissedDate)
    }

    // MARK: - After Responded

    func testAfterResponded_neverShowsAgain() {
        appState.feedbackState?.hasResponded = true
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-365 * 86400)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    // MARK: - Persistence

    func testStatePersistsAcrossAppStateInstances() {
        // Set a specific first launch date and dismiss once
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-86400)
        appState.feedbackState?.dismissCount = 1
        appState.saveFeedbackState()

        // Create a new AppState instance (simulates app restart)
        let newAppState = AppState(session: mockSession)

        XCTAssertNotNil(newAppState.feedbackState)
        XCTAssertEqual(newAppState.feedbackState!.dismissCount, 1)
        // firstLaunchDate should be approximately 1 day ago
        let elapsed = Date().timeIntervalSince(newAppState.feedbackState!.firstLaunchDate)
        XCTAssertTrue(elapsed > 86300 && elapsed < 86500)

        newAppState.stopPolling()
    }

    // MARK: - Cooldown

    func testFiveMinuteCooldown_preventsImmediateReshow() {
        // Set eligible threshold (1 hour elapsed, dismissCount 0)
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-3601)
        // But dismissed just 2 minutes ago
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-120)
        // dismissCount is still 0 since we're simulating the state manually
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertFalse(appState.showFeedbackPrompt)
    }

    func testAfterCooldown_promptCanShow() {
        appState.feedbackState?.firstLaunchDate = Date().addingTimeInterval(-3601)
        // Dismissed 6 minutes ago (past the 5-minute cooldown)
        appState.feedbackState?.lastDismissedDate = Date().addingTimeInterval(-360)
        appState.saveFeedbackState()

        appState.checkFeedbackPrompt()
        XCTAssertTrue(appState.showFeedbackPrompt)
    }
}
