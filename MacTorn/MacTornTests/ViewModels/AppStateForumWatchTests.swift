import XCTest
@testable import MacTorn

@MainActor
final class AppStateForumWatchTests: XCTestCase {
    func testForumPollHTTPFailurePreservesLastGoodDataAndShowsError() async throws {
        appState.apiKey = "valid_key"
        appState.watchedThreads = [WatchedThread(id: 111, title: "Known thread", lastKnownPostCount: 42)]
        mockSession.setHTTPError(statusCode: 503)
        appState.refreshForumWatch()
        let deadline = Date().addingTimeInterval(2)
        while appState.watchedThreads.first?.error == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(appState.watchedThreads.first?.error)
        XCTAssertEqual(appState.watchedThreads.first?.title, "Known thread")
        XCTAssertEqual(appState.watchedThreads.first?.lastKnownPostCount, 42)
    }

    func testMalformedNewThreadLeavesLoadingStateAndCanRecover() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: [:])
        XCTAssertTrue(appState.addWatchedThread(input: "111"))
        let deadline = Date().addingTimeInterval(2)
        while appState.watchedThreads.first?.error == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(appState.watchedThreads.first?.error)
        XCTAssertEqual(appState.watchedThreads.first?.title, "Thread #111")
        try mockSession.setSuccessResponse(json: ["thread": ["title": "Recovered thread", "posts": 42]])
        appState.refreshForumWatch()
        let retryDeadline = Date().addingTimeInterval(2)
        while appState.watchedThreads.first?.error != nil, Date() < retryDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(appState.watchedThreads.first?.error)
        XCTAssertEqual(appState.watchedThreads.first?.title, "Recovered thread")
        XCTAssertEqual(appState.watchedThreads.first?.lastKnownPostCount, 42)
    }

    var mockSession: MockNetworkSession!
    var appState: AppState!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults = .createMockDefaults()
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession, defaults: testDefaults)
        testDefaults.removeObject(forKey: "forumWatchedThreads")
        testDefaults.removeObject(forKey: "forumWatchConfig")
        appState.watchedThreads = []
        appState.forumWatchConfig = ForumWatchConfig()
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState.stopForumPolling()
        appState = nil
        mockSession = nil
        testDefaults.removeObject(forKey: "forumWatchedThreads")
        testDefaults.removeObject(forKey: "forumWatchConfig")
        try await super.tearDown()
    }

    // MARK: - Add Thread Tests

    func testAddWatchedThread_addsThread() {
        appState.apiKey = "valid_key"
        XCTAssertTrue(appState.addWatchedThread(input: "12345"))

        XCTAssertEqual(appState.watchedThreads.count, 1)
        XCTAssertEqual(appState.watchedThreads.first?.id, 12345)
        XCTAssertEqual(appState.watchedThreads.first?.title, "Loading...")
    }

    // MARK: - v2 Error Envelope Contract (forum endpoint)

    /// The forum endpoint is v2 (`/v2/forum/{threadId}/thread`). Torn's v2 error
    /// envelope is `{"code":Int,"error":String}` with `error` as a TOP-LEVEL string.
    /// A swallowed error makes the thread parse as a bogus "Unknown" thread with
    /// post count 0 — corrupting watch state. The error must be surfaced instead.
    func testFetchForumThreadMetadata_surfacesV2RateLimitError() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIErrorV2(code: 5, message: "Too many requests")

        appState.addWatchedThread(input: "12345")
        try await Task.sleep(nanoseconds: 800_000_000)

        let thread = appState.watchedThreads.first
        XCTAssertEqual(thread?.error, "Too many requests — backing off.",
                       "v2 forum error envelope must be surfaced, not parsed as an 'Unknown' thread")
        XCTAssertNotEqual(thread?.title, "Unknown",
                          "on a v2 error the thread title must not be corrupted to 'Unknown'")
    }
}

// MARK: - A halted key stops Forum Watch too (audit F-06)

@MainActor
final class ForumWatchKeyHaltTests: XCTestCase {
    private var mockSession: MockNetworkSession!
    private var app: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        app = AppState(session: mockSession,
                       connectivity: ControllableConnectivity(),
                       defaults: .createMockDefaults())
        app.apiKey = "forum-halt-\(UUID().uuidString)"
        app.watchedThreads = [WatchedThread(id: 111, title: "Thread A")]
        try mockSession.setSuccessResponse(json: TornAPIFixtures.forumThreadSuccess)
    }

    override func tearDown() async throws {
        app.stopForumPolling()
        app = nil
        mockSession = nil
        try await super.tearDown()
    }

    /// Rejects the key the way a code-2 response does.
    private func haltOnRejectedKey() {
        app.handlePermanentKeyError(.permanentKey(code: 2, message: "Incorrect key"))
        XCTAssertTrue(app.keyHalted)
    }

    private var forumRequests: [URL] {
        mockSession.requestedURLs.filter { $0.absoluteString.contains("/forum/") }
    }

    func testPermanentKeyErrorStopsTheForumTimer() {
        app.startForumPolling()
        XCTAssertTrue(app.forumTimer.isRunning)

        app.handlePermanentKeyError(.permanentKey(code: 2, message: "Incorrect key"))

        XCTAssertFalse(app.forumTimer.isRunning,
                     "a rejected key must not keep polling threads every few minutes")
    }

    func testHaltedKeyIssuesNoForumThreadRequests() async throws {
        haltOnRejectedKey()

        app.refreshForumWatch()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(forumRequests.isEmpty)
    }

    /// The menu's onAppear calls `startForumPolling()` every time it opens; after a halt
    /// that used to reinstall the timer.
    func testStartForumPollingIsRefusedWhileHalted() async throws {
        haltOnRejectedKey()

        app.startForumPolling()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(app.forumTimer.isRunning)
        XCTAssertTrue(forumRequests.isEmpty)
    }
}
