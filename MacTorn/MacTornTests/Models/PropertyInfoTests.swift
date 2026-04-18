import XCTest
@testable import MacTorn

final class PropertyInfoTests: XCTestCase {

    // Real Torn API shape for user/?selections=properties (verified 2026-04-18 against
    // bombel's Private Island). `status` indicates residency, `cost`/`marketprice` are
    // unconditional, `rented` is null OR an object with days_left when rented OUT to
    // another player. We deliberately ignore `upkeep`/`staff_cost` because they're
    // per-day rates only paid when residing — too easy to mistake for current debt.
    func testPropertyInfo_decodesStatusCostMarketpriceHappy() throws {
        let json: [String: Any] = [
            "property_id": 5678137,
            "property": "Private Island",
            "status": "Owned by them",
            "cost": 500_000_000,
            "marketprice": 1_057_788_000,
            "happy": 4525,
            "upkeep": 100_000,        // present in API; we deliberately don't surface it
            "staff_cost": 252_500,
            "rented": NSNull()
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let property = try JSONDecoder().decode(PropertyInfo.self, from: data)

        XCTAssertEqual(property.id, 5678137)
        XCTAssertEqual(property.propertyType, "Private Island")
        XCTAssertEqual(property.status, "Owned by them")
        XCTAssertEqual(property.cost, 500_000_000)
        XCTAssertEqual(property.marketprice, 1_057_788_000)
        XCTAssertEqual(property.happy, 4525)
        XCTAssertFalse(property.rented)
        XCTAssertNil(property.rentDaysLeft)
    }

    func testPropertyInfo_decodesRentedObjectWithDaysLeft() throws {
        let json: [String: Any] = [
            "property_id": 67890,
            "property": "Mansion",
            "cost": 50_000_000,
            "marketprice": 75_000_000,
            "upkeep": 500_000,
            "rented": [
                "user_id": 999,
                "days_left": 14,
                "cost_per_day": 1_000_000
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let property = try JSONDecoder().decode(PropertyInfo.self, from: data)

        XCTAssertTrue(property.rented)
        XCTAssertEqual(property.rentDaysLeft, 14)
    }

    func testPropertyInfo_missingFieldsDefaultToZero() throws {
        let json: [String: Any] = [
            "property_id": 1,
            "property": "House"
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let property = try JSONDecoder().decode(PropertyInfo.self, from: data)

        XCTAssertEqual(property.cost, 0)
        XCTAssertEqual(property.marketprice, 0)
        XCTAssertEqual(property.happy, 0)
        XCTAssertEqual(property.status, "")
        XCTAssertFalse(property.rented)
    }
}
