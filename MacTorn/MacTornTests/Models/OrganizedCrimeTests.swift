import XCTest
@testable import MacTorn

final class OrganizedCrimeTests: XCTestCase {

    func testOrganizedCrime_decodesFromJSON() throws {
        let json: [String: Any] = [
            "crime_id": 8,
            "crime_name": "Planned Robbery",
            "participants": [
                ["description": "Driver", "state": "Okay"],
                ["description": "Lookout", "state": "Okay"]
            ],
            "time_started": 1700000000,
            "time_ready": 1700086400,
            "time_left": 3600,
            "initiated": false,
            "planner_id": 12345,
            "planner_name": "TestPlayer"
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let oc = try JSONDecoder().decode(OrganizedCrime.self, from: data)

        XCTAssertEqual(oc.crimeId, 8)
        XCTAssertEqual(oc.crimeName, "Planned Robbery")
        XCTAssertEqual(oc.participants.count, 2)
        XCTAssertEqual(oc.timeStarted, 1700000000)
        XCTAssertEqual(oc.timeReady, 1700086400)
        XCTAssertEqual(oc.timeLeft, 3600)
        XCTAssertFalse(oc.initiated)
        XCTAssertEqual(oc.plannerName, "TestPlayer")
    }

    func testOrganizedCrime_isReady() {
        let oc = OrganizedCrime(
            crimeId: 8, crimeName: "Planned Robbery",
            participants: [], timeStarted: 1700000000,
            timeReady: 1700086400, timeLeft: 0,
            initiated: true, plannerId: 12345, plannerName: "Test"
        )
        XCTAssertTrue(oc.isReady)
    }

    func testOrganizedCrime_isNotReady_timeRemaining() {
        let oc = OrganizedCrime(
            crimeId: 8, crimeName: "Planned Robbery",
            participants: [], timeStarted: 1700000000,
            timeReady: 1700086400, timeLeft: 3600,
            initiated: false, plannerId: 12345, plannerName: "Test"
        )
        XCTAssertFalse(oc.isReady)
    }

    func testOrganizedCrime_isNotReady_notInitiated() {
        let oc = OrganizedCrime(
            crimeId: 8, crimeName: "Planned Robbery",
            participants: [], timeStarted: 1700000000,
            timeReady: 1700086400, timeLeft: 0,
            initiated: false, plannerId: 12345, plannerName: "Test"
        )
        XCTAssertFalse(oc.isReady)
    }
}
