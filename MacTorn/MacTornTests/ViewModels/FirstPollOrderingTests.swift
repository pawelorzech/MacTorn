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

    func testSaveAndConnectRefreshRequestsKeyInfoBeforeUserData() async throws {
        let session = FirstPollRoutingSession()
        let app = AppState(
            session: session,
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults()
        )
        app.apiKey = "save-connect-\(UUID().uuidString)"

        app.refreshNow()

        for _ in 0..<100 where session.requestedPaths().count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let paths = session.requestedPaths()
        XCTAssertGreaterThanOrEqual(paths.count, 2)
        XCTAssertEqual(paths.first, "/v2/key/info")
        XCTAssertEqual(paths.first(where: { $0 != "/v2/key/info" }), "/user")
        app.stopPolling()
    }

    // MARK: - Account changes

    /// An account change must tear down the previous account's timer, or `startPolling`'s
    /// early-return guard reads `timerCancellable` and `lastFetchTime` from the old account
    /// and skips establishing the ordering for the new key entirely.
    func testAnAccountChangeTearsDownThePreviousTimer() {
        let app = makeApp()
        app.apiKey = "first-\(UUID().uuidString)"
        app.startPolling()
        XCTAssertNotNil(app.timerCancellable)

        app.apiKey = "second-\(UUID().uuidString)"

        XCTAssertNil(app.timerCancellable,
                     "the old account's timer must not poll under the new account's key")
    }

    /// A superseded attempt must not clear the window a newer one opened — the same shape
    /// as the deferred-handle clobber, relocated to the flag.
    func testASupersededFirstFetchDoesNotClearALiveWait() {
        let app = makeApp()
        app.apiKey = "superseded-\(UUID().uuidString)"
        app.awaitingFirstKeyInfo = true
        let stale = app.firstFetchGeneration

        app.firstFetchGeneration &+= 1   // a newer attempt takes ownership

        XCTAssertNotEqual(stale, app.firstFetchGeneration,
                          "the generation is what lets the stale task recognise itself")
        XCTAssertTrue(app.awaitingFirstKeyInfo)
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

private final class FirstPollRoutingSession: NetworkSession, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func requestedPaths() -> [String] { lock.withLock { paths } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://api.torn.com")!
        lock.withLock { paths.append(url.path) }
        let json: [String: Any]
        if url.path == "/v2/key/info" {
            json = [
                "info": [
                    "access": ["level": 4, "type": "Full Access", "faction": false,
                               "company": false],
                    "user": ["id": 42, "faction_id": NSNull(), "company_id": NSNull()],
                    "selections": [
                        "user": ["basic", "bars", "cooldowns", "travel", "profile",
                                 "money", "battlestats", "properties", "stocks",
                                 "organizedcrime", "refills", "education", "bounties",
                                 "notifications", "events", "attacks"],
                        "faction": [], "market": ["itemmarket"], "property": [],
                        "torn": ["stocks", "items"], "racing": [], "forum": [],
                        "key": ["info"], "company": [],
                    ],
                ],
            ]
        } else {
            json = TornAPIFixtures.validFullResponse()
        }
        let data = try TornAPIFixtures.toData(json)
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
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
