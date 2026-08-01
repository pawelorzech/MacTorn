import XCTest
@testable import MacTorn

@MainActor
final class ForumWatchServiceTests: XCTestCase {
    func testOwnsParsingStateConfigAndPersistence() throws {
        let defaults = UserDefaults.createMockDefaults()
        let service = ForumWatchService(
            defaults: defaults,
            session: MockNetworkSession()
        )

        XCTAssertEqual(service.parseThreadInput(" 12345 "), 12345)
        XCTAssertEqual(
            service.parseThreadInput("https://www.torn.com/forums.php#/p=threads&t=16532308"),
            16_532_308
        )
        XCTAssertNil(service.parseThreadInput("invalid"))
        XCTAssertEqual(service.add(input: "12345"), 12345)
        XCTAssertNil(service.add(input: "12345"))
        service.config.pollingIntervalSeconds = 300
        service.save()

        let reloaded = ForumWatchService(
            defaults: defaults,
            session: MockNetworkSession()
        )
        reloaded.load()
        XCTAssertEqual(reloaded.threads.map(\.id), [12345])
        XCTAssertEqual(reloaded.config.pollingIntervalSeconds, 300)
    }

    func testLoadNormalizesUnsafePollingInterval() throws {
        let defaults = UserDefaults.createMockDefaults()
        defaults.set(
            try JSONEncoder().encode(ForumWatchConfig(pollingIntervalSeconds: 0)),
            forKey: "forumWatchConfig"
        )
        let service = ForumWatchService(
            defaults: defaults,
            session: MockNetworkSession()
        )

        service.load()

        XCTAssertEqual(service.config.pollingIntervalSeconds, 180)
    }

    func testRestoreToggleAndMarkReadMutateOwnedState() {
        let service = ForumWatchService(
            defaults: .createMockDefaults(),
            session: MockNetworkSession()
        )
        service.threads = [
            WatchedThread(id: 1, title: "One"),
            WatchedThread(id: 3, title: "Three")
        ]
        let restored = WatchedThread(
            id: 2,
            title: "Two",
            notificationsEnabled: true,
            lastKnownPostCount: 12,
            error: "old"
        )

        XCTAssertTrue(service.restore(restored, at: 1))
        service.toggleNotifications(threadID: 2)
        service.markAsRead(threadID: 2)

        XCTAssertEqual(service.threads.map(\.id), [1, 2, 3])
        XCTAssertFalse(service.threads[1].notificationsEnabled)
        XCTAssertNil(service.threads[1].error)
        XCTAssertFalse(service.restore(restored, at: 0))
    }

    func testApplyUpdatesThreadAndReturnsOnlyEnabledPostIncrease() {
        let service = ForumWatchService(
            defaults: .createMockDefaults(),
            session: MockNetworkSession()
        )
        service.threads = [
            WatchedThread(
                id: 123,
                title: "Old",
                notificationsEnabled: true,
                lastKnownPostCount: 40,
                error: "old"
            )
        ]

        let update = service.apply(
            ForumThreadSnapshot(title: "Updated", postCount: 43),
            to: 123
        )
        let unchanged = service.apply(
            ForumThreadSnapshot(title: "Updated", postCount: 43),
            to: 123
        )

        XCTAssertEqual(
            update,
            ForumNewPosts(threadID: 123, title: "Updated", count: 3)
        )
        XCTAssertNil(unchanged)
        XCTAssertEqual(service.threads[0].lastKnownPostCount, 43)
        XCTAssertNil(service.threads[0].error)
    }

    func testFetchThreadDecodesNestedPayload() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: TornAPIFixtures.forumThreadSuccess)
        let service = ForumWatchService(
            defaults: .createMockDefaults(),
            session: mock
        )

        let result = try await service.fetchThread(
            from: URL(string: "https://api.torn.com/v2/forum/12345/thread")!
        )

        guard case .success(let snapshot, _) = result else {
            return XCTFail("Expected thread payload")
        }
        XCTAssertEqual(snapshot.title, "Test Forum Thread")
        XCTAssertEqual(snapshot.postCount, 42)
    }

    func testFetchThreadSurfacesV2APIError() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIErrorV2(code: 5, message: "Too many requests")
        let service = ForumWatchService(
            defaults: .createMockDefaults(),
            session: mock
        )

        let result = try await service.fetchThread(
            from: URL(string: "https://api.torn.com/v2/forum/12345/thread")!
        )

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected API error")
        }
        XCTAssertEqual(error.userMessage, "Too many requests — backing off.")
    }
}

