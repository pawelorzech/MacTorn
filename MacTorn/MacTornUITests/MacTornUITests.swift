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
                        online: Bool = true,
                        accessibilityDisplayOptions: Bool = false,
                        windowHeight: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--uitesting", "-uitest-fixture", fixture,
                    "-uitest-online", online ? "1" : "0"]
        if let apiKey { args += ["-uitest-apikey", apiKey] }
        if let windowHeight {
            args += ["-uitest-window-height", String(windowHeight)]
        }
        if accessibilityDisplayOptions {
            // These are process-local harness inputs. They do not mutate the user's
            // global accessibility preferences.
            args += [
                "-reduceTransparency", "YES",
                "-AppleReduceMotion", "YES",
                "-AppleIncreaseContrast", "YES",
            ]
        }
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
        XCTAssertFalse(app.buttons["uitest.group.Now"].exists,
                       "Navigation groups must not be shown before a key is entered")
    }

    // MARK: - Navigation

    /// Every module stays reachable in at most two actions: group, then module.
    func testGroupedNavigationSwitchesContentAndPreservesSelectedState() throws {
        let app = launch(fixture: "full", apiKey: "sample-full-user")
        _ = window(app)

        let nowGroup = app.buttons["uitest.group.Now"]
        XCTAssertTrue(nowGroup.waitForExistence(timeout: 10), "Now group should exist")
        XCTAssertTrue(nowGroup.isSelected, "Now should be the selected group by default")

        let statusTab = app.buttons["uitest.tab.Status"]
        XCTAssertTrue(statusTab.waitForExistence(timeout: 10), "Status tab should exist")
        XCTAssertTrue(statusTab.isSelected, "Status should be selected by default")

        // Status content is the default.
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Status"].waitForExistence(timeout: 10),
                      "Status content should be shown by default")

        // One action selects Watch and its default module, Watchlist.
        let watchGroup = app.buttons["uitest.group.Watch"]
        watchGroup.click()
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Watchlist"].waitForExistence(timeout: 10),
                      "Watchlist should be the Watch group's default module")
        XCTAssertTrue(watchGroup.isSelected, "Watch group should report selected in AX")
        XCTAssertTrue(app.buttons["uitest.tab.Watchlist"].isSelected,
                      "Watchlist should report selected in AX")

        // A second action reaches the other module in the active group.
        app.buttons["uitest.tab.Forums"].click()
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Forums"].waitForExistence(timeout: 10),
                      "Forums content should be shown from the Watch module picker")
        XCTAssertTrue(app.buttons["uitest.tab.Forums"].isSelected,
                      "Forums should report selected in AX")

        // Account is also one action away and defaults to Money.
        app.buttons["uitest.group.Account"].click()
        XCTAssertTrue(app.descendants(matching: .any)["uitest.tabContent.Money"].waitForExistence(timeout: 10),
                      "Money should be the Account group's default module")
        XCTAssertTrue(app.buttons["uitest.tab.Money"].isSelected,
                      "Money should report selected in AX")
    }

    /// The fixed menu-bar surface remains 320 pt wide and neither navigation row clips
    /// when reduced transparency and increased contrast are requested.
    func testGroupedNavigationFits320WithAccessibilityDisplayOptions() throws {
        let app = launch(
            fixture: "full",
            apiKey: "sample-accessibility-user",
            accessibilityDisplayOptions: true
        )
        let win = window(app)
        XCTAssertEqual(win.frame.width, 320, accuracy: 3,
                       "The compact UI-test surface should remain 320 pt wide")

        let groupIDs = ["Now", "Account", "Watch"]
        let groups = groupIDs.map { app.buttons["uitest.group.\($0)"] }
        for group in groups {
            XCTAssertTrue(group.waitForExistence(timeout: 10))
            assertContained(group, in: win)
        }
        assertDoNotOverlap(groups)

        let nowModules = ["Status", "Travel", "Attacks"].map {
            app.buttons["uitest.tab.\($0)"]
        }
        for module in nowModules {
            XCTAssertTrue(module.waitForExistence(timeout: 10))
            XCTAssertTrue(module.isHittable)
            assertContained(module, in: win)
        }
        assertDoNotOverlap(nowModules)
    }

    /// Pins the AX contract for all seven modules and Settings. Audio order and keyboard
    /// focus still require the manual system-level matrix documented in the QA report.
    func testAllModulesAndSettingsExposeStableAXContract() throws {
        let app = launch(fixture: "full", apiKey: "sample-ax-user", windowHeight: 1000)
        _ = window(app)

        let groups: [(name: String, modules: [String])] = [
            ("Now", ["Status", "Travel", "Attacks"]),
            ("Account", ["Money", "Faction"]),
            ("Watch", ["Watchlist", "Forums"]),
        ]

        for group in groups {
            let groupButton = app.buttons["uitest.group.\(group.name)"]
            XCTAssertTrue(groupButton.waitForExistence(timeout: 10))
            XCTAssertEqual(groupButton.label, "\(group.name) group")
            groupButton.click()
            assertBecomesSelected(groupButton)

            for module in group.modules {
                let moduleButton = app.buttons["uitest.tab.\(module)"]
                XCTAssertTrue(moduleButton.waitForExistence(timeout: 10))
                XCTAssertEqual(moduleButton.label, module)
                moduleButton.click()
                assertBecomesSelected(moduleButton)
                XCTAssertTrue(
                    app.descendants(matching: .any)["uitest.tabContent.\(module)"]
                        .waitForExistence(timeout: 10),
                    "\(module) content should be reachable through its AX identifier"
                )
            }
        }

        // Return to Status and pin the progress-bar elements exposed by XCUI.
        // On macOS, SwiftUI's accessibilityValue is available to assistive
        // technologies but is omitted from XCUI's snapshot for these `Other`
        // elements; spoken values remain part of the manual VoiceOver matrix.
        app.buttons["uitest.group.Now"].click()
        app.buttons["uitest.tab.Status"].click()
        let refresh = app.buttons["Refresh Torn data"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        XCTAssertEqual(refresh.label, "Refresh Torn data")

        let expectedProgressLabels = ["Energy", "Nerve", "Happy", "Life"]
        let statusScroll = app.scrollViews["uitest.tabContent.Status"]
        XCTAssertTrue(statusScroll.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(
            statusScroll.frame.height,
            481,
            "Status should stay a compact, bounded surface"
        )
        let nextAction = app.descendants(matching: .any)["uitest.nextAction"]
        XCTAssertTrue(nextAction.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(
            nextAction.frame.height,
            52,
            "Next Action should remain a single compact row"
        )
        for label in expectedProgressLabels {
            let element = statusScroll.otherElements[label]
            XCTAssertTrue(
                element.waitForExistence(timeout: 10),
                "\(label) progress AX element missing"
            )
            XCTAssertEqual(element.label, label)
        }

        app.buttons["uitest.openSettings"].click()
        let keyField = app.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10))
        XCTAssertEqual(keyField.label, "Torn API Key")
        XCTAssertEqual(app.buttons["uitest.saveKey"].label, "Save & Connect")
        XCTAssertEqual(app.buttons["uitest.testConnection"].label, "Test Connection")

        let settingsSections: [(id: String, title: String)] = [
            ("account", "Account"),
            ("refresh", "Refresh"),
            ("notifications", "Notifications"),
            ("privacy", "Privacy"),
            ("startup", "Startup"),
            ("diagnostics", "Diagnostics & About"),
        ]
        for section in settingsSections {
            let button = app.buttons["settings.section.\(section.id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.label, section.title)
            button.click()
            assertBecomesSelected(button)
            XCTAssertTrue(
                app.descendants(matching: .any)["uitest.settingsContent.\(section.id)"]
                    .waitForExistence(timeout: 10),
                "\(section.title) should replace the current Settings section"
            )
        }
    }

    // MARK: - Account isolation (T15 fixture preparation)

    /// A delayed, cancellation-ignoring response for synthetic account A must never
    /// overwrite or briefly reappear after switching to synthetic account B.
    func testAccountSwitchNeverFlashesStaleIdentity() throws {
        let app = launch(
            fixture: "accountSwitch",
            apiKey: "fixture-account-a",
            windowHeight: 900
        )
        _ = window(app)

        let accountA = app.staticTexts["Fixture Account A"]
        XCTAssertTrue(accountA.waitForExistence(timeout: 10), "Fixture account A should load")

        // Start the deliberately delayed second A request, then switch while it is in flight.
        app.buttons["Refresh Torn data"].click()
        app.buttons["uitest.openSettings"].click()

        let keyField = app.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10))
        keyField.click()
        keyField.typeKey("a", modifierFlags: .command)
        keyField.typeText("fixture-account-b")
        app.buttons["uitest.saveKey"].click()

        // During the new account's initial load ContentView disables interaction. Wait
        // for the fixture B response, then return to Status.
        let back = app.buttons["uitest.openSettings"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: back)
        waitForExpectations(timeout: 10)
        back.click()

        let accountB = app.staticTexts["Fixture Account B"]
        XCTAssertTrue(accountB.waitForExistence(timeout: 10), "Fixture account B should load")

        // The non-cancellable A response arrives after 3 seconds. Sample beyond that
        // boundary so even a short stale-identity flash fails the test.
        let observationDeadline = Date().addingTimeInterval(4)
        while Date() < observationDeadline {
            XCTAssertFalse(accountA.exists, "Stale fixture account A flashed after switching to B")
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(accountB.exists, "Fixture account B should remain visible")
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
        let app = launch(
            fixture: "full",
            apiKey: "sample-connection-user",
            windowHeight: 900
        )
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

    private func assertContained(_ element: XCUIElement,
                                 in window: XCUIElement,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let tolerance: CGFloat = 1
        XCTAssertGreaterThanOrEqual(element.frame.minX, window.frame.minX - tolerance,
                                    file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.maxX + tolerance,
                                 file: file, line: line)
    }

    private func assertDoNotOverlap(_ elements: [XCUIElement],
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        let ordered = elements.sorted { $0.frame.minX < $1.frame.minX }
        for (left, right) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX,
                                     "Navigation controls should not overlap",
                                     file: file, line: line)
        }
    }

    private func assertBecomesSelected(_ element: XCUIElement,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: 3),
            .completed,
            "\(element.identifier) should report selected in AX",
            file: file,
            line: line
        )
    }
}
