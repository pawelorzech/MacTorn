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
    /// Wait for element to appear within the given timeout
    func waitForAppearance(timeout: TimeInterval = 5) -> Bool {
        return self.waitForExistence(timeout: timeout)
    }

    /// Tap if element exists
    func tapIfExists() {
        if self.exists {
            self.tap()
        }
    }
}
