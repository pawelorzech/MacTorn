import XCTest
@testable import MacTorn

final class MoneyDataTests: XCTestCase {

    // MARK: - Decoding Tests

    func testDecoding_fullData() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.moneyData)
        let money = try JSONDecoder().decode(MoneyData.self, from: data)

        XCTAssertEqual(money.cash, 1000000)
        XCTAssertEqual(money.vault, 50000000)
        XCTAssertEqual(money.points, 5000)
        XCTAssertEqual(money.tokens, 100)
        XCTAssertEqual(money.cayman, 100000000)
    }

    func testDecoding_withDefaults() throws {
        // When fields are missing, should use defaults (0)
        let json: [String: Any] = [
            "money_onhand": 500000
            // Other fields missing
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let money = try JSONDecoder().decode(MoneyData.self, from: data)

        XCTAssertEqual(money.cash, 500000)
        XCTAssertEqual(money.vault, 0) // Default
        XCTAssertEqual(money.points, 0) // Default
        XCTAssertEqual(money.tokens, 0) // Default
        XCTAssertEqual(money.cayman, 0) // Default
    }

    func testDecoding_allMissing() throws {
        let json: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: json)
        let money = try JSONDecoder().decode(MoneyData.self, from: data)

        XCTAssertEqual(money.cash, 0)
        XCTAssertEqual(money.vault, 0)
        XCTAssertEqual(money.points, 0)
        XCTAssertEqual(money.tokens, 0)
        XCTAssertEqual(money.cayman, 0)
    }

    // MARK: - Memberwise Initializer Tests

    func testMemberwiseInit() {
        let money = MoneyData(cash: 100, vault: 200, points: 300, tokens: 400, cayman: 500)

        XCTAssertEqual(money.cash, 100)
        XCTAssertEqual(money.vault, 200)
        XCTAssertEqual(money.points, 300)
        XCTAssertEqual(money.tokens, 400)
        XCTAssertEqual(money.cayman, 500)
    }

    func testDefaultInit() {
        let money = MoneyData()

        XCTAssertEqual(money.cash, 0)
        XCTAssertEqual(money.vault, 0)
        XCTAssertEqual(money.points, 0)
        XCTAssertEqual(money.tokens, 0)
        XCTAssertEqual(money.cayman, 0)
    }

    // MARK: - Large Numbers Tests

    func testLargeNumbers() throws {
        let json: [String: Any] = [
            "money_onhand": 999999999999,
            "vault_amount": 9999999999999,
            "points": 100000,
            "company_funds": 50000,
            "cayman_bank": 99999999999999
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let money = try JSONDecoder().decode(MoneyData.self, from: data)

        XCTAssertEqual(money.cash, 999999999999)
        XCTAssertEqual(money.vault, 9999999999999)
        XCTAssertEqual(money.points, 100000)
        XCTAssertEqual(money.tokens, 50000)
        XCTAssertEqual(money.cayman, 99999999999999)
    }

    // MARK: - Encoding Tests

    func testEncodingRoundTrip() throws {
        let original = MoneyData(cash: 1000, vault: 2000, points: 100, tokens: 50, cayman: 5000)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MoneyData.self, from: data)

        XCTAssertEqual(original.cash, decoded.cash)
        XCTAssertEqual(original.vault, decoded.vault)
        XCTAssertEqual(original.points, decoded.points)
        XCTAssertEqual(original.tokens, decoded.tokens)
        XCTAssertEqual(original.cayman, decoded.cayman)
    }
}
