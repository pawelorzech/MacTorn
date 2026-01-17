import XCTest
@testable import MacTorn

final class BarTests: XCTestCase {

    // MARK: - Percentage Calculation Tests

    func testPercentageCalculation_fullBar() {
        let bar = Bar(current: 150, maximum: 150)
        XCTAssertEqual(bar.percentage, 100.0, accuracy: 0.01)
    }

    func testPercentageCalculation_halfBar() {
        let bar = Bar(current: 75, maximum: 150)
        XCTAssertEqual(bar.percentage, 50.0, accuracy: 0.01)
    }

    func testPercentageCalculation_emptyBar() {
        let bar = Bar(current: 0, maximum: 150)
        XCTAssertEqual(bar.percentage, 0.0, accuracy: 0.01)
    }

    func testPercentageCalculation_overFull() {
        // Edge case: current > maximum (can happen with boosters)
        let bar = Bar(current: 200, maximum: 150)
        XCTAssertEqual(bar.percentage, 133.33, accuracy: 0.01)
    }

    func testPercentageCalculation_zeroMaximum() {
        // Edge case: division by zero protection
        let bar = Bar(current: 0, maximum: 0)
        XCTAssertEqual(bar.percentage, 0.0)
    }

    // MARK: - Decoding Tests

    func testDecoding_fullBar() throws {
        let json = TornAPIFixtures.energyFull
        let bar = try decode(Bar.self, from: json)

        XCTAssertEqual(bar.current, 150)
        XCTAssertEqual(bar.maximum, 150)
        XCTAssertEqual(bar.increment, 5)
        XCTAssertEqual(bar.interval, 300)
        XCTAssertEqual(bar.ticktime, 0)
        XCTAssertEqual(bar.fulltime, 0)
    }

    func testDecoding_halfBar() throws {
        let json = TornAPIFixtures.energyHalf
        let bar = try decode(Bar.self, from: json)

        XCTAssertEqual(bar.current, 75)
        XCTAssertEqual(bar.maximum, 150)
        XCTAssertEqual(bar.percentage, 50.0, accuracy: 0.01)
    }

    func testDecoding_emptyBar() throws {
        let json = TornAPIFixtures.energyEmpty
        let bar = try decode(Bar.self, from: json)

        XCTAssertEqual(bar.current, 0)
        XCTAssertEqual(bar.maximum, 150)
        XCTAssertEqual(bar.percentage, 0.0)
    }

    // MARK: - Equatable Tests

    func testEquatable_sameBars() {
        let bar1 = Bar(current: 100, maximum: 150)
        let bar2 = Bar(current: 100, maximum: 150)
        XCTAssertEqual(bar1, bar2)
    }

    func testEquatable_differentBars() {
        let bar1 = Bar(current: 100, maximum: 150)
        let bar2 = Bar(current: 50, maximum: 150)
        XCTAssertNotEqual(bar1, bar2)
    }

    // MARK: - Edge Cases

    func testNegativeCurrent() {
        // Edge case: negative current (shouldn't happen but handle gracefully)
        let bar = Bar(current: -10, maximum: 150)
        XCTAssertEqual(bar.percentage, -6.67, accuracy: 0.01)
    }

    func testLargeNumbers() {
        // Large numbers shouldn't cause overflow
        let bar = Bar(current: 1000000, maximum: 10000000)
        XCTAssertEqual(bar.percentage, 10.0, accuracy: 0.01)
    }
}
