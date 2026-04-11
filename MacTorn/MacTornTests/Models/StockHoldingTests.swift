import XCTest
@testable import MacTorn

final class StockHoldingTests: XCTestCase {

    func testStockHolding_decodesFromJSON() throws {
        let json: [String: Any] = [
            "stock_id": 1,
            "total_shares": 10000,
            "transactions": [
                ["shares": 5000, "bought_price": 500, "time_bought": 1700000000],
                ["shares": 5000, "bought_price": 600, "time_bought": 1700100000]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let stock = try JSONDecoder().decode(StockHolding.self, from: data)

        XCTAssertEqual(stock.stockId, 1)
        XCTAssertEqual(stock.totalShares, 10000)
        XCTAssertEqual(stock.transactions?.count, 2)
    }

    func testStockHolding_totalCostBasis() {
        let stock = StockHolding(
            stockId: 1, totalShares: 10000,
            transactions: [
                StockTransaction(shares: 5000, boughtPrice: 500, timeBought: 1700000000),
                StockTransaction(shares: 5000, boughtPrice: 600, timeBought: 1700100000)
            ]
        )

        XCTAssertEqual(stock.totalCostBasis, 5_500_000) // 5000*500 + 5000*600
    }

    func testStockHolding_decodesWithoutTransactions() throws {
        let json: [String: Any] = [
            "stock_id": 25,
            "total_shares": 0
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let stock = try JSONDecoder().decode(StockHolding.self, from: data)

        XCTAssertEqual(stock.stockId, 25)
        XCTAssertEqual(stock.totalShares, 0)
        XCTAssertNil(stock.transactions)
        XCTAssertEqual(stock.totalCostBasis, 0)
    }
}
