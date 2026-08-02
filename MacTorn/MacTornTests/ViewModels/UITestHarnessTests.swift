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
