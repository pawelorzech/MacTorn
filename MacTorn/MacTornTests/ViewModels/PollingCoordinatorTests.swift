import XCTest
@testable import MacTorn

/// Etap D — the request/record budget accounting, driven by a fake clock.
@MainActor
final class PollingCoordinatorTests: XCTestCase {

    private var clock: MutableTimeSource!
    private var coord: PollingCoordinator!

    private func endpoint(_ id: String) -> TornEndpoint {
        TornEndpointRegistry.endpoint(id: id)!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = MutableTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        coord = PollingCoordinator(time: clock, hardCapPerMinute: 60, softTargetPerMinute: 15)
    }

    // MARK: Request counting

    func testRecordsCountRequestsInLastMinute() {
        for _ in 0..<5 { coord.record(endpoint("user.fast")) }
        XCTAssertEqual(coord.requestsInLastMinute, 5)
        XCTAssertEqual(coord.requestsInLastDay, 5)
    }

    func testRequestsRollOffAfterAMinute() {
        for _ in 0..<3 { coord.record(endpoint("user.fast")) }
        clock.advance(61)
        XCTAssertEqual(coord.requestsInLastMinute, 0, "older than 60s should roll off the minute window")
        XCTAssertEqual(coord.requestsInLastDay, 3, "but still within the day window")
    }

    func testRequestsRollOffAfterADay() {
        for _ in 0..<3 { coord.record(endpoint("user.fast")) }
        clock.advance(24 * 60 * 60 + 1)
        XCTAssertEqual(coord.requestsInLastDay, 0)
    }

    // MARK: Hard cap gate

    func testCanMakeRequestUntilHardCap() {
        for _ in 0..<59 { coord.record(endpoint("user.fast")) }
        XCTAssertTrue(coord.canMakeRequest(), "59 < 60 cap")
        coord.record(endpoint("user.fast")) // 60th within the minute
        XCTAssertFalse(coord.canMakeRequest(), "at the cap, no more requests this minute")
        clock.advance(61)
        XCTAssertTrue(coord.canMakeRequest(), "cap frees up as the window slides")
    }

    // MARK: Record (row) budget per category

    func testRowBasedEndpointAccumulatesRecordsInItsCategory() {
        coord.record(endpoint("user.activity")) // row-based, 25 rows, activity
        coord.record(endpoint("user.activity"))
        XCTAssertEqual(coord.recordsInLastDay(.activity), 50)
    }

    func testPointInTimeEndpointRecordsNoRows() {
        coord.record(endpoint("user.fast")) // point-in-time
        XCTAssertEqual(coord.recordsInLastDay(.core), 0)
        XCTAssertEqual(coord.requestsInLastDay, 1, "still counts as a request")
    }

    func testRecordsAreKeyedByCategory() {
        coord.record(endpoint("user.activity"))   // activity, 25
        coord.record(endpoint("faction.news"))    // faction, 25
        XCTAssertEqual(coord.recordsInLastDay(.activity), 25)
        XCTAssertEqual(coord.recordsInLastDay(.faction), 25)
        XCTAssertEqual(coord.recordsInLastDay(.forum), 0)
    }

    func testRecordsPerDayByCategoryOnlyReportsTraffic() {
        coord.record(endpoint("user.activity"))
        let byCat = coord.recordsPerDayByCategory()
        XCTAssertEqual(byCat[.activity], 25)
        XCTAssertNil(byCat[.forum], "categories with no traffic are omitted")
    }

    func testRecordsRollOffAfterADay() {
        coord.record(endpoint("user.activity"))
        clock.advance(24 * 60 * 60 + 1)
        XCTAssertEqual(coord.recordsInLastDay(.activity), 0)
    }

    // MARK: Budget headroom

    func testWithinRecordBudget() {
        let coordTight = PollingCoordinator(time: clock, recordBudgetPerDayPerCategory: 40)
        coordTight.record(endpoint("user.activity")) // 25
        XCTAssertTrue(coordTight.isWithinRecordBudget(.activity), "25 < 40")
        coordTight.record(endpoint("user.activity")) // 50
        XCTAssertFalse(coordTight.isWithinRecordBudget(.activity), "50 >= 40")
    }

    /// The real cadence stays far under budget: point-in-time endpoints every 30s is
    /// ~2/min, nowhere near the 60/min hard cap or the 15/min soft target.
    func testRealisticCadenceStaysUnderSoftTarget() {
        // Simulate one fast-poll cycle (user.fast + user.v2 + faction.basic) at t=0.
        for id in ["user.fast", "user.v2", "faction.basic"] { coord.record(endpoint(id)) }
        XCTAssertLessThan(coord.requestsInLastMinute, coord.softTargetPerMinute)
    }
}
