import XCTest
@testable import MacTorn

/// Watching a forum category for new threads.
///
/// The behaviour worth guarding hardest is the first check: a category holds up to a
/// hundred threads, so a naive "anything not in the seen-set is new" would greet anyone
/// switching the feature on with a hundred notifications about months-old conversations.
@MainActor
final class ForumCategoryWatchTests: XCTestCase {

    private func makeService() -> ForumWatchService {
        ForumWatchService(defaults: UserDefaults.createMockDefaults(), session: MockNetworkSession())
    }

    private func threads(_ ids: [Int]) -> [ForumCategoryThread] {
        ids.map { ForumCategoryThread(id: $0, title: "Thread \($0)") }
    }

    // MARK: - Seeding

    func testTheFirstListingIsLearnedNotAnnounced() {
        let service = makeService()
        XCTAssertTrue(service.applyCategory(threads([1, 2, 3])).isEmpty,
                      "switching the watch on must not announce the existing backlog")
        XCTAssertEqual(service.config.knownFactionThreadIds, [1, 2, 3])
    }

    func testAnEmptyFirstListingStillCountsAsSeeded() {
        let service = makeService()
        XCTAssertTrue(service.applyCategory([]).isEmpty)
        // A category that was empty and then gets its first thread should announce it.
        XCTAssertEqual(service.applyCategory(threads([7])).map(\.id), [7])
    }

    // MARK: - Diffing

    func testOnlyUnseenThreadsAreAnnounced() {
        let service = makeService()
        _ = service.applyCategory(threads([1, 2]))
        let new = service.applyCategory(threads([1, 2, 3, 4]))
        XCTAssertEqual(Set(new.map(\.id)), [3, 4])
    }

    func testTheSameThreadIsAnnouncedOnlyOnce() {
        let service = makeService()
        _ = service.applyCategory(threads([1]))
        XCTAssertEqual(service.applyCategory(threads([1, 2])).map(\.id), [2])
        XCTAssertTrue(service.applyCategory(threads([1, 2])).isEmpty)
    }

    /// A thread dropping off the listing (page turnover, deletion) is not news, and must
    /// not make the threads still on the page look new next time.
    func testThreadsFallingOffTheListingAreForgottenQuietly() {
        let service = makeService()
        _ = service.applyCategory(threads([1, 2, 3]))
        XCTAssertTrue(service.applyCategory(threads([2, 3])).isEmpty)
        XCTAssertEqual(service.config.knownFactionThreadIds, [2, 3])
        XCTAssertTrue(service.applyCategory(threads([2, 3])).isEmpty)
    }

    func testAnnouncedThreadsCarryTheirTitle() {
        let service = makeService()
        _ = service.applyCategory(threads([1]))
        let new = service.applyCategory([
            ForumCategoryThread(id: 1, title: "Thread 1"),
            ForumCategoryThread(id: 99, title: "Raid tonight"),
        ])
        XCTAssertEqual(new.map(\.title), ["Raid tonight"])
    }

    // MARK: - Persistence

    /// A config written by a build that predates the seeded flag must keep its settings,
    /// and must be treated as already seeded when it carries ids.
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
        XCTAssertEqual(config.pollingIntervalSeconds, 300)
        XCTAssertTrue(config.hasSeededFactionThreads,
                      "a config that already knows thread ids was seeded by an older build")
    }

    func testSeenThreadsSurviveARestart() {
        let defaults = UserDefaults.createMockDefaults()
        let first = ForumWatchService(defaults: defaults, session: MockNetworkSession())
        _ = first.applyCategory(threads([1, 2]))

        let second = ForumWatchService(defaults: defaults, session: MockNetworkSession())
        second.load()
        XCTAssertEqual(second.config.knownFactionThreadIds, [1, 2])
        XCTAssertEqual(second.applyCategory(threads([1, 2, 3])).map(\.id), [3],
                       "a restart must not re-announce the whole category")
    }

    // MARK: - Decoding

    private func respond(_ object: [String: Any], statusCode: Int = 200) throws -> ForumWatchService {
        let session = MockNetworkSession()
        try session.setSuccessResponse(json: object)
        if statusCode != 200 {
            session.mockResponse = HTTPURLResponse(url: url(), statusCode: statusCode,
                                                   httpVersion: nil, headerFields: nil)
        }
        return ForumWatchService(defaults: UserDefaults.createMockDefaults(), session: session)
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

    func testAnErrorEnvelopeIsClassifiedNotTreatedAsAnEmptyCategory() async throws {
        let service = try respond(["code": 5, "error": "Too many requests"])
        guard case .apiError(let error, _) = try await service.fetchCategoryThreads(from: url()) else {
            return XCTFail("expected an API error")
        }
        XCTAssertEqual(error.classification, .rateLimit)
    }

    /// Reading a missing `threads` array as "no threads" would wipe the seen-set and then
    /// re-announce the whole category on the next successful call.
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
