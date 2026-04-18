import XCTest
import os.log
@testable import MacTorn

final class StockMetadataTests: XCTestCase {

    private let logger = Logger(subsystem: "com.mactorn.tests", category: "StockMetadataTests")

    // Real torn/?selections=stocks shape: dict keyed by stock_id, each entry has
    // name, acronym, current_price, plus extra fields (director, market_cap, benefit, etc.)
    // that the parser must tolerate without failing.
    func testParseStocksMetadata_extractsDictKeyedByStockId() throws {
        let json: [String: Any] = [
            "stocks": [
                "1": [
                    "stock_id": 1,
                    "name": "Torn City Stock Exchange",
                    "acronym": "TCSE",
                    "director": "Bruce Hunter",
                    "current_price": 1234.56,
                    "total_shares": 100_000_000,
                    "market_cap": 123_456_000_000,
                    "forecast": "Average",
                    "demand": "Low",
                    "benefit": ["requirement": 1000, "description": "..."]
                ],
                "16": [
                    "stock_id": 16,
                    "name": "Sym-Sym Pharmaceuticals",
                    "acronym": "SYS",
                    "current_price": 805.32
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = AppState.parseStocksMetadata(from: data, logger: logger)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1]?.acronym, "TCSE")
        XCTAssertEqual(result[1]?.name, "Torn City Stock Exchange")
        XCTAssertEqual(result[1]?.currentPrice ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(result[16]?.acronym, "SYS")
        XCTAssertEqual(result[16]?.id, 16)
    }

    func testParseStocksMetadata_returnsEmptyOnTornAPIError() throws {
        let json: [String: Any] = [
            "error": ["code": 7, "error": "Incorrect ID-entity relation"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = AppState.parseStocksMetadata(from: data, logger: logger)

        XCTAssertTrue(result.isEmpty)
    }

    func testParseStocksMetadata_handlesIntegerCurrentPrice() throws {
        let json: [String: Any] = [
            "stocks": [
                "5": ["name": "X", "acronym": "X", "current_price": 100]  // Int, not Double
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = AppState.parseStocksMetadata(from: data, logger: logger)

        XCTAssertEqual(result[5]?.currentPrice ?? 0, 100, accuracy: 0.001)
    }

    func testStockHolding_marketValue_usesCurrentPriceFromMetadata() {
        let stock = StockHolding(stockId: 16, totalShares: 1_500_000, transactions: nil)
        let metadata: [Int: StockMetadata] = [
            16: StockMetadata(id: 16, name: "Sym-Sym Pharmaceuticals", acronym: "SYS", currentPrice: 805.32)
        ]

        XCTAssertEqual(stock.marketValue(using: metadata), Int(1_500_000.0 * 805.32))
    }

    func testStockHolding_marketValue_returnsZeroWhenMetadataMissing() {
        let stock = StockHolding(stockId: 99, totalShares: 1_000, transactions: nil)
        XCTAssertEqual(stock.marketValue(using: [:]), 0)
    }

    func testStockMetadata_roundTripsThroughJSONEncoder() throws {
        let original = StockMetadata(id: 7, name: "Big Al's Gun Shop", acronym: "BAG", currentPrice: 42.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StockMetadata.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
