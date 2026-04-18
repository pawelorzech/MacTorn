import XCTest
@testable import MacTorn

final class StockMetadataTests: XCTestCase {

    // Real torn/?selections=stocks shape: dict keyed by stock_id, each entry has
    // name, acronym, current_price, total_shares, market_cap, etc.
    func testTornStocksResponse_decodesDictKeyedByStockId() throws {
        let json: [String: Any] = [
            "stocks": [
                "1": [
                    "name": "Torn City Stock Exchange",
                    "acronym": "TCSE",
                    "current_price": 1234.56,
                    "total_shares": 100_000_000,
                    "market_cap": 123_456_000_000
                ],
                "16": [
                    "name": "Sym-Sym Pharmaceuticals",
                    "acronym": "SYS",
                    "current_price": 805.32,
                    "total_shares": 5_000_000,
                    "market_cap": 4_026_600_000
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(TornStocksResponse.self, from: data)

        XCTAssertEqual(response.stocks.count, 2)
        XCTAssertEqual(response.stocks[1]?.acronym, "TCSE")
        XCTAssertEqual(response.stocks[1]?.name, "Torn City Stock Exchange")
        XCTAssertEqual(response.stocks[1]?.currentPrice ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(response.stocks[16]?.acronym, "SYS")
        XCTAssertEqual(response.stocks[16]?.id, 16)
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
