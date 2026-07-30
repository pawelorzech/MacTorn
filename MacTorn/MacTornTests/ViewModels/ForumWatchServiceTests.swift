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
