import XCTest
import Sentry
@testable import MacTorn

/// Unit coverage for the deterministic UI-test harness (Etap G / ISC-20). The XCUITest
/// suite proves the harness end-to-end; these pin its pure routing/decoding contract so a
/// regression is caught in milliseconds without launching the app.
#if DEBUG
final class UITestHarnessTests: XCTestCase {

    private let fakeKey = "sample-harness-value"

    // MARK: - Fixture routing

    func testFullScenarioServesDecodableUserResponse() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)

        let decoded = try JSONDecoder().decode(TornResponse.self, from: data)
        XCTAssertEqual(decoded.name, "TestPlayer")
        XCTAssertNotNil(decoded.bars, "The full fixture should populate bars")
    }

    func testInvalidKeyScenarioServesErrorEnvelope() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .invalidKey)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 2, "Invalid-key fixture must carry Torn code 2")
    }

    func testEmptyScenarioServesEmptyObject() throws {
        let url = TornAPI.url(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .empty)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Empty scenario should serve {}")
    }

    /// Only the fast user call (which carries the `bars` selection) gets the rich fixture;
    /// the faction call must not be mistaken for it.
    func testFactionEndpointServesEmptyObjectEvenInFullScenario() throws {
        let url = TornAPI.factionURL(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Faction endpoint should not receive the user fixture")
    }

    /// The row-based activity call also hits the `/user/` path but without `bars`; it must
    /// not be served the fast-user fixture (which would double-count / mis-decode).
    func testUserActivityCallIsNotServedFastFixture() throws {
        let url = TornAPI.activityURL(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .full)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?.isEmpty, true, "Activity call must not get the fast-user fixture")
    }

    // MARK: - Issue #84 probes: the `.accessibility` activity seed must survive a poll
    //
    // `UITestConfiguration.makeAppState()` seeds exactly one activity event for the
    // `.accessibility` scenario and claims it is "never overwritten by fetchActivityData's
    // `if let events = ...` guard" because the activity endpoint serves `[:]`. These pin
    // every link in that chain so the XCUITest failure (`uitest.event.9002` never found)
    // can be localised without launching the app.

    /// Link 1: the fixture really does serve `{}` on the activity call for `.accessibility`.
    func testAccessibilityScenarioServesEmptyObjectOnActivityCall() throws {
        let url = TornAPI.activityURL(for: fakeKey)
        let data = FixtureNetworkSession.body(for: url, scenario: .accessibility)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json.isEmpty,
                      "The accessibility scenario must not route the activity call to a rich fixture")
    }

    /// Link 2: an empty activity body must decode to *absent* events, not to an empty
    /// array. `UserActivityPayload.events` is optional precisely so `AppState` can tell
    /// "the endpoint said nothing" from "the endpoint said zero events" — and only the
    /// former leaves a seeded list alone.
    func testEmptyActivityBodyReportsAbsentEventsRatherThanZeroEvents() async throws {
        let session = FixtureNetworkSession(scenario: .accessibility)
        let service = UserSnapshotService(session: session)
        let url = try XCTUnwrap(TornAPI.activityURL(for: fakeKey))

        let result = try await service.loadActivity(url)
        guard case .success(let payload, _) = result else {
            return XCTFail("Activity call should succeed on an empty body, got \(result)")
        }

        XCTAssertNil(payload.events,
                     "An activity response with no \"events\" key must report nil, not [] — " +
                     "[] passes the `if let events` guard and wipes seeded/known events")
    }

    /// Link 3: `identified(by:)` must win over the timestamp-derived fallback, so the row's
    /// accessibility identifier really is `uitest.event.9002`.
    func testSeededAccessibilityEventKeepsItsAPIIdentity() throws {
        let json = Data("""
        {"timestamp": 1735689600, "event": "You were mugged by <a href=\\"#\\">Fixture Mugger</a> for $500."}
        """.utf8)
        let event = try JSONDecoder().decode(TornEvent.self, from: json).identified(by: "9002")

        XCTAssertEqual(event.id, "9002")
        XCTAssertEqual("uitest.event.\(event.id)", "uitest.event.9002")
        XCTAssertEqual(event.cleanEvent, "You were mugged by Fixture Mugger for $500.")
    }

    /// Link 4, end to end: seed the event exactly as the harness does, run one real poll
    /// through the fixture session, and require the row to still be there afterwards.
    /// If this goes red, no amount of scrolling in XCUITest can find `uitest.event.9002`.
    @MainActor
    func testAccessibilityPollDoesNotClearSeededActivityEvents() async throws {
        let appState = AppState(session: FixtureNetworkSession(scenario: .accessibility),
                                connectivity: ControllableConnectivity(),
                                defaults: .createMockDefaults())
        appState.apiKey = "sample-ax-financial-user"   // resets account-scoped state

        let seeded = try JSONDecoder().decode(
            TornEvent.self,
            from: Data("""
            {"timestamp": \(Int(Date().timeIntervalSince1970) - 90), "event": "You were mugged for $500."}
            """.utf8)
        ).identified(by: "9002")
        appState.activityEvents = [seeded]

        XCTAssertTrue(appState.fetchData(), "The fixture poll should start")

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              appState.endpointHealth.latest(for: "user.activity") == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(appState.endpointHealth.latest(for: "user.activity"),
                        "The activity call must have run for this probe to mean anything")

        XCTAssertEqual(appState.activityEvents.map(\.id), ["9002"],
                       "The accessibility fixture's seeded event must survive the activity poll — " +
                       "StatusView hides EventsView entirely when activityEvents is empty")
    }

    func testNilURLDoesNotCrashAndServesEmpty() {
        let data = FixtureNetworkSession.body(for: nil, scenario: .full)
        XCTAssertFalse(data.isEmpty, "A nil URL should still yield a valid (empty-object) body")
    }

    // MARK: - Scenario parsing

    func testFixtureScenarioRawValues() {
        XCTAssertEqual(FixtureScenario(rawValue: "full"), .full)
        XCTAssertEqual(FixtureScenario(rawValue: "invalidKey"), .invalidKey)
        XCTAssertEqual(FixtureScenario(rawValue: "empty"), .empty)
        XCTAssertEqual(FixtureScenario(rawValue: "accountSwitch"), .accountSwitch)
        XCTAssertEqual(FixtureScenario(rawValue: "accessibility"), .accessibility)
        XCTAssertEqual(FixtureScenario(rawValue: "watchAccessibility"), .watchAccessibility)
        XCTAssertNil(FixtureScenario(rawValue: "nonsense"))
    }

    func testAccountSwitchFixtureRoutesSyntheticIdentityByKey() throws {
        let accountAURL = try XCTUnwrap(TornAPI.url(for: FixtureNetworkSession.accountAKey))
        let accountBURL = try XCTUnwrap(TornAPI.url(for: FixtureNetworkSession.accountBKey))

        let accountAData = FixtureNetworkSession.body(for: accountAURL, scenario: .accountSwitch)
        let accountBData = FixtureNetworkSession.body(for: accountBURL, scenario: .accountSwitch)
        let accountA = try JSONDecoder().decode(TornResponse.self, from: accountAData)
        let accountB = try JSONDecoder().decode(TornResponse.self, from: accountBData)

        XCTAssertEqual(accountA.name, "Fixture Account A")
        XCTAssertEqual(accountA.playerId, 100_001)
        XCTAssertEqual(accountB.name, "Fixture Account B")
        XCTAssertEqual(accountB.playerId, 200_002)
    }

    func testAccountSwitchFixtureRejectsUnknownSyntheticKey() throws {
        let url = try XCTUnwrap(TornAPI.url(for: "fixture-unknown"))
        let data = FixtureNetworkSession.body(for: url, scenario: .accountSwitch)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(json["error"] as? [String: Any])

        XCTAssertEqual(error["code"] as? Int, 2)
    }

    // MARK: - Sentry maintenance contract

    func testSentryStartupRemainsOptInAndDisabledForUITests() {
        XCTAssertFalse(SentryManager.shouldStart(isEnabled: false, isUITesting: false))
        XCTAssertFalse(SentryManager.shouldStart(isEnabled: true, isUITesting: true))
        XCTAssertTrue(SentryManager.shouldStart(isEnabled: true, isUITesting: false))
    }

    func testSentryConfigurationRemainsCrashOnlyAndPIIFree() throws {
        let options = Options()

        SentryManager.configure(options, release: "1.2.3", environment: "test")

        XCTAssertEqual(options.releaseName, "mactorn@1.2.3")
        XCTAssertEqual(options.environment, "test")
        XCTAssertEqual(options.tracesSampleRate?.doubleValue, 0)
        XCTAssertFalse(options.sendDefaultPii)
        XCTAssertFalse(options.enableNetworkTracking)
        XCTAssertFalse(options.enableNetworkBreadcrumbs)
        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertFalse(options.enableAppHangTracking)

        let request = SentryRequest()
        request.url = "https://api.torn.com/user/?selections=basic&key=TOP_SECRET"
        request.queryString = "selections=basic&key=TOP_SECRET"
        let event = Event(level: .error)
        event.request = request

        let scrubbedEvent = try XCTUnwrap(options.beforeSend?(event))
        XCTAssertEqual(scrubbedEvent.request?.url, "https://api.torn.com/user?[key,selections]")
        XCTAssertNil(scrubbedEvent.request?.queryString)

        let breadcrumb = Breadcrumb(level: .info, category: "http")
        breadcrumb.data = [
            "url": "https://api.torn.com/user/?selections=basic&key=TOP_SECRET",
        ]
        let scrubbedBreadcrumb = try XCTUnwrap(options.beforeBreadcrumb?(breadcrumb))
        XCTAssertEqual(
            scrubbedBreadcrumb.data?["url"] as? String,
            "https://api.torn.com/user?[key,selections]"
        )
    }

    // MARK: - Grouped navigation

    func testNavigationGroupsCoverEveryTabExactlyOnce() {
        let groupedTabs = AppGroup.allCases.flatMap(\.tabs)

        XCTAssertEqual(groupedTabs.count, AppTab.allCases.count)
        XCTAssertEqual(Set(groupedTabs), Set(AppTab.allCases))
    }

    func testNavigationGroupMappingsAndDefaults() {
        XCTAssertEqual(AppGroup.now.tabs, [.status, .travel, .attacks])
        XCTAssertEqual(AppGroup.account.tabs, [.money, .properties, .stocks, .faction])
        XCTAssertEqual(AppGroup.watch.tabs, [.watchlist, .forums])

        for group in AppGroup.allCases {
            XCTAssertEqual(group.defaultTab.group, group)
            XCTAssertTrue(group.tabs.allSatisfy { $0.group == group })
        }
    }

    // MARK: - Keyboard-first command contract

    func testNavigationCommandsCoverEveryTabWithUniqueShortcuts() {
        let commands = MacTornCommand.navigation

        XCTAssertEqual(Set(commands.compactMap(\.tab)), Set(AppTab.allCases))
        XCTAssertEqual(Set(commands.map(\.keyEquivalent)).count, AppTab.allCases.count)
        XCTAssertEqual(commands.map(\.keyEquivalent), Array("123456789"))
    }

    func testGlobalCommandShortcutsRemainConventional() {
        XCTAssertEqual(MacTornCommand.refresh.keyEquivalent, "r")
        XCTAssertEqual(MacTornCommand.settings.keyEquivalent, ",")
        XCTAssertNil(MacTornCommand.refresh.tab)
        XCTAssertNil(MacTornCommand.settings.tab)
    }

    func testNavigationStateKeepsClicksAndCommandsInSync() {
        let navigation = AppNavigationState()

        XCTAssertEqual(navigation.selectedTab, .status)
        XCTAssertFalse(navigation.isShowingSettings)

        navigation.showSettings()
        XCTAssertTrue(navigation.isShowingSettings)
        XCTAssertFalse(
            navigation.dismissSettings(hasConfiguredAccount: false),
            "Onboarding Settings must not be dismissible"
        )

        navigation.select(.forums)
        XCTAssertEqual(navigation.selectedTab, .forums)
        XCTAssertFalse(navigation.isShowingSettings)

        navigation.showSettings()
        XCTAssertTrue(navigation.dismissSettings(hasConfiguredAccount: true))
        XCTAssertFalse(navigation.isShowingSettings)
    }

    func testSettingsSectionsHaveStableCompactNavigation() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["Account", "Refresh", "Notifications", "Privacy", "Startup", "Diagnostics & About"]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.compactTitle),
            ["Account", "Refresh", "Alerts", "Privacy", "Startup", "About"]
        )
        XCTAssertEqual(
            Set(SettingsSection.allCases.map(\.anchorID)).count,
            SettingsSection.allCases.count
        )
    }
}
#endif
