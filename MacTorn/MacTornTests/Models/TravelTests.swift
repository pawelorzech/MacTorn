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
}
