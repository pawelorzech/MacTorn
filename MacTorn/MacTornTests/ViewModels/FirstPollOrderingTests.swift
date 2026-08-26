import XCTest
@testable import MacTorn

/// The first poll of a session must not go out before MacTorn knows what the key can read.
///
/// This has been got wrong twice, in opposite directions, which is why it has its own
/// suite. First the capabilities load ran *alongside* the first fetch, so narrowing never
/// applied to the one request it exists for. Then the fix withheld the polling timer until
/// that fetch finished, which stopped a slow `/key/info` from leaking an un-narrowed
/// request but left `refreshNow` free to install a second timer during the wait — and left
/// a cancelled first fetch with no timer at all.
///
/// The invariant is therefore stated three ways below: the timer exists immediately, no
/// poll goes out while the wait is on, and the wait always ends.
@MainActor
final class FirstPollOrderingTests: XCTestCase {

    private func makeApp() -> AppState {
        AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults()
        )
    }

    // MARK: - The timer must exist straight away

    /// `refreshNow` installs a timer whenever it finds none, so a window where
    /// `startPolling` has returned without one is a window where a manual refresh creates
    /// a duplicate and orphans whatever arrives later.
    func testStartPollingInstallsTheTimerSynchronously() throws {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.startPolling()

        XCTAssertNotNil(app.timerCancellable,
                        "a caller that returns without a timer lets refreshNow create a second one")
        app.stopPolling()
    }

    func testAManualRefreshDuringTheWaitDoesNotReplaceTheTimer() throws {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.startPolling()
        let timer = try XCTUnwrap(app.timerCancellable)

        app.refreshNow()

        XCTAssertTrue(app.timerCancellable === timer,
                      "the automatic timer must survive a refresh issued mid-wait")
        app.stopPolling()
    }

    // MARK: - Nothing polls while the wait is on

    func testAManualRefreshIsRefusedWhileWaitingOnKeyInfo() {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.awaitingFirstKeyInfo = true
        app.lastManualRefreshAt = nil

        app.refreshNow()

        // `refreshNow` stamps this only on a refresh it accepted, so an untouched value is
        // the observable proof that the guard turned it away.
        XCTAssertNil(app.lastManualRefreshAt,
                     "a manual refresh must not jump the capabilities load")
        app.stopPolling()
    }

    func testAManualRefreshIsAcceptedOnceTheWaitIsOver() {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.keyInfo = TornKeyInfo.testFixture()
        app.awaitingFirstKeyInfo = false
        app.lastManualRefreshAt = nil

        app.refreshNow()

        XCTAssertNotNil(app.lastManualRefreshAt, "the guard must lift, not latch")
        app.stopPolling()
    }

    // MARK: - The wait always ends

    /// Cleared before the cancellation check, so a first fetch cancelled by an account
    /// change still unblocks the timer. Otherwise polling stops for the whole session.
    func testAnAccountChangeClearsTheWait() {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.awaitingFirstKeyInfo = true

        app.resetAccountScopedState()

        XCTAssertFalse(app.awaitingFirstKeyInfo)
        XCTAssertNil(app.firstFetchTask)
    }

    func testAKeyAlreadyKnownThisSessionDoesNotWait() {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.keyInfo = TornKeyInfo.testFixture()

        app.startPolling()

        XCTAssertFalse(app.awaitingFirstKeyInfo,
                       "a validated key costs no round-trip on a later startPolling")
        XCTAssertNotNil(app.timerCancellable)
        app.stopPolling()
    }
}

// MARK: - Fixtures

extension TornKeyInfo {
    /// A Full Access key, decoded through the real decoder so the shape stays honest.
    static func testFixture(factionID: Int? = 100) -> TornKeyInfo {
        let json: [String: Any] = [
            "info": [
                "access": ["level": 4, "type": "Full Access", "faction": true, "company": false,
                           "log": ["custom_permissions": false, "available": []]],
                "user": ["id": 42,
                         "faction_id": factionID.map { $0 as Any } ?? NSNull(),
                         "company_id": NSNull()],
                "selections": [
                    "user": ["basic", "bars", "cooldowns", "travel", "profile", "money",
                             "battlestats", "properties", "stocks", "organizedcrime",
                             "refills", "education", "bounties", "notifications",
                             "events", "attacks"],
                    "faction": ["basic", "chain"],
                    "market": ["itemmarket"],
                    "property": [],
                    "torn": ["stocks", "items"],
                    "racing": [],
                    "forum": [],
                    "key": ["info"],
                    "company": [],
                ],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(TornKeyInfo.Response.self, from: data).info
    }
}
