import XCTest
@testable import MacTorn

final class WatchlistPriceAlertTests: XCTestCase {

    // MARK: - Encode / Decode

    func testWatchlistItem_withThreshold_encodesAndDecodes() throws {
        let item = WatchlistItem(
            id: 123,
            name: "Xanax",
            lowestPrice: 900,
            lowestPriceQuantity: 5,
            secondLowestPrice: 950,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: 950
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(decoded.priceThreshold, 1000)
        XCTAssertEqual(decoded.lastAlertedPrice, 950)
        XCTAssertEqual(decoded.id, 123)
        XCTAssertEqual(decoded.name, "Xanax")
    }

    func testWatchlistItem_withoutThreshold_decodesFromLegacy() throws {
        // JSON without the new fields (legacy data)
        let legacyJSON = """
        {
            "id": 456,
            "name": "Vicodin",
            "lowestPrice": 800,
            "lowestPriceQuantity": 3,
            "secondLowestPrice": 850
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WatchlistItem.self, from: legacyJSON)

        XCTAssertEqual(decoded.id, 456)
        XCTAssertEqual(decoded.name, "Vicodin")
        XCTAssertNil(decoded.priceThreshold)
        XCTAssertNil(decoded.lastAlertedPrice)
    }

    // MARK: - shouldFirePriceAlert

    func testWatchlistItem_shouldAlert_priceDropsBelowThreshold() {
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 900,
            lowestPriceQuantity: 1,
            secondLowestPrice: 950,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: nil
        )

        XCTAssertTrue(item.shouldFirePriceAlert)
    }

    func testWatchlistItem_shouldNotAlert_priceAboveThreshold() {
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 1100,
            lowestPriceQuantity: 1,
            secondLowestPrice: 1200,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: nil
        )

        XCTAssertFalse(item.shouldFirePriceAlert)
    }

    func testWatchlistItem_shouldAlert_priceDropsFurther() {
        // lastAlertedPrice exists but current price dropped even lower
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 800,
            lowestPriceQuantity: 1,
            secondLowestPrice: 850,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: 900
        )

        XCTAssertTrue(item.shouldFirePriceAlert)
    }

    func testWatchlistItem_shouldNotAlert_priceNotDroppedFurtherSinceLastAlert() {
        // lowestPrice is below threshold but same as or above lastAlertedPrice → no new alert
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 900,
            lowestPriceQuantity: 1,
            secondLowestPrice: 950,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: 900
        )

        XCTAssertFalse(item.shouldFirePriceAlert)
    }

    func testWatchlistItem_shouldNotAlert_noThreshold() {
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 500,
            lowestPriceQuantity: 1,
            secondLowestPrice: 600,
            lastUpdated: nil,
            error: nil,
            priceThreshold: nil,
            lastAlertedPrice: nil
        )

        XCTAssertFalse(item.shouldFirePriceAlert)
    }

    func testWatchlistItem_shouldNotAlert_priceIsZero() {
        let item = WatchlistItem(
            id: 1,
            name: "Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 1000,
            lastAlertedPrice: nil
        )

        XCTAssertFalse(item.shouldFirePriceAlert)
    }
}
