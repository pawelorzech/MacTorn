import XCTest
@testable import MacTorn

/// Watching a forum category for new threads.
///
/// Two behaviours carry the weight here, and the first version of this suite got the
/// second one backwards.
///
/// The first check must be silent: the seen list starts empty, so treating "not in the
/// list" as "new" would greet anyone switching the feature on with a page of
/// notifications about months-old conversations.
///
/// And the seen list must be cumulative. Torn returns one capped page, not the category,
/// so replacing the list with each page made it a sliding window: a thread that scrolled
/// past the cut was forgotten, and the next reply that bumped it back to the top was
/// announced as new. In an activity-ordered listing that is the steady state.
@MainActor
final class ForumCategoryWatchTests: XCTestCase {

    private let category = 4

    private func makeService(watching categoryID: Int? = 4) -> ForumWatchService {
        let service = ForumWatchService(defaults: UserDefaults.createMockDefaults(),
                                        session: MockNetworkSession())
        service.config.factionForumCategoryId = categoryID
        return service
    }

    private func threads(_ ids: [Int]) -> [ForumCategoryThread] {
        ids.map { ForumCategoryThread(id: $0, title: "Thread \($0)") }
    }

    @discardableResult
    private func apply(_ service: ForumWatchService,
                       _ ids: [Int],
                       category: Int? = nil) -> [ForumCategoryThread] {
        service.applyCategory(threads(ids), for: category ?? self.category)
    }

    // MARK: - Seeding

    func testTheFirstListingIsLearnedNotAnnounced() {
        let service = makeService()
        XCTAssertTrue(apply(service, [1, 2, 3]).isEmpty,
                      "switching the watch on must not announce the existing backlog")
        XCTAssertEqual(Set(service.config.seenFactionThreadIds), [1, 2, 3])
        XCTAssertEqual(service.config.seededCategoryId, category)
    }

    func testAnEmptyFirstListingStillCountsAsSeeded() {
        let service = makeService()
        XCTAssertTrue(apply(service, []).isEmpty)
        XCTAssertEqual(apply(service, [7]).map(\.id), [7],
                       "the first thread in a quiet category is the one most worth hearing about")
    }

    // MARK: - Diffing

    func testOnlyUnseenThreadsAreAnnounced() {
        let service = makeService()
        apply(service, [1, 2])
        XCTAssertEqual(Set(apply(service, [1, 2, 3, 4]).map(\.id)), [3, 4])
    }

    func testTheSameThreadIsAnnouncedOnlyOnce() {
        let service = makeService()
        apply(service, [1])
        XCTAssertEqual(apply(service, [1, 2]).map(\.id), [2])
        XCTAssertTrue(apply(service, [1, 2]).isEmpty)
    }

    /// The regression this suite previously asserted the wrong way round. A thread
    /// dropping off a capped page has not gone away, and the reply that bumps it back is
    /// not news.
    func testAThreadThatScrollsOffAndComesBackIsNotAnnouncedAgain() {
        let service = makeService()
        apply(service, [1, 2, 3])

        XCTAssertTrue(apply(service, [2, 3]).isEmpty, "losing a row is not an event")
        XCTAssertTrue(apply(service, [1, 2, 3]).isEmpty,
                      "thread 1 was seen three polls ago and must stay seen")
    }

    func testAnnouncedThreadsCarryTheirTitle() {
        let service = makeService()
        apply(service, [1])
        let new = service.applyCategory([
            ForumCategoryThread(id: 1, title: "Thread 1"),
            ForumCategoryThread(id: 99, title: "Raid tonight"),
        ], for: category)
        XCTAssertEqual(new.map(\.title), ["Raid tonight"])
    }

    // MARK: - Bounds

    func testTheSeenListIsBoundedAndEvictsTheLeastRecentlySeen() {
        let service = makeService()
        let cap = ForumWatchConfig.maximumSeenThreadIds
        apply(service, Array(1...20))
        var newest = 0
        for start in stride(from: 21, through: cap + 200, by: 20) {
            apply(service, Array(start..<(start + 20)))
            newest = start + 19
        }

        XCTAssertLessThanOrEqual(service.config.seenFactionThreadIds.count, cap)
        XCTAssertTrue(service.config.seenFactionThreadIds.contains(newest),
                      "the most recently seen ids must survive eviction")
    }

