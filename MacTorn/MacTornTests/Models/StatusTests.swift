import XCTest
@testable import MacTorn

final class StatusTests: XCTestCase {

    // MARK: - isOkay Tests

    func testIsOkay_stateOkay() throws {
        let json = TornAPIFixtures.statusOkay
        let status = try decode(Status.self, from: json)

        XCTAssertTrue(status.isOkay)
    }

    func testIsOkay_stateNil() throws {
        let json: [String: Any] = [:]
        let status = try decode(Status.self, from: json)
        XCTAssertTrue(status.isOkay)
    }

    func testIsOkay_inHospital() throws {
        let json = TornAPIFixtures.statusHospital
        let status = try decode(Status.self, from: json)

        XCTAssertFalse(status.isOkay)
    }

    func testIsOkay_inJail() throws {
        let json = TornAPIFixtures.statusJail
        let status = try decode(Status.self, from: json)

        XCTAssertFalse(status.isOkay)
    }

    // MARK: - isInHospital Tests

    func testIsInHospital_yes() throws {
        let json = TornAPIFixtures.statusHospital
        let status = try decode(Status.self, from: json)

        XCTAssertTrue(status.isInHospital)
        XCTAssertFalse(status.isInJail)
    }

    func testIsInHospital_no() throws {
        let json = TornAPIFixtures.statusOkay
        let status = try decode(Status.self, from: json)

        XCTAssertFalse(status.isInHospital)
    }

    // MARK: - isInJail Tests

    func testIsInJail_yes() throws {
        let json = TornAPIFixtures.statusJail
        let status = try decode(Status.self, from: json)

        XCTAssertTrue(status.isInJail)
        XCTAssertFalse(status.isInHospital)
    }

    func testIsInJail_no() throws {
        let json = TornAPIFixtures.statusOkay
        let status = try decode(Status.self, from: json)

        XCTAssertFalse(status.isInJail)
    }

    // MARK: - timeRemaining Tests

    func testTimeRemaining_noUntil() throws {
        let json: [String: Any] = [
            "description": "Okay",
            "state": "Okay"
        ]
        let status = try decode(Status.self, from: json)
        XCTAssertEqual(status.timeRemaining, 0)
    }

    func testTimeRemaining_untilInPast() throws {
        let pastTime = Int(Date().timeIntervalSince1970) - 1000
        let json: [String: Any] = [
            "description": "In hospital",
            "state": "Hospital",
            "until": pastTime
        ]
        let status = try decode(Status.self, from: json)
        XCTAssertEqual(status.timeRemaining, 0)
    }

    func testTimeRemaining_untilInFuture() throws {
        let futureTime = Int(Date().timeIntervalSince1970) + 1000
        let json: [String: Any] = [
            "description": "In hospital",
            "state": "Hospital",
            "until": futureTime
        ]
        let status = try decode(Status.self, from: json)

        // Should be approximately 1000, allow some tolerance for test execution time
        XCTAssertGreaterThan(status.timeRemaining, 900)
        XCTAssertLessThanOrEqual(status.timeRemaining, 1000)
    }

    // MARK: - Decoding Tests

    func testDecoding_fullStatus() throws {
        let json: [String: Any] = [
            "description": "In hospital for 30 minutes",
            "details": "Hospitalized by SomePlayer",
            "state": "Hospital",
            "until": 1700000000
        ]
        let status = try decode(Status.self, from: json)

        XCTAssertEqual(status.description, "In hospital for 30 minutes")
        XCTAssertEqual(status.details, "Hospitalized by SomePlayer")
        XCTAssertEqual(status.state, "Hospital")
        XCTAssertEqual(status.until, 1700000000)
    }

    // MARK: - Equatable Tests

    func testEquatable() throws {
        let json: [String: Any] = [
            "description": "Okay",
            "state": "Okay"
        ]
        let status1 = try decode(Status.self, from: json)
        let status2 = try decode(Status.self, from: json)
        XCTAssertEqual(status1, status2)
    }

    func testEquatable_different() throws {
        let json1: [String: Any] = [
            "description": "Okay",
            "state": "Okay"
        ]
        let json2: [String: Any] = [
            "description": "Hospital",
            "state": "Hospital",
            "until": 1000
        ]
        let status1 = try decode(Status.self, from: json1)
        let status2 = try decode(Status.self, from: json2)
        XCTAssertNotEqual(status1, status2)
    }
}
