import XCTest

/// Deterministic UI tests (Etap G / ISC-20).
///
/// Every launch is hermetic: the app runs under `--uitesting`, which wires it from
/// fixtures + test doubles (see `UITestSupport.swift`) — no real network, Keychain, or
/// notifications. The MenuBarExtra content is surfaced in a real window the runner drives.
final class MacTornUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch helper

    /// Launches the app under the harness with a chosen fixture and optional seeded key.
    private func launch(fixture: String, apiKey: String? = nil,
                        online: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--uitesting", "-uitest-fixture", fixture,
                    "-uitest-online", online ? "1" : "0"]
        if let apiKey { args += ["-uitest-apikey", apiKey] }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The single UI-test window. Waits for it so tests don't race the launch.
    private func window(_ app: XCUIApplication) -> XCUIElement {
        let win = app.windows.firstMatch
        XCTAssertTrue(win.waitForExistence(timeout: 15), "UI-test window never appeared")
        return win
    }

    // MARK: - Onboarding

    /// With no API key, the app must present onboarding (the key entry), not the tabs.
    func testOnboardingWithoutKeyShowsKeyEntry() throws {
        let app = launch(fixture: "empty", apiKey: nil)
        _ = window(app)

        let keyField = app.descendants(matching: .any)["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10),
                      "API-key field should be shown when no key is configured")

        // The tab bar belongs to the signed-in UI and must be absent during onboarding.
        XCTAssertFalse(app.buttons["uitest.tab.Status"].exists,
                       "Tabs must not be shown before a key is entered")
    }

    // MARK: - Navigation

    /// With a key + a healthy fixture, tapping a tab switches the visible content.
    func testTabNavigationSwitchesContent() throws {
        let app = launch(fixture: "full", apiKey: "sample-full-user")
        _ = window(app)

        let statusTab = app.buttons["uitest.tab.Status"]
        XCTAssertTrue(statusTab.waitForExistence(timeout: 10), "Status tab should exist")

        // Status content is the default.
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Status"].waitForExistence(timeout: 10),
                      "Status content should be shown by default")

        // Switch to Watchlist and assert the content element tracks the new tab.
        app.buttons["uitest.tab.Watchlist"].click()
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Watchlist"].waitForExistence(timeout: 10),
                      "Watchlist content should be shown after tapping the Watchlist tab")

        // And back to Money.
        app.buttons["uitest.tab.Money"].click()
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Money"].waitForExistence(timeout: 10),
                      "Money content should be shown after tapping the Money tab")
    }

    // MARK: - Error surfacing

    /// A permanent key error (Torn code 2) must surface an error in the UI, not silently
    /// leave the user on a blank screen.
    func testInvalidKeySurfacesError() throws {
        let app = launch(fixture: "invalidKey", apiKey: "sample-bad-user")
        _ = window(app)

        let error = app.descendants(matching: .any)["uitest.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15),
                      "An invalid key should surface a visible error message")
    }

    // MARK: - Key validation (Etap C)

    /// "Test Connection" validates the key against /key/info and reports what it unlocks.
    func testTestConnectionReportsAccess() throws {
        let app = launch(fixture: "full", apiKey: "sample-connection-user")
        _ = window(app)

        // Open Settings from the signed-in footer, then run Test Connection.
        let settings = app.buttons["uitest.openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings button should exist")
        settings.click()

        let testButton = app.buttons["uitest.testConnection"]
        XCTAssertTrue(testButton.waitForExistence(timeout: 10), "Test Connection button should exist")
        testButton.click()

        XCTAssertTrue(app.descendants(matching: .any)["uitest.keyValidationSuccess"].waitForExistence(timeout: 15),
                      "A valid key should report its access level after Test Connection")
    }

    /// During onboarding, Test Connection validates the typed key WITHOUT saving it, so the
    /// result stays visible on the Settings screen instead of flipping to the tab UI.
    func testOnboardingTestConnectionKeepsSettingsVisible() throws {
        let app = launch(fixture: "full", apiKey: nil)
        _ = window(app)

        let keyField = app.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10), "Key field should be shown at onboarding")
        keyField.click()
        keyField.typeText("sample-typed-value")

        app.buttons["uitest.testConnection"].click()

        XCTAssertTrue(app.descendants(matching: .any)["uitest.keyValidationSuccess"].waitForExistence(timeout: 15),
                      "Result should appear after Test Connection")
        XCTAssertTrue(keyField.exists,
                      "Test Connection must not save the key / leave the onboarding screen")
        XCTAssertFalse(app.buttons["uitest.tab.Status"].exists,
                       "The signed-in tab UI must not appear from a mere Test Connection")
    }
}