    // MARK: - Category identity

    /// A listing already in flight when the user changes the category describes a category
    /// nobody is watching. Writing its ids under the new category's seed made the next poll
    /// announce a whole page of old threads.
    func testAListingForAnotherCategoryIsDiscarded() {
        let service = makeService(watching: 7)
        XCTAssertTrue(service.applyCategory(threads([1, 2, 3]), for: 4).isEmpty)
        XCTAssertTrue(service.config.seenFactionThreadIds.isEmpty,
                      "category 4's ids must not be stored against category 7")
        XCTAssertFalse(service.config.hasSeededFactionThreads)
        XCTAssertNil(service.config.seededCategoryId)
    }

    func testPointingTheWatchAtANewCategorySeedsAgainRatherThanAnnouncing() {
        let service = makeService()
        apply(service, [1, 2, 3])

        service.config.factionForumCategoryId = 7
        XCTAssertTrue(apply(service, [10, 11], category: 7).isEmpty,
                      "a different category starts over instead of announcing its backlog")
        XCTAssertEqual(service.config.seededCategoryId, 7)
        XCTAssertEqual(apply(service, [10, 11, 12], category: 7).map(\.id), [12])
    }

    func testForgetSeenThreadsClearsEverySeedingField() {
        let service = makeService()
        apply(service, [1, 2, 3])
        service.config.forgetSeenThreads()

        XCTAssertTrue(service.config.seenFactionThreadIds.isEmpty)
        XCTAssertNil(service.config.seededCategoryId)
        XCTAssertFalse(service.config.hasSeededFactionThreads)
    }

    // MARK: - Persistence and migration

    func testSeenThreadsSurviveARestart() {
        let defaults = UserDefaults.createMockDefaults()
        let first = ForumWatchService(defaults: defaults, session: MockNetworkSession())
        first.config.factionForumCategoryId = category
        first.applyCategory(threads([1, 2]), for: category)

        let second = ForumWatchService(defaults: defaults, session: MockNetworkSession())
        second.load()
        XCTAssertEqual(Set(second.config.seenFactionThreadIds), [1, 2])
        XCTAssertEqual(second.applyCategory(threads([1, 2, 3]), for: category).map(\.id), [3],
                       "a restart must not re-announce the whole category")
    }

