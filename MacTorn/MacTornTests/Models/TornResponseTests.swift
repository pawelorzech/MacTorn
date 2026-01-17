import XCTest
@testable import MacTorn

final class TornResponseTests: XCTestCase {

    // MARK: - Full Decoding Tests

    func testDecoding_validFullResponse() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.name, "TestPlayer")
        XCTAssertEqual(response.playerId, 123456)
        XCTAssertNotNil(response.energy)
        XCTAssertNotNil(response.nerve)
        XCTAssertNotNil(response.life)
        XCTAssertNotNil(response.happy)
        XCTAssertNotNil(response.cooldowns)
        XCTAssertNotNil(response.travel)
        XCTAssertNotNil(response.status)
        XCTAssertNotNil(response.chain)
        XCTAssertNotNil(response.events)
        XCTAssertNotNil(response.messages)
        XCTAssertNil(response.error)
    }

    // MARK: - Bars Computed Property Tests

    func testBars_allBarsPresent() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        let bars = response.bars
        XCTAssertNotNil(bars)
        XCTAssertEqual(bars?.energy.current, 100)
        XCTAssertEqual(bars?.nerve.current, 50)
        XCTAssertEqual(bars?.life.current, 7500)
        XCTAssertEqual(bars?.happy.current, 5000)
    }

    func testBars_missingBar() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "player_id": 123456,
            "energy": TornAPIFixtures.energyFull,
            "nerve": TornAPIFixtures.energyHalf
            // Missing life and happy
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertNil(response.bars) // Should be nil because not all bars present
    }

    // MARK: - Unread Messages Count Tests

    func testUnreadMessagesCount_noMessages() throws {
        let json: [String: Any] = [
            "name": "TestPlayer"
            // No messages
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 0)
    }

    func testUnreadMessagesCount_allRead() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "messages": [
                "1": ["name": "Sender1", "read": 1],
                "2": ["name": "Sender2", "read": 1]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 0)
    }

    func testUnreadMessagesCount_someUnread() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "messages": [
                "1": ["name": "Sender1", "read": 0],
                "2": ["name": "Sender2", "read": 1],
                "3": ["name": "Sender3", "read": 0]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 2)
    }

    // MARK: - Recent Events Tests

    func testRecentEvents_noEvents() throws {
        let json: [String: Any] = [
            "name": "TestPlayer"
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertTrue(response.recentEvents.isEmpty)
    }

    func testRecentEvents_sortedByTimestamp() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "events": [
                "1": ["timestamp": 1000, "event": "Old event", "seen": 1],
                "2": ["timestamp": 3000, "event": "Newest event", "seen": 0],
                "3": ["timestamp": 2000, "event": "Middle event", "seen": 0]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        let events = response.recentEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].timestamp, 3000) // Newest first
        XCTAssertEqual(events[1].timestamp, 2000)
        XCTAssertEqual(events[2].timestamp, 1000) // Oldest last
    }

    // MARK: - Error Response Tests

    func testDecoding_errorResponse() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.tornErrorInvalidKey)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, 2)
        XCTAssertEqual(response.error?.error, "Incorrect Key")
    }

    // MARK: - TornEvent Tests

    func testTornEvent_cleanEvent() throws {
        let json: [String: Any] = [
            "timestamp": 1700000000,
            "event": "You received a message from <a href='profile.php?XID=12345'>SomePlayer</a>.",
            "seen": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try JSONDecoder().decode(TornEvent.self, from: data)

        XCTAssertEqual(event.cleanEvent, "You received a message from SomePlayer.")
    }

    func testTornEvent_date() throws {
        let json: [String: Any] = [
            "timestamp": 1700000000,
            "event": "Test event",
            "seen": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try JSONDecoder().decode(TornEvent.self, from: data)

        XCTAssertEqual(event.date, Date(timeIntervalSince1970: 1700000000))
    }

    // MARK: - TornMessage Tests

    func testTornMessage_decoding() throws {
        let json: [String: Any] = [
            "name": "TestSender",
            "type": "Private",
            "title": "Hello World",
            "timestamp": 1700000000,
            "read": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let message = try JSONDecoder().decode(TornMessage.self, from: data)

        XCTAssertEqual(message.name, "TestSender")
        XCTAssertEqual(message.type, "Private")
        XCTAssertEqual(message.title, "Hello World")
        XCTAssertEqual(message.timestamp, 1700000000)
        XCTAssertEqual(message.read, 0)
    }
}
