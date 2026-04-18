import XCTest
@testable import MacTorn

final class PropertyInfoTests: XCTestCase {

    // Real Torn API shape for user/?selections=properties — each property has
    // cost, marketprice, upkeep, and rented (null OR object with days_left).
    // The previous decoder mapped a non-existent `money` field, so vault was always 0.
    func testPropertyInfo_decodesCostMarketpriceUpkeep() throws {
        let json: [String: Any] = [
            "property_id": 12345,
            "property": "Private Island",
            "cost": 100_000_000,
            "marketprice": 250_000_000,
            "upkeep": 1_500_000,
            "rented": NSNull()
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let property = try JSONDecoder().decode(PropertyInfo.self, from: data)

        XCTAssertEqual(property.id, 12345)
        XCTAssertEqual(property.propertyType, "Private Island")
        XCTAssertEqual(property.cost, 100_000_000)
        XCTAssertEqual(property.marketprice, 250_000_000)
        XCTAssertEqual(property.upkeep, 1_500_000)
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
        XCTAssertEqual(property.upkeep, 0)
        XCTAssertFalse(property.rented)
    }
}
