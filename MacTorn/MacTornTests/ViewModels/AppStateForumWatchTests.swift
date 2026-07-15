import XCTest
@testable import MacTorn

@MainActor
final class AppStateForumWatchTests: XCTestCase {

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

    // MARK: - parseThreadInput Tests

    func testParseThreadInput_bareId() {
        XCTAssertEqual(appState.parseThreadInput("12345"), 12345)
    }

    func testParseThreadInput_bareIdWithSpaces() {
        XCTAssertEqual(appState.parseThreadInput("  12345  "), 12345)
    }

    func testParseThreadInput_urlWithThreadId() {
        let url = "https://www.torn.com/forums.php#/p=threads&f=67&t=16532308"
        XCTAssertEqual(appState.parseThreadInput(url), 16532308)
    }

    func testParseThreadInput_urlWithQueryParam() {
        let url = "https://www.torn.com/forums.php?t=12345"
        XCTAssertEqual(appState.parseThreadInput(url), 12345)
    }

    func testParseThreadInput_invalidInput() {
        XCTAssertNil(appState.parseThreadInput("abc"))
        XCTAssertNil(appState.parseThreadInput(""))
        XCTAssertNil(appState.parseThreadInput("https://www.torn.com/forums.php"))
    }

    // MARK: - Add Thread Tests

    func testAddWatchedThread_addsThread() {
        appState.apiKey = "valid_key"
        appState.addWatchedThread(input: "12345")

        XCTAssertEqual(appState.watchedThreads.count, 1)
        XCTAssertEqual(appState.watchedThreads.first?.id, 12345)
        XCTAssertEqual(appState.watchedThreads.first?.title, "Loading...")
    }

    func testAddWatchedThread_preventsDuplicate() {
        appState.apiKey = "valid_key"
        appState.addWatchedThread(input: "12345")
        appState.addWatchedThread(input: "12345")

        XCTAssertEqual(appState.watchedThreads.count, 1)
    }

    func testAddWatchedThread_invalidInput() {
        appState.apiKey = "valid_key"
        appState.addWatchedThread(input: "invalid")

        XCTAssertTrue(appState.watchedThreads.isEmpty)
    }

    func testAddWatchedThread_fromURL() {
        appState.apiKey = "valid_key"
        appState.addWatchedThread(input: "https://www.torn.com/forums.php#/p=threads&f=67&t=16532308")

        XCTAssertEqual(appState.watchedThreads.count, 1)
        XCTAssertEqual(appState.watchedThreads.first?.id, 16532308)
    }

    // MARK: - Remove Thread Tests

    func testRemoveWatchedThread() {
        appState.watchedThreads = [
            WatchedThread(id: 111, title: "Thread A"),
            WatchedThread(id: 222, title: "Thread B")
        ]

        appState.removeWatchedThread(111)

        XCTAssertEqual(appState.watchedThreads.count, 1)
        XCTAssertNil(appState.watchedThreads.first(where: { $0.id == 111 }))
        XCTAssertNotNil(appState.watchedThreads.first(where: { $0.id == 222 }))
    }

    func testRemoveWatchedThread_nonExistent() {
        appState.watchedThreads = [
            WatchedThread(id: 111, title: "Thread A")
        ]

        appState.removeWatchedThread(999)

        XCTAssertEqual(appState.watchedThreads.count, 1)
    }

    // MARK: - Toggle Notifications Tests

    func testToggleThreadNotifications() {
        appState.watchedThreads = [
            WatchedThread(id: 111, title: "Thread A", notificationsEnabled: true)
        ]

        appState.toggleThreadNotifications(111)
        XCTAssertFalse(appState.watchedThreads.first!.notificationsEnabled)

        appState.toggleThreadNotifications(111)
        XCTAssertTrue(appState.watchedThreads.first!.notificationsEnabled)
    }

    // MARK: - Persistence Tests

    func testSaveAndLoadForumWatch() {
        appState.watchedThreads = [
            WatchedThread(id: 111, title: "Thread A", notificationsEnabled: false, lastKnownPostCount: 42),
            WatchedThread(id: 222, title: "Thread B", notificationsEnabled: true, lastKnownPostCount: 10, isFactionThread: true)
        ]
        appState.forumWatchConfig.factionForumAutoMonitor = true
        appState.forumWatchConfig.pollingIntervalSeconds = 300
        appState.saveForumWatch()

        let newAppState = AppState(session: mockSession, defaults: testDefaults)

        XCTAssertEqual(newAppState.watchedThreads.count, 2)
        XCTAssertEqual(newAppState.watchedThreads[0].id, 111)
        XCTAssertEqual(newAppState.watchedThreads[0].notificationsEnabled, false)
        XCTAssertEqual(newAppState.watchedThreads[0].lastKnownPostCount, 42)
        XCTAssertEqual(newAppState.watchedThreads[1].isFactionThread, true)
        XCTAssertTrue(newAppState.forumWatchConfig.factionForumAutoMonitor)
        XCTAssertEqual(newAppState.forumWatchConfig.pollingIntervalSeconds, 300)
    }

    func testLoadForumWatch_emptyWhenNothingSaved() {
        testDefaults.removeObject(forKey: "forumWatchedThreads")
        testDefaults.removeObject(forKey: "forumWatchConfig")

        appState.loadForumWatch()

        XCTAssertTrue(appState.watchedThreads.isEmpty)
        XCTAssertFalse(appState.forumWatchConfig.factionForumAutoMonitor)
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
        XCTAssertEqual(thread?.error, "Too many requests",
                       "v2 forum error envelope must be surfaced, not parsed as an 'Unknown' thread")
        XCTAssertNotEqual(thread?.title, "Unknown",
                          "on a v2 error the thread title must not be corrupted to 'Unknown'")
    }
}
