import XCTest
@testable import MacTorn

final class TravelTests: XCTestCase {

    // MARK: - isAbroad Tests

    func testIsAbroad_inTorn() throws {
        let json = TornAPIFixtures.travelInTorn
        let travel = try decode(Travel.self, from: json)

        XCTAssertFalse(travel.isAbroad)
    }

    func testIsAbroad_abroadInMexico() throws {
        let json = TornAPIFixtures.travelAbroad
        let travel = try decode(Travel.self, from: json)

        XCTAssertTrue(travel.isAbroad)
    }

    func testIsAbroad_travelingToDestination() throws {
        let json = TornAPIFixtures.travelTraveling
        let travel = try decode(Travel.self, from: json)

        // Still traveling, not yet abroad
        XCTAssertFalse(travel.isAbroad)
    }

    // MARK: - isTraveling Tests

    func testIsTraveling_notTraveling() throws {
        let json = TornAPIFixtures.travelInTorn
        let travel = try decode(Travel.self, from: json)

        XCTAssertFalse(travel.isTraveling)
    }

    func testIsTraveling_traveling() throws {
        let json = TornAPIFixtures.travelTraveling
        let travel = try decode(Travel.self, from: json)

        XCTAssertTrue(travel.isTraveling)
    }

    func testIsTraveling_abroadNotTraveling() throws {
        let json = TornAPIFixtures.travelAbroad
        let travel = try decode(Travel.self, from: json)

        XCTAssertFalse(travel.isTraveling)
    }

    // MARK: - arrivalDate Tests

    func testArrivalDate_notTraveling() throws {
        let json = TornAPIFixtures.travelInTorn
        let travel = try decode(Travel.self, from: json)

        XCTAssertNil(travel.arrivalDate)
    }

    func testArrivalDate_traveling() throws {
        let json = TornAPIFixtures.travelTraveling
        let travel = try decode(Travel.self, from: json)

        XCTAssertNotNil(travel.arrivalDate)
        // Arrival should be in the future
        XCTAssertGreaterThan(travel.arrivalDate!, Date())
    }

    // MARK: - Decoding Tests

    func testDecoding_allFields() throws {
        let json: [String: Any] = [
            "destination": "Japan",
            "timestamp": 1700000000,
            "departed": 1699999000,
            "time_left": 1000
        ]
        let travel = try decode(Travel.self, from: json)

        XCTAssertEqual(travel.destination, "Japan")
        XCTAssertEqual(travel.timestamp, 1700000000)
        XCTAssertEqual(travel.departed, 1699999000)
        XCTAssertEqual(travel.timeLeft, 1000)
    }

