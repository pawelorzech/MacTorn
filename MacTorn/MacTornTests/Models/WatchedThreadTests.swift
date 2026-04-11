import XCTest
@testable import MacTorn

final class WatchedThreadTests: XCTestCase {

    // MARK: - Init Tests

    func testInit_defaults() {
        let thread = WatchedThread(id: 12345, title: "Test Thread")

        XCTAssertEqual(thread.id, 12345)
        XCTAssertEqual(thread.title, "Test Thread")
        XCTAssertTrue(thread.notificationsEnabled)
        XCTAssertEqual(thread.lastKnownPostCount, 0)
        XCTAssertNil(thread.lastChecked)
        XCTAssertNil(thread.error)
        XCTAssertFalse(thread.isFactionThread)
    }

    func testInit_factionThread() {
        let thread = WatchedThread(id: 99, title: "Faction Announcement", notificationsEnabled: true, lastKnownPostCount: 5, isFactionThread: true)

        XCTAssertTrue(thread.isFactionThread)
        XCTAssertEqual(thread.lastKnownPostCount, 5)
    }

    // MARK: - Encoding/Decoding Tests

    func testEncoding_roundTrip() throws {
        let original = WatchedThread(
            id: 12345,
            title: "Test Thread",
            notificationsEnabled: false,
            lastKnownPostCount: 42,
            lastChecked: Date(),
            error: nil,
            isFactionThread: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedThread.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.title, decoded.title)
        XCTAssertEqual(original.notificationsEnabled, decoded.notificationsEnabled)
        XCTAssertEqual(original.lastKnownPostCount, decoded.lastKnownPostCount)
        XCTAssertEqual(original.isFactionThread, decoded.isFactionThread)
    }

    func testDecoding_withError() throws {
        let json: [String: Any] = [
            "id": 12345,
            "title": "Error Thread",
            "notificationsEnabled": true,
            "lastKnownPostCount": 0,
            "isFactionThread": false,
            "error": "API Error"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let thread = try JSONDecoder().decode(WatchedThread.self, from: data)

        XCTAssertEqual(thread.error, "API Error")
    }

    // MARK: - ForumWatchConfig Tests

    func testForumWatchConfig_defaults() {
        let config = ForumWatchConfig()

        XCTAssertFalse(config.factionForumAutoMonitor)
        XCTAssertNil(config.factionForumCategoryId)
        XCTAssertEqual(config.pollingIntervalSeconds, 180)
        XCTAssertTrue(config.knownFactionThreadIds.isEmpty)
    }

    func testForumWatchConfig_roundTrip() throws {
        var original = ForumWatchConfig()
        original.factionForumAutoMonitor = true
        original.factionForumCategoryId = 42
        original.pollingIntervalSeconds = 300
        original.knownFactionThreadIds = [100, 200, 300]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ForumWatchConfig.self, from: data)

        XCTAssertEqual(decoded.factionForumAutoMonitor, true)
        XCTAssertEqual(decoded.factionForumCategoryId, 42)
        XCTAssertEqual(decoded.pollingIntervalSeconds, 300)
        XCTAssertEqual(decoded.knownFactionThreadIds, [100, 200, 300])
    }

    // MARK: - Identifiable

    func testIdentifiable() {
        let thread = WatchedThread(id: 789, title: "ID Test")
        XCTAssertEqual(thread.id, 789)
    }
}
