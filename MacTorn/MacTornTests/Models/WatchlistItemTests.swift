import XCTest
@testable import MacTorn

final class WatchlistItemTests: XCTestCase {

    // MARK: - priceDifference Tests

    func testPriceDifference_normalCase() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 100)
    }

    func testPriceDifference_samePrices() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1000,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    func testPriceDifference_noSecondPrice() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 0,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    func testPriceDifference_noLowestPrice() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    // MARK: - isLoading Tests

    func testIsLoading_loading() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: nil
        )

        XCTAssertTrue(item.isLoading)
    }

    func testIsLoading_loaded() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertFalse(item.isLoading)
    }

    func testIsLoading_hasError() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: "No listings"
        )

        // Has error, so not loading
        XCTAssertFalse(item.isLoading)
    }

    // MARK: - Decoding Tests

    func testDecoding_fullItem() throws {
        let json: [String: Any] = [
            "id": 123,
            "name": "Xanax",
            "lowestPrice": 850000,
            "lowestPriceQuantity": 10,
            "secondLowestPrice": 860000,
            "lastUpdated": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.id, 123)
        XCTAssertEqual(item.name, "Xanax")
        XCTAssertEqual(item.lowestPrice, 850000)
        XCTAssertEqual(item.lowestPriceQuantity, 10)
        XCTAssertEqual(item.secondLowestPrice, 860000)
    }

    func testDecoding_legacyItemMissingFields() throws {
        // Legacy items might not have all fields
        let json: [String: Any] = [
            "id": 123,
            "name": "Xanax"
            // Missing price fields
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.id, 123)
        XCTAssertEqual(item.name, "Xanax")
        XCTAssertEqual(item.lowestPrice, 0) // Default
        XCTAssertEqual(item.lowestPriceQuantity, 0) // Default
        XCTAssertEqual(item.secondLowestPrice, 0) // Default
    }

    func testDecoding_withError() throws {
        let json: [String: Any] = [
            "id": 123,
            "name": "Invalid Item",
            "lowestPrice": 0,
            "lowestPriceQuantity": 0,
            "secondLowestPrice": 0,
            "error": "Item not found"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.error, "Item not found")
        XCTAssertFalse(item.isLoading)
    }

    // MARK: - Encoding Tests

    func testEncoding_roundTrip() throws {
        let original = WatchlistItem(
            id: 456,
            name: "Donator Pack",
            lowestPrice: 9500000,
            lowestPriceQuantity: 3,
            secondLowestPrice: 9600000,
            lastUpdated: Date(),
            error: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.lowestPrice, decoded.lowestPrice)
        XCTAssertEqual(original.lowestPriceQuantity, decoded.lowestPriceQuantity)
        XCTAssertEqual(original.secondLowestPrice, decoded.secondLowestPrice)
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let item = WatchlistItem(
            id: 789,
            name: "Test",
            lowestPrice: 100,
            lowestPriceQuantity: 1,
            secondLowestPrice: 200,
            lastUpdated: nil,
            error: nil
        )

        XCTAssertEqual(item.id, 789)
    }
}
