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
        let win = app.windows["MacTorn UI Tests"]
        XCTAssertTrue(win.waitForExistence(timeout: 15), "UI-test window never appeared")
        return win
    }

    // MARK: - Onboarding

    /// With no API key, the app must present onboarding (the key entry), not the tabs.
    func testOnboardingWithoutKeyShowsKeyEntry() throws {
        let app = launch(fixture: "empty", apiKey: nil)
        let win = window(app)

        let keyField = win.descendants(matching: .any)["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10),
                      "API-key field should be shown when no key is configured")

        // The tab bar belongs to the signed-in UI and must be absent during onboarding.
        XCTAssertFalse(win.buttons["uitest.tab.Status"].exists,
                       "Tabs must not be shown before a key is entered")
        XCTAssertFalse(win.buttons["uitest.group.Now"].exists,
                       "Navigation groups must not be shown before a key is entered")
    }

    // MARK: - Navigation

    /// Every module stays reachable in at most two actions: group, then module.
    func testGroupedNavigationSwitchesContentAndPreservesSelectedState() throws {
        let app = launch(fixture: "full", apiKey: "sample-full-user")
        let win = window(app)

        let nowGroup = win.buttons["uitest.group.Now"]
        XCTAssertTrue(nowGroup.waitForExistence(timeout: 10), "Now group should exist")
        XCTAssertTrue(nowGroup.isSelected, "Now should be the selected group by default")

        let statusTab = win.buttons["uitest.tab.Status"]
        XCTAssertTrue(statusTab.waitForExistence(timeout: 10), "Status tab should exist")
        XCTAssertTrue(statusTab.isSelected, "Status should be selected by default")

        // Status content is the default.
        XCTAssertTrue(win.descendants(matching: .any)["uitest.tabContent.Status"].waitForExistence(timeout: 10),
                      "Status content should be shown by default")

        // One action selects Watch and its default module, Watchlist.
        let watchGroup = win.buttons["uitest.group.Watch"]
        watchGroup.click()
        XCTAssertTrue(win.descendants(matching: .any)["uitest.tabContent.Watchlist"].waitForExistence(timeout: 10),
                      "Watchlist should be the Watch group's default module")
        XCTAssertTrue(watchGroup.isSelected, "Watch group should report selected in AX")
        XCTAssertTrue(win.buttons["uitest.tab.Watchlist"].isSelected,
                      "Watchlist should report selected in AX")

        // A second action reaches the other module in the active group.
        win.buttons["uitest.tab.Forums"].click()
        XCTAssertTrue(win.descendants(matching: .any)["uitest.tabContent.Forums"].waitForExistence(timeout: 10),
                      "Forums content should be shown from the Watch module picker")
        XCTAssertTrue(win.buttons["uitest.tab.Forums"].isSelected,
                      "Forums should report selected in AX")

        // Account is also one action away and defaults to Money.
        win.buttons["uitest.group.Account"].click()
        XCTAssertTrue(win.descendants(matching: .any)["uitest.tabContent.Money"].waitForExistence(timeout: 10),
                      "Money should be the Account group's default module")
        XCTAssertTrue(win.buttons["uitest.tab.Money"].isSelected,
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
        let groups = groupIDs.map { win.buttons["uitest.group.\($0)"] }
        for group in groups {
            XCTAssertTrue(group.waitForExistence(timeout: 10))
            assertContained(group, in: win)
        }
        assertDoNotOverlap(groups)

        let nowModules = ["Status", "Travel", "Attacks"].map {
            win.buttons["uitest.tab.\($0)"]
        }
        for module in nowModules {
            XCTAssertTrue(module.waitForExistence(timeout: 10))
            XCTAssertTrue(module.isHittable)
            assertContained(module, in: win)
        }
        assertDoNotOverlap(nowModules)
    }

    /// Financial data is split into focused Account modules, and the longest one
    /// remains scrollable without pushing the footer outside a short display.
    func testAccountModulesFitAndStocksScrollInShortWindow() throws {
        let app = launch(
            fixture: "full",
            apiKey: "sample-short-window-user",
            windowHeight: 480
        )
        let win = window(app)

        win.buttons["uitest.group.Account"].click()

        let accountModules = ["Money", "Properties", "Stocks", "Faction"].map {
            win.buttons["uitest.tab.\($0)"]
        }
        for module in accountModules {
            XCTAssertTrue(module.waitForExistence(timeout: 10))
            XCTAssertTrue(module.isHittable)
            assertContained(module, in: win)
        }
        assertDoNotOverlap(accountModules)

        XCTAssertTrue(
            win.buttons["Send Money"].isHittable,
            "Money should remain a glanceable single-screen summary"
        )

        win.buttons["uitest.tab.Stocks"].click()
        let stocksScroll = win.scrollViews["uitest.tabContent.Stocks"]
        XCTAssertTrue(stocksScroll.waitForExistence(timeout: 10))
        assertContained(stocksScroll, in: win)

        let footer = win.buttons["uitest.openSettings"]
        XCTAssertTrue(footer.isHittable, "The fixed footer should remain reachable")

        let stockMarket = win.buttons["Stock Market"]
        XCTAssertFalse(
            stockMarket.isHittable,
            "The long fixture should start with its bottom action outside the viewport"
        )
        for _ in 0..<12 where !stockMarket.isHittable {
            stocksScroll.swipeUp()
        }
        XCTAssertTrue(
            stockMarket.isHittable,
            "The bottom of a long Stocks module should be reachable by scrolling"
        )
    }

    /// Pins the AX contract for all nine modules and Settings. Audio order and keyboard
    /// focus still require the manual system-level matrix documented in the QA report.
    func testAllModulesAndSettingsExposeStableAXContract() throws {
        let app = launch(fixture: "full", apiKey: "sample-ax-user")
        let win = window(app)

        let groups: [(name: String, modules: [String])] = [
            ("Now", ["Status", "Travel", "Attacks"]),
            ("Account", ["Money", "Properties", "Stocks", "Faction"]),
            ("Watch", ["Watchlist", "Forums"]),
        ]

        for group in groups {
            let groupButton = win.buttons["uitest.group.\(group.name)"]
            XCTAssertTrue(groupButton.waitForExistence(timeout: 10))
            XCTAssertEqual(groupButton.label, "\(group.name) group")
            groupButton.click()
            assertBecomesSelected(groupButton)

            for module in group.modules {
                let moduleButton = win.buttons["uitest.tab.\(module)"]
                XCTAssertTrue(moduleButton.waitForExistence(timeout: 10))
                XCTAssertEqual(moduleButton.label, module)
                moduleButton.click()
                assertBecomesSelected(moduleButton)
                XCTAssertTrue(
                    win.descendants(matching: .any)["uitest.tabContent.\(module)"]
                        .waitForExistence(timeout: 10),
                    "\(module) content should be reachable through its AX identifier"
                )
            }
        }

        // Return to Status and pin the progress-bar elements exposed by XCUI.
        // On macOS, SwiftUI's accessibilityValue is available to assistive
        // technologies but is omitted from XCUI's snapshot for these `Other`
        // elements; spoken values remain part of the manual VoiceOver matrix.
        win.buttons["uitest.group.Now"].click()
        win.buttons["uitest.tab.Status"].click()
        let refresh = win.buttons["Refresh Torn data"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        XCTAssertEqual(refresh.label, "Refresh Torn data")

        let expectedProgressLabels = ["Energy", "Nerve", "Happy", "Life"]
        let statusScroll = win.scrollViews["uitest.tabContent.Status"]
        XCTAssertTrue(statusScroll.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(
            statusScroll.frame.height,
            481,
            "Status should stay a compact, bounded surface"
        )
        let nextAction = win.descendants(matching: .any)["uitest.nextAction"]
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

        win.buttons["uitest.openSettings"].click()
        let keyField = win.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10))
        XCTAssertEqual(keyField.label, "Torn API Key")
        XCTAssertEqual(win.buttons["uitest.saveKey"].label, "Save & Connect")
        XCTAssertEqual(win.buttons["uitest.testConnection"].label, "Test Connection")

        let settingsSections: [(id: String, title: String)] = [
            ("account", "Account"),
            ("refresh", "Refresh"),
            ("notifications", "Notifications"),
            ("privacy", "Privacy"),
            ("startup", "Startup"),
            ("diagnostics", "Diagnostics & About"),
        ]
        for section in settingsSections {
            let button = win.buttons["settings.section.\(section.id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.label, section.title)
            button.click()
            assertBecomesSelected(button)
            XCTAssertTrue(
                win.descendants(matching: .any)["uitest.settingsContent.\(section.id)"]
                    .waitForExistence(timeout: 10),
                "\(section.title) should replace the current Settings section"
            )
        }
    }

    /// VoiceOver must receive the context hidden by icons, color, and unlabeled
    /// progress bars. The fixture makes every affected surface deterministic.
    func testStatusSurfacesExposeDescriptiveVoiceOverSemantics() throws {
        let app = launch(fixture: "accessibility", apiKey: "sample-ax-semantics-user")
        let win = window(app)

        win.buttons["uitest.tab.Travel"].click()
        let flightProgress = win.descendants(matching: .any)["uitest.travel.progress"]
        XCTAssertTrue(flightProgress.waitForExistence(timeout: 10))
        XCTAssertEqual(flightProgress.label, "Flight progress")
        // macOS XCUITest exposes an empty `value` for these custom SwiftUI
        // accessibility elements. Their VoiceOver values need a manual pass.

        win.buttons["uitest.tab.Attacks"].click()
        let attack = win.descendants(matching: .any)["uitest.attack.fixture-attack"]
        XCTAssertTrue(attack.waitForExistence(timeout: 10))
        XCTAssertTrue(attack.label.contains("Mugged"))
        XCTAssertTrue(attack.label.contains("outgoing attack against Fixture Opponent"))

        let incomingAttack = win.descendants(matching: .any)["uitest.attack.fixture-incoming-attack"]
        XCTAssertTrue(incomingAttack.waitForExistence(timeout: 10))
        XCTAssertTrue(incomingAttack.label.contains("Hospitalized"))
        XCTAssertTrue(incomingAttack.label.contains("incoming attack from Fixture Aggressor"))

        win.buttons["uitest.group.Account"].click()
        win.buttons["uitest.tab.Faction"].click()

        let ocProgress = win.descendants(matching: .any)["uitest.faction.ocProgress"]
        XCTAssertTrue(ocProgress.waitForExistence(timeout: 10))
        XCTAssertEqual(ocProgress.label, "Organized Crime progress")

        let warProgress = win.descendants(matching: .any)["uitest.faction.warProgress"]
        XCTAssertTrue(warProgress.waitForExistence(timeout: 10))
        XCTAssertEqual(warProgress.label, "Ranked War lead progress")
    }

    /// Sibling of `testStatusSurfacesExposeDescriptiveVoiceOverSemantics` — covers the
    /// batch-45 surfaces that test didn't reach: Battle Stats (AttacksView), Money,
    /// Properties, the Status-tab Chain card + Hospital badge + Events row, and Credits.
    /// Every one of these currently has zero accessibility modifiers, so VoiceOver
    /// reads each `Text`/icon as an unrelated fragment instead of one sentence, and
    /// colour-only meaning (rented badge, chain urgency, hospital state) never reaches
    /// non-visual users. This test pins the combined label each element MUST expose
    /// once issue #45 (and #44 for ChainView's `Color.gray`) is implemented.
    func testFinancialAndEventSurfacesExposeDescriptiveVoiceOverSemantics() throws {
        let app = launch(fixture: "accessibility", apiKey: "sample-ax-financial-user")
        let win = window(app)

        // MARK: Attacks — Battle Stats StatItem grid + Total row.
        // The accessibility fixture's fast-user JSON carries no battlestats keys, so
        // every stat decodes to its documented zero default — deterministic across
        // every poll, not just the first.
        win.buttons["uitest.tab.Attacks"].click()

        let strengthStat = win.descendants(matching: .any)["uitest.battleStats.Strength"]
        XCTAssertTrue(strengthStat.waitForExistence(timeout: 10),
                      "Each battle-stat tile must be one combined accessibility element")
        XCTAssertEqual(strengthStat.label, "Strength: 0",
                       "The stat's value must be read together with its label, not as two separate fragments")

        let totalStat = win.descendants(matching: .any)["uitest.battleStats.total"]
        XCTAssertTrue(totalStat.waitForExistence(timeout: 10))
        XCTAssertEqual(totalStat.label, "Total: 0")

        // MARK: Money — Cash card rows.
        win.buttons["uitest.group.Account"].click()
        win.buttons["uitest.tab.Money"].click()

        let cashRow = win.descendants(matching: .any)["uitest.money.cash"]
        XCTAssertTrue(cashRow.waitForExistence(timeout: 10),
                      "'On Hand' and its dollar value must combine into one sentence")
        XCTAssertEqual(cashRow.label, "On Hand: $1,000,000")

        let vaultRow = win.descendants(matching: .any)["uitest.money.vault"]
        XCTAssertTrue(vaultRow.waitForExistence(timeout: 10))
        XCTAssertEqual(vaultRow.label, "Vault: $0")

        let pointsRow = win.descendants(matching: .any)["uitest.money.points"]
        XCTAssertTrue(pointsRow.waitForExistence(timeout: 10))
        XCTAssertEqual(pointsRow.label, "Points: 10")

        let tokensRow = win.descendants(matching: .any)["uitest.money.tokens"]
        XCTAssertTrue(tokensRow.waitForExistence(timeout: 10))
        XCTAssertEqual(tokensRow.label, "Tokens: 0")

        // MARK: Properties — PropertyCard. The "rented out" badge today is colour
        // (orange text) only; the rent countdown's urgency (<=3 days => orange) is
        // also colour-only. Both must be readable from the label text alone.
        win.buttons["uitest.tab.Properties"].click()

        let propertyCard = win.descendants(matching: .any)["uitest.property.9101"]
        XCTAssertTrue(propertyCard.waitForExistence(timeout: 10),
                      "A property card must be one combined accessibility element")
        for expectedFragment in ["Property", "rented out", "$750,000", "$500,000", "200", "2 days"] {
            XCTAssertTrue(
                propertyCard.label.contains(expectedFragment),
                "Property card label '\(propertyCard.label)' must mention '\(expectedFragment)'"
            )
        }

        // MARK: Status tab — Chain card, Hospital badge, Events row.
        win.buttons["uitest.group.Now"].click()
        win.buttons["uitest.tab.Status"].click()

        let chainCard = win.descendants(matching: .any)["uitest.chain"]
        XCTAssertTrue(chainCard.waitForExistence(timeout: 10),
                      "The chain card must be one combined accessibility element")
        XCTAssertTrue(chainCard.label.contains("5/10"),
                      "Chain label '\(chainCard.label)' must state current/maximum")
        XCTAssertTrue(
            chainCard.label.lowercased().contains("warning"),
            "Chain label '\(chainCard.label)' must spell out the urgency the colour alone conveys " +
            "(fixture times out in ~150s, the orange/warning bucket)"
        )

        let hospitalBadge = win.descendants(matching: .any)["uitest.status.hospital"]
        XCTAssertTrue(hospitalBadge.waitForExistence(timeout: 10),
                      "The hospital status badge must be one combined accessibility element")
        XCTAssertTrue(
            hospitalBadge.label.localizedCaseInsensitiveContains("hospital"),
            "Hospital badge label '\(hospitalBadge.label)' must say what state the player is in"
        )

        let eventRow = win.descendants(matching: .any)["uitest.event.9002"]
        XCTAssertTrue(eventRow.waitForExistence(timeout: 10),
                      "Each event row must be one combined accessibility element")
        XCTAssertTrue(
            eventRow.label.contains("You were mugged by Fixture Mugger for $500."),
            "Event row label '\(eventRow.label)' must carry the (HTML-stripped) event text"
        )

        // MARK: Credits — static rows reachable from Settings > Diagnostics & About.
        win.buttons["uitest.openSettings"].click()
        win.buttons["settings.section.diagnostics"].click()
        win.buttons["Credits"].click()

        let developerRow = win.descendants(matching: .any)["uitest.credits.developer"]
        XCTAssertTrue(developerRow.waitForExistence(timeout: 10),
                      "The developer credit must be one combined accessibility element")
        XCTAssertTrue(developerRow.label.contains("bombel"))

        let factionRow = win.descendants(matching: .any)["uitest.credits.faction"]
        XCTAssertTrue(factionRow.waitForExistence(timeout: 10))
        XCTAssertTrue(factionRow.label.contains("The Masters"))

        let contributorRow = win.descendants(matching: .any)["uitest.credits.contributor.Greeney"]
        XCTAssertTrue(contributorRow.waitForExistence(timeout: 10),
                      "Even a contributor with no linked Torn profile needs a stable AX id")
        XCTAssertTrue(contributorRow.label.contains("Greeney"))
    }

    /// Compact list controls must remain easy to hit, while forum state that used to
    /// live only in icons, colour and tooltips stays available without a mouse.
    func testWatchListsExposeAccessibleControlsAndForumState() throws {
        let app = launch(fixture: "watchAccessibility", apiKey: "sample-watch-a11y-user")
        let win = window(app)

        win.buttons["uitest.group.Watch"].click()

        let priceAlert = win.buttons["Set price alert for Accessibility Item"]
        let removeItem = win.buttons["Remove Accessibility Item from price watch"]
        for control in [priceAlert, removeItem] {
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 24)
            XCTAssertGreaterThanOrEqual(control.frame.height, 24)
        }

        win.buttons["uitest.tab.Forums"].click()

        let errorText = win.staticTexts["Fixture forum unavailable."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10),
                      "Forum errors must be visible without hovering a tooltip")
        XCTAssertTrue(
            win.descendants(matching: .any)["Error: Fixture forum unavailable."]
                .waitForExistence(timeout: 10),
            "The warning icon must expose the error to VoiceOver"
        )
        XCTAssertTrue(
            win.descendants(matching: .any)["Last checked successfully"]
                .waitForExistence(timeout: 10),
            "A successful check must not rely on a green icon alone"
        )

        let notificationsOn = win.buttons[
            "Notifications on for Unavailable forum thread. Disable notifications"
        ]
        let notificationsOff = win.buttons[
            "Notifications off for Healthy forum thread. Enable notifications"
        ]
        let removeThread = win.buttons[
            "Remove Unavailable forum thread from watched threads"
        ]
        for control in [notificationsOn, notificationsOff, removeThread] {
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 24)
            XCTAssertGreaterThanOrEqual(control.frame.height, 24)
        }
    }

    // MARK: - Account isolation (T15 fixture preparation)

    /// A delayed, cancellation-ignoring response for synthetic account A must never
    /// overwrite or briefly reappear after switching to synthetic account B.
    func testAccountSwitchNeverFlashesStaleIdentity() throws {
        let app = launch(
            fixture: "accountSwitch",
            apiKey: "fixture-account-a"
        )
        let win = window(app)

        let accountA = win.staticTexts["Fixture Account A"]
        XCTAssertTrue(accountA.waitForExistence(timeout: 10), "Fixture account A should load")

        // Start the deliberately delayed second A request, then switch while it is in flight.
        win.buttons["Refresh Torn data"].click()
        win.buttons["uitest.openSettings"].click()

        let keyField = win.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10))
        keyField.click()
        keyField.typeKey("a", modifierFlags: .command)
        keyField.typeText("fixture-account-b")
        win.buttons["uitest.saveKey"].click()

        // During the new account's initial load ContentView disables interaction. Wait
        // for the fixture B response, then return to Status.
        let back = win.buttons["uitest.openSettings"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: back)
        waitForExpectations(timeout: 10)
        back.click()

        let accountB = win.staticTexts["Fixture Account B"]
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
        let win = window(app)

        let error = win.descendants(matching: .any)["uitest.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15),
                      "An invalid key should surface a visible error message")

        let recovery = win.descendants(matching: .any)["uitest.moduleState.recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10),
                      "Module recovery action must remain a separate accessibility element")
        XCTAssertEqual(recovery.label, "Settings")
    }

    func testOfflineModuleExposesRetryAsSeparateAccessibilityElement() throws {
        let app = launch(
            fixture: "empty",
            apiKey: "sample-offline-user",
            online: false
        )
        let win = window(app)

        let recovery = win.descendants(matching: .any)["uitest.moduleState.recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10),
                      "Retry must not be swallowed by the module status label")
        XCTAssertEqual(recovery.label, "Retry")
    }

    // MARK: - Key validation (Etap C)

    /// "Test Connection" validates the key against /key/info and reports what it unlocks.
    func testTestConnectionReportsAccess() throws {
        let app = launch(
            fixture: "full",
            apiKey: "sample-connection-user"
        )
        let win = window(app)

        // Open Settings from the signed-in footer, then run Test Connection.
        let settings = win.buttons["uitest.openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings button should exist")
        settings.click()

        let testButton = win.buttons["uitest.testConnection"]
        XCTAssertTrue(testButton.waitForExistence(timeout: 10), "Test Connection button should exist")
        testButton.click()

        XCTAssertTrue(win.descendants(matching: .any)["uitest.keyValidationSuccess"].waitForExistence(timeout: 15),
                      "A valid key should report its access level after Test Connection")
    }

    /// During onboarding, Test Connection validates the typed key WITHOUT saving it, so the
    /// result stays visible on the Settings screen instead of flipping to the tab UI.
    func testOnboardingTestConnectionKeepsSettingsVisible() throws {
        let app = launch(fixture: "full", apiKey: nil)
        let win = window(app)

        let keyField = win.secureTextFields["uitest.apiKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 10), "Key field should be shown at onboarding")
        keyField.click()
        keyField.typeText("sample-typed-value")

        win.buttons["uitest.testConnection"].click()

        XCTAssertTrue(win.descendants(matching: .any)["uitest.keyValidationSuccess"].waitForExistence(timeout: 15),
                      "Result should appear after Test Connection")
        XCTAssertTrue(keyField.exists,
                      "Test Connection must not save the key / leave the onboarding screen")
        XCTAssertFalse(win.buttons["uitest.tab.Status"].exists,
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
