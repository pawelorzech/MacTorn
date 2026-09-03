import XCTest
@testable import MacTorn

final class TornFormatterTests: XCTestCase {
    func testFormatMoney_standardAmounts() {
        XCTAssertEqual(TornFormatter.formatMoney(0), "$0")
        XCTAssertEqual(TornFormatter.formatMoney(100), "$100")
        XCTAssertEqual(TornFormatter.formatMoney(1_000), "$1,000")
        XCTAssertEqual(TornFormatter.formatMoney(1_250_000), "$1,250,000")
        XCTAssertEqual(TornFormatter.formatMoney(50_000_000), "$50,000,000")
    }

    func testFormatMoney_negativeAmounts() {
        XCTAssertEqual(TornFormatter.formatMoney(-500), "-$500")
    }

    func testFormatNumber_standardNumbers() {
        XCTAssertEqual(TornFormatter.formatNumber(0), "0")
        XCTAssertEqual(TornFormatter.formatNumber(42), "42")
        XCTAssertEqual(TornFormatter.formatNumber(1_000), "1,000")
        XCTAssertEqual(TornFormatter.formatNumber(5_056_869), "5,056,869")
    }
}
