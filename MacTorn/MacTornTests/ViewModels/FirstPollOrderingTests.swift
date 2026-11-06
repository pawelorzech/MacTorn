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

    private func makeApp(_ session: NetworkSession = MockNetworkSession()) -> AppState {
        AppState(
            session: session,
            connectivity: ControllableConnectivity(connected: true),
            defaults: .createMockDefaults(),
            time: MutableTimeSource()
        )
    }

    // MARK: - The timer must exist straight away

    /// `refreshNow` installs a timer whenever it finds none, so a window where
    /// `startPolling` has returned without one is a window where a manual refresh creates
    /// a duplicate and orphans whatever arrives later.
    func testStartPollingInstallsTheTimerSynchronously() {
        let app = makeApp()
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.startPolling()

        XCTAssertTrue(app.pollTimer.isRunning,
                      "a caller that returns without a timer lets refreshNow create a second one")
        app.stopPolling()
    }

    // MARK: - Nothing polls while the wait is on

    func testNothingPollsWhileKeyInfoIsPendingAndManualRefreshesAreTurnedAway() async {
        let session = FirstPollRoutingSession(holdKeyInfo: true)
        let app = makeApp(session)
        defer { session.releaseKeyInfo(); app.stopPolling() }
        app.apiKey = "ordering-\(UUID().uuidString)"

        app.startPolling()
        let asked = await eventually { session.requestedPaths() == ["/v2/key/info"] }
        XCTAssertTrue(asked, "the capabilities load goes out first")

        app.refreshNow()
        app.refreshNow()
        await settle()
        XCTAssertEqual(session.requestedPaths(), ["/v2/key/info"],
                       "no poll and no second handshake may jump the capabilities load")

        session.releaseKeyInfo()
        let polled = await eventually { session.requestedPaths().contains("/user") }
        XCTAssertTrue(polled, "the first poll follows once the key is understood")
        XCTAssertEqual(session.requestedPaths().first, "/v2/key/info")
        XCTAssertEqual(session.requestedPaths().filter { $0 == "/v2/key/info" }.count, 1)
    }

    func testAManualRefreshIsAcceptedOnceTheWaitIsOver() async {
        let session = FirstPollRoutingSession(holdKeyInfo: false)
        let app = makeApp(session)
        defer { app.stopPolling() }
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.startPolling()
        let firstPoll = await eventually { app.player.data != nil }
        XCTAssertTrue(firstPoll)
        XCTAssertEqual(session.userPolls(), 1)

        app.refreshNow()

        let refreshed = await eventually { session.userPolls() == 2 }
        XCTAssertTrue(refreshed, "the guard must lift, not latch")
    }

    func testSaveAndConnectRefreshRequestsKeyInfoBeforeUserData() async {
        let session = FirstPollRoutingSession(holdKeyInfo: false)
        let app = makeApp(session)
        defer { app.stopPolling() }
        app.apiKey = "save-connect-\(UUID().uuidString)"

        app.refreshNow()

        let sent = await eventually { session.requestedPaths().count >= 2 }
        XCTAssertTrue(sent)
        let paths = session.requestedPaths()
        XCTAssertEqual(paths.first, "/v2/key/info")
        XCTAssertEqual(paths.first(where: { $0 != "/v2/key/info" }), "/user")
    }

    // MARK: - Account changes

    /// An account change must tear down the previous account's timer, or `startPolling`'s
    /// early-return guard reads the old account's state and skips establishing the
    /// ordering for the new key entirely.
    func testAnAccountChangeTearsDownThePreviousTimer() {
        let app = makeApp()
        app.apiKey = "first-\(UUID().uuidString)"
        app.startPolling()
        XCTAssertTrue(app.pollTimer.isRunning)

        app.apiKey = "second-\(UUID().uuidString)"

        XCTAssertFalse(app.pollTimer.isRunning,
                       "the old account's timer must not poll under the new account's key")
    }

    // MARK: - The wait always ends

    /// A first fetch cancelled by an account change must still unblock polling for the new
    /// key, or polling stops for the whole session; and the old key must never poll.
    func testAnAccountChangeDuringTheWaitStillLetsTheNewKeyPoll() async throws {
        let session = FirstPollRoutingSession(holdKeyInfo: true)
        let app = makeApp(session)
        defer { session.releaseKeyInfo(); app.stopPolling() }
        let oldKey = "old-\(UUID().uuidString)"
        let newKey = "new-\(UUID().uuidString)"
        app.apiKey = oldKey
        app.startPolling()
        let waiting = await eventually { session.requestedPaths() == ["/v2/key/info"] }
        XCTAssertTrue(waiting)

        app.apiKey = newKey
        app.startPolling()
        session.releaseKeyInfo()

        let polled = await eventually { session.userPolls() >= 1 }
        XCTAssertTrue(polled, "the new key must be polled even though the old wait was cancelled")
        await settle()
        for url in session.requestedURLs() where url.path == "/user" {
            XCTAssertTrue(url.query?.contains("key=\(newKey)") == true, "the old key must not poll: \(url)")
        }
    }

    func testAKeyAlreadyKnownThisSessionDoesNotWait() async {
        let session = FirstPollRoutingSession(holdKeyInfo: false)
        let app = makeApp(session)
        defer { app.stopPolling() }
        app.apiKey = "ordering-\(UUID().uuidString)"
        app.requester.testKeyInfo = TornKeyInfo.testFixture()

        app.startPolling()

        let polled = await eventually { session.userPolls() >= 1 }
        XCTAssertTrue(polled)
        XCTAssertEqual(session.requestedPaths().filter { $0 == "/v2/key/info" }.count, 0,
                       "a validated key costs no round-trip on a later startPolling")
    }
}

private final class FirstPollRoutingSession: NetworkSession, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding: Bool

    /// With `holdKeyInfo`, `/key/info` stays unanswered until `releaseKeyInfo()`.
    init(holdKeyInfo: Bool) { holding = holdKeyInfo }

    func requestedURLs() -> [URL] { lock.withLock { urls } }
    func requestedPaths() -> [String] { requestedURLs().map(\.path) }
    /// Fast user polls only: the fan-out also sends row-based `/user` calls without `bars`.
    func userPolls() -> Int {
        requestedURLs().filter { $0.path == "/user" && ($0.query ?? "").contains("bars") }.count
    }

    func releaseKeyInfo() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        pending.forEach { $0.resume() }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://api.torn.com")!
        lock.withLock { urls.append(url) }
        if url.path == "/v2/key/info" {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if holding { held.append(continuation); return false }
                    return true
                }
                if resumeNow { continuation.resume() }
            }
        }
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