    func testDecoding_nullFields() throws {
        let json: [String: Any?] = [
            "destination": nil,
            "timestamp": nil,
            "departed": nil,
            "time_left": nil
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let travel = try JSONDecoder().decode(Travel.self, from: data)

        XCTAssertNil(travel.destination)
        XCTAssertNil(travel.timestamp)
        XCTAssertNil(travel.departed)
        XCTAssertNil(travel.timeLeft)
    }

    // MARK: - Equatable Tests

    func testEquatable() throws {
        let json: [String: Any] = [
            "destination": "Mexico",
            "timestamp": 1000,
            "departed": 500,
            "time_left": 0
        ]
        let travel1 = try decode(Travel.self, from: json)
        let travel2 = try decode(Travel.self, from: json)
        XCTAssertEqual(travel1, travel2)
    }

    // MARK: - Edge Cases

    func testIsAbroad_nilDestination() throws {
        let json: [String: Any] = [
            "time_left": 0
        ]
        let travel = try decode(Travel.self, from: json)
        XCTAssertFalse(travel.isAbroad)
    }

    func testIsTraveling_nilTimeLeft() throws {
        let json: [String: Any] = [
            "destination": "Mexico"
        ]
        let travel = try decode(Travel.self, from: json)
        XCTAssertFalse(travel.isTraveling)
    }

    // MARK: - remainingSeconds Tests

    func testRemainingSeconds_usesTimestampDirectly() throws {
        // Set arrival time 60 seconds in the future
        let futureTimestamp = Int(Date().timeIntervalSince1970) + 60
        let json: [String: Any] = [
            "destination": "Japan",
            "timestamp": futureTimestamp,
            "departed": futureTimestamp - 1000,
            "time_left": 60
        ]
        let travel = try decode(Travel.self, from: json)

        // Even with a stale fetchTime, should use timestamp directly
        let staleFetchTime = Date().addingTimeInterval(-300) // 5 minutes ago
        let remaining = travel.remainingSeconds(from: staleFetchTime)

        // Should be approximately 60 seconds (allow 1-2 seconds tolerance for test execution)
        XCTAssertGreaterThanOrEqual(remaining, 58)
        XCTAssertLessThanOrEqual(remaining, 62)
    }

    func testRemainingSeconds_fallsBackToTimeLeftWhenTimestampNil() throws {
        let json: [String: Any] = [
            "destination": "Japan",
            "time_left": 120
        ]
        let travel = try decode(Travel.self, from: json)

        let fetchTime = Date()
        let remaining = travel.remainingSeconds(from: fetchTime)

        // Should use timeLeft since timestamp is nil
        XCTAssertGreaterThanOrEqual(remaining, 118)
        XCTAssertLessThanOrEqual(remaining, 120)
    }

    func testRemainingSeconds_fallsBackToTimeLeftWhenTimestampZero() throws {
        let json: [String: Any] = [
            "destination": "Japan",
            "timestamp": 0,
            "time_left": 90
        ]
        let travel = try decode(Travel.self, from: json)

        let fetchTime = Date()
        let remaining = travel.remainingSeconds(from: fetchTime)

        // Should use timeLeft since timestamp is 0
        XCTAssertGreaterThanOrEqual(remaining, 88)
        XCTAssertLessThanOrEqual(remaining, 90)
    }

    func testRemainingSeconds_returnsZeroWhenArrivalPassed() throws {
        // Set arrival time in the past
        let pastTimestamp = Int(Date().timeIntervalSince1970) - 60
        let json: [String: Any] = [
            "destination": "Japan",
            "timestamp": pastTimestamp,
            "departed": pastTimestamp - 1000,
            "time_left": 0
        ]
        let travel = try decode(Travel.self, from: json)

        let remaining = travel.remainingSeconds(from: Date())
        XCTAssertEqual(remaining, 0)
    }

    func testRemainingSeconds_consistentRegardlessOfFetchTime() throws {
        // Set arrival time 120 seconds in the future
        let futureTimestamp = Int(Date().timeIntervalSince1970) + 120
        let json: [String: Any] = [
            "destination": "Japan",
            "timestamp": futureTimestamp,
            "departed": futureTimestamp - 1000,
            "time_left": 120
        ]
        let travel = try decode(Travel.self, from: json)

        // Test with different fetchTimes - result should be the same
        let recentFetchTime = Date()
        let staleFetchTime = Date().addingTimeInterval(-60)
        let veryOldFetchTime = Date().addingTimeInterval(-600)

        let remaining1 = travel.remainingSeconds(from: recentFetchTime)
        let remaining2 = travel.remainingSeconds(from: staleFetchTime)
        let remaining3 = travel.remainingSeconds(from: veryOldFetchTime)

        // All should return approximately the same value (within 1 second tolerance)
        XCTAssertEqual(remaining1, remaining2, accuracy: 1)
        XCTAssertEqual(remaining2, remaining3, accuracy: 1)
    }

    func testRemainingSeconds_zeroWhenNotTraveling() throws {
        let json: [String: Any] = [
            "destination": "Torn",
            "time_left": 0
        ]
        let travel = try decode(Travel.self, from: json)

        let remaining = travel.remainingSeconds(from: Date())
        XCTAssertEqual(remaining, 0)
    }
}