    /// A config written by 1.12.0 or 1.12.1 stored an unordered `Set` under a different
    /// key. Those installs must not re-announce their category after upgrading.
    func testAConfigFromTheSetEraMigratesWithoutReannouncing() throws {
        let legacy: [String: Any] = [
            "factionForumAutoMonitor": true,
            "factionForumCategoryId": 4,
            "pollingIntervalSeconds": 300,
            "knownFactionThreadIds": [1, 2, 3],
            "hasSeededFactionThreads": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let config = try JSONDecoder().decode(ForumWatchConfig.self, from: data)

        XCTAssertEqual(Set(config.seenFactionThreadIds), [1, 2, 3])
        XCTAssertEqual(config.seededCategoryId, 4, "the ids belong to the watched category")
        XCTAssertTrue(config.hasSeededFactionThreads)
        XCTAssertEqual(config.pollingIntervalSeconds, 300)
        XCTAssertTrue(config.factionForumAutoMonitor)
    }

    /// The pre-`hasSeededFactionThreads` shape, from before 1.12.0.
    func testAnOlderConfigWithoutTheSeededFlagStillLoads() throws {
        let legacy: [String: Any] = [
            "factionForumAutoMonitor": true,
            "factionForumCategoryId": 4,
            "pollingIntervalSeconds": 300,
            "knownFactionThreadIds": [1, 2],
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let config = try JSONDecoder().decode(ForumWatchConfig.self, from: data)

        XCTAssertTrue(config.factionForumAutoMonitor)
        XCTAssertEqual(config.factionForumCategoryId, 4)
        XCTAssertTrue(config.hasSeededFactionThreads,
                      "a config that already knows thread ids was seeded by an older build")
    }

    func testAFreshConfigIsNotSeeded() throws {
        let data = try JSONSerialization.data(withJSONObject: ["pollingIntervalSeconds": 180])
        let config = try JSONDecoder().decode(ForumWatchConfig.self, from: data)
        XCTAssertFalse(config.hasSeededFactionThreads)
        XCTAssertNil(config.seededCategoryId)
        XCTAssertTrue(config.seenFactionThreadIds.isEmpty)
    }

    func testRoundTripsThroughItsOwnEncoder() throws {
        var config = ForumWatchConfig(factionForumAutoMonitor: true,
                                      factionForumCategoryId: 4,
                                      pollingIntervalSeconds: 300)
        config.seenFactionThreadIds = [3, 2, 1]
        config.seededCategoryId = 4
        config.hasSeededFactionThreads = true

        let decoded = try JSONDecoder().decode(ForumWatchConfig.self,
                                               from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.seenFactionThreadIds, [3, 2, 1], "order is meaningful")
        XCTAssertEqual(decoded.seededCategoryId, 4)
        XCTAssertTrue(decoded.hasSeededFactionThreads)
        XCTAssertEqual(decoded.pollingIntervalSeconds, 300)
    }

    // MARK: - Decoding

    private func respond(_ object: [String: Any], statusCode: Int = 200) throws -> ForumWatchService {
        let session = MockNetworkSession()
        try session.setSuccessResponse(json: object)
        if statusCode != 200 {
            session.mockResponse = HTTPURLResponse(url: url(), statusCode: statusCode,
                                                   httpVersion: nil, headerFields: nil)
        }
        let service = ForumWatchService(defaults: UserDefaults.createMockDefaults(), session: session)
        service.config.factionForumCategoryId = category
        return service
    }

    private func url() -> URL { URL(string: "https://api.torn.com/v2/forum/4/threads")! }

    func testDecodesTheSpecShape() async throws {
        let service = try respond(["threads": [
            ["id": 16_532_308, "title": "Raid tonight", "posts": 12],
            ["id": 16_532_309, "title": "Recruitment", "posts": 3],
        ]])
        guard case .success(let threads, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(threads.map(\.id), [16_532_308, 16_532_309])
        XCTAssertEqual(threads.first?.title, "Raid tonight")
    }

    func testOneUnusableRowDoesNotCostTheRestOfTheListing() async throws {
        let service = try respond(["threads": [
            ["title": "No id"],
            ["id": 5, "title": "Fine"],
            ["id": 6],
        ]])
        guard case .success(let threads, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(threads.map(\.id), [5, 6])
        XCTAssertEqual(threads.last?.title, "Untitled thread",
                       "a thread with no title is still trackable")
    }

    /// Titles reach the persisted `forumWatchedThreads` blob, so they get the same cap a
    /// typed watchlist name does.
    func testTitlesAreCappedBeforeTheyCanBePersisted() async throws {
        let service = try respond(["threads": [["id": 1,
                                                "title": String(repeating: "A", count: 10_000)]]])
        guard case .success(let threads, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(threads.first?.title.count, WatchlistItem.maximumNameLength)
    }

    func testAnErrorEnvelopeIsClassifiedNotTreatedAsAnEmptyCategory() async throws {
        let service = try respond(["code": 5, "error": "Too many requests"])
        guard case .apiError(let error, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected an API error")
        }
        XCTAssertEqual(error.classification, .rateLimit)
    }

    /// Reading a missing `threads` array as "no threads" would seed an empty set and then
    /// announce the whole category on the next successful call.
    func testAMissingThreadsArrayIsMalformedNotEmpty() async throws {
        let service = try respond(["unexpected": true])
        guard case .malformed = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected malformed")
        }
    }

    func testNon200IsReportedAsAnHTTPError() async throws {
        let service = try respond(["threads": []], statusCode: 503)
        guard case .httpError(let statusCode, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected an HTTP error")
        }
        XCTAssertEqual(statusCode, 503)
    }
}
