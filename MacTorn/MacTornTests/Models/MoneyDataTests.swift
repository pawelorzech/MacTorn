import XCTest
@testable import MacTorn

/// Money as the user snapshot parser reads it from the v1 `money` selection.
final class MoneyDataTests: XCTestCase {
    func testReadsEveryBalance() {
        let money = UserSnapshotService.parseMoney(TornAPIFixtures.moneyData)
        XCTAssertEqual(money.cash, 1000000)
        XCTAssertEqual(money.vault, 50000000)
        XCTAssertEqual(money.points, 5000)
        XCTAssertEqual(money.tokens, 100)
        XCTAssertEqual(money.cayman, 100000000)
    }

    func testMissingBalancesReadAsZero() {
        let money = UserSnapshotService.parseMoney(["money_onhand": 500000])
        XCTAssertEqual(money.cash, 500000)
        XCTAssertEqual(money.vault, 0)
        XCTAssertEqual(money.points, 0)
        XCTAssertEqual(money.tokens, 0)
        XCTAssertEqual(money.cayman, 0)
    }

    func testVaultFallsBackToPropertyVaultThenNestedMoneyVault() {
        XCTAssertEqual(UserSnapshotService.parseMoney(["property_vault": 7]).vault, 7)
        XCTAssertEqual(UserSnapshotService.parseMoney(["money": ["vault": 9]]).vault, 9)
        XCTAssertEqual(UserSnapshotService.parseMoney(["vault_amount": 3, "property_vault": 7]).vault, 3)
    }

    func testLargeNumbers() {
        let money = UserSnapshotService.parseMoney([
            "money_onhand": 999999999999,
            "vault_amount": 9999999999999,
            "points": 100000,
            "donator": 50000,
            "cayman_bank": 99999999999999,
        ])
        XCTAssertEqual(money.cash, 999999999999)
        XCTAssertEqual(money.vault, 9999999999999)
        XCTAssertEqual(money.points, 100000)
        XCTAssertEqual(money.tokens, 50000)
        XCTAssertEqual(money.cayman, 99999999999999)
    }
}