// MARK: - Corrupted store + partial responses (audit 2026-08-01, D-01 / D-02)

@MainActor
final class ForumWatchResilienceTests: XCTestCase {

    private func makeService(_ defaults: UserDefaults) -> ForumWatchService {
        ForumWatchService(defaults: defaults, session: MockNetworkSession())
    }

    func testUnreadableThreadBlobIsNotOverwritten() {
        let defaults = UserDefaults.createMockDefaults()
        let corrupt = Data("]]not json[[".utf8)
        defaults.set(corrupt, forKey: "forumWatchedThreads")

        let service = makeService(defaults)
        service.load()
        service.save()   // the forum poll saves on its own schedule

        XCTAssertEqual(defaults.data(forKey: "forumWatchedThreads"), corrupt)
        XCTAssertEqual(defaults.data(forKey: "forumWatchedThreads.unreadable"), corrupt)
    }

    func testConfigStillPersistsWhileThreadBlobIsUnreadable() throws {
        let defaults = UserDefaults.createMockDefaults()
        defaults.set(Data("]]not json[[".utf8), forKey: "forumWatchedThreads")

        let service = makeService(defaults)
        service.load()
        service.config.pollingIntervalSeconds = 300
        service.save()

        let reloaded = makeService(defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.config.pollingIntervalSeconds, 300,
                       "a regenerable preference is not blocked by the thread guard")
    }

    func testAddingAThreadResumesPersistence() {
        let defaults = UserDefaults.createMockDefaults()
        defaults.set(Data("]]not json[[".utf8), forKey: "forumWatchedThreads")

        let service = makeService(defaults)
        service.load()
        XCTAssertEqual(service.add(input: "12345"), 12345)

        let reloaded = makeService(defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.threads.map(\.id), [12345])
    }

    // D-02: a response carrying a title but no post count used to be accepted as a
    // success with `postCount: 0`. That zero was written to `lastKnownPostCount`, and
    // the `previousCount > 0` guard in `apply` then swallowed the next genuine increase
    // — the "new posts" alert was lost permanently and the counter silently jumped.
    func testApplyStillDetectsNewPostsAfterAPartialResponse() {
        let service = makeService(.createMockDefaults())
        _ = service.add(input: "12345")

        XCTAssertNil(service.apply(ForumThreadSnapshot(title: "Thread", postCount: 340),
                                   to: 12345),
                     "first real reading only seeds the baseline")

        let alert = service.apply(ForumThreadSnapshot(title: "Thread", postCount: 345),
                                  to: 12345)
        XCTAssertEqual(alert?.count, 5, "a genuine increase must still alert")
    }

    func testZeroPostCountWouldDestroyTheBaseline() {
        // Pins why the parser must reject a missing post count: if a 0 ever reaches
        // `apply`, the next real reading is silently swallowed.
        let service = makeService(.createMockDefaults())
        _ = service.add(input: "12345")
        _ = service.apply(ForumThreadSnapshot(title: "Thread", postCount: 340), to: 12345)
        _ = service.apply(ForumThreadSnapshot(title: "Unknown", postCount: 0), to: 12345)

        XCTAssertNil(service.apply(ForumThreadSnapshot(title: "Thread", postCount: 345),
                                   to: 12345),
                     "documents the damage a 0 does — the parser must never produce one")
    }
}

@MainActor
final class ForumThreadParseTests: XCTestCase {

    private func parse(_ json: [String: Any]) async throws -> ForumThreadResult {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: json)
        let service = ForumWatchService(defaults: .createMockDefaults(), session: mock)
        return try await service.fetchThread(
            from: URL(string: "https://api.torn.com/v2/forum/12345/thread")!
        )
    }

    func testResponseWithoutPostCountIsMalformedNotSuccess() async throws {
        let result = try await parse(["thread": ["title": "Test Forum Thread"]])
        guard case .malformed = result else {
            return XCTFail("a response with no usable post count must not count as success: \(result)")
        }
    }

    func testStringifiedPostCountIsTolerated() async throws {
        let result = try await parse(["thread": ["title": "Test", "posts": "42"]])
        guard case .success(let snapshot, _) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.postCount, 42)
    }

    func testEmptyTitleFallsBackWithoutLosingThePostCount() async throws {
        let result = try await parse(["thread": ["title": "", "posts": 7]])
        guard case .success(let snapshot, _) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.postCount, 7)
        XCTAssertEqual(snapshot.title, "Unknown")
    }
}
