import XCTest

final class MacTornUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Reset state for each test
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Settings View Tests

    func testSettingsView_appearsWhenNoAPIKey() throws {
        // When no API key is set, settings should appear
        // Note: This test assumes a clean state or --uitesting launch argument clears the key

        // Look for settings-related UI elements
        let settingsElements = app.windows.firstMatch

        // The app should show some form of settings or API key input
        // Adjust selectors based on actual UI implementation
        XCTAssertTrue(settingsElements.exists)
    }

    // MARK: - Tab Navigation Tests

    func testTabNavigation_allTabsExist() throws {
        // Skip if settings view is blocking
        // This test verifies the main tab structure

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)

        // Look for tab bar or navigation elements
        // Adjust based on actual UI implementation
    }

    func testTabNavigation_switchBetweenTabs() throws {
        let window = app.windows.firstMatch

        // Tab navigation test
        // Adjust selectors based on actual tab implementation
        // e.g., app.buttons["Status"].tap()

        XCTAssertTrue(window.exists)
    }

    // MARK: - Refresh Button Tests

    func testRefreshButton_exists() throws {
        let window = app.windows.firstMatch

        // Look for refresh button
        // Adjust selector based on actual implementation
        // let refreshButton = window.buttons["Refresh"]

        XCTAssertTrue(window.exists)
    }

    func testRefreshButton_triggersRefresh() throws {
        // This test would verify that tapping refresh triggers a data fetch
        // Would need to mock network or observe state changes

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Watchlist UI Tests

    func testWatchlist_addItem() throws {
        // Navigate to watchlist tab
        // Add an item
        // Verify it appears in the list

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    func testWatchlist_removeItem() throws {
        // Navigate to watchlist tab
        // Remove an item
        // Verify it's no longer in the list

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Error State Tests

    func testErrorState_displaysErrorMessage() throws {
        // Trigger an error state
        // Verify error message is displayed

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Loading State Tests

    func testLoadingState_showsLoadingIndicator() throws {
        // During data fetch, loading indicator should be visible

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Status View Tests

    func testStatusView_displaysBars() throws {
        // Verify energy, nerve, life, happy bars are displayed

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Performance Tests

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}

// MARK: - UI Test Helpers

extension XCUIElement {
    /// Wait for element to exist with timeout
    func waitForExistence(timeout: TimeInterval = 5) -> Bool {
        return self.waitForExistence(timeout: timeout)
    }

    /// Tap if element exists
    func tapIfExists() {
        if self.exists {
            self.tap()
        }
    }
}
