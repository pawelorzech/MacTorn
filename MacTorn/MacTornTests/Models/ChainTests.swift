import XCTest
@testable import MacTorn

final class ChainTests: XCTestCase {

    // MARK: - isActive Tests

    func testIsActive_inactive() throws {
        let json = TornAPIFixtures.chainInactive
        let chain = try decode(Chain.self, from: json)

        XCTAssertFalse(chain.isActive)
    }

    func testIsActive_active() throws {
        let json = TornAPIFixtures.chainActive
        let chain = try decode(Chain.self, from: json)

        XCTAssertTrue(chain.isActive)
    }

    func testIsActive_zeroCurrent() throws {
        let json: [String: Any] = [
            "current": 0,
            "maximum": 10,
            "timeout": Int(Date().timeIntervalSince1970) + 300,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertFalse(chain.isActive)
    }

    func testIsActive_zeroTimeout() throws {
        let json: [String: Any] = [
            "current": 25,
            "maximum": 100,
            "timeout": 0,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertFalse(chain.isActive)
    }

    func testIsActive_nilValues() throws {
        let json: [String: Any] = [:]
        let chain = try decode(Chain.self, from: json)
        XCTAssertFalse(chain.isActive)
    }

    // MARK: - isOnCooldown Tests

    func testIsOnCooldown_no() throws {
        let json = TornAPIFixtures.chainInactive
        let chain = try decode(Chain.self, from: json)

        XCTAssertFalse(chain.isOnCooldown)
    }

    func testIsOnCooldown_yes() throws {
        let json = TornAPIFixtures.chainOnCooldown
        let chain = try decode(Chain.self, from: json)

        XCTAssertTrue(chain.isOnCooldown)
    }

    func testIsOnCooldown_zeroCooldown() throws {
        let json: [String: Any] = [
            "current": 0,
            "maximum": 10,
            "timeout": 0,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertFalse(chain.isOnCooldown)
    }

    func testIsOnCooldown_nilCooldown() throws {
        let json: [String: Any] = [
            "current": 0,
            "maximum": 10,
            "timeout": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertFalse(chain.isOnCooldown)
    }

    // MARK: - timeoutRemaining Tests

    func testTimeoutRemaining_noTimeout() throws {
        let json: [String: Any] = [
            "current": 0,
            "maximum": 10,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertEqual(chain.timeoutRemaining, 0)
    }

    func testTimeoutRemaining_timeoutInPast() throws {
        let pastTime = Int(Date().timeIntervalSince1970) - 1000
        let json: [String: Any] = [
            "current": 25,
            "maximum": 100,
            "timeout": pastTime,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)
        XCTAssertEqual(chain.timeoutRemaining, 0)
    }

    func testTimeoutRemaining_timeoutInFuture() throws {
        let futureTime = Int(Date().timeIntervalSince1970) + 1000
        let json: [String: Any] = [
            "current": 25,
            "maximum": 100,
            "timeout": futureTime,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)

        // Should be approximately 1000, allow some tolerance
        XCTAssertGreaterThan(chain.timeoutRemaining, 900)
        XCTAssertLessThanOrEqual(chain.timeoutRemaining, 1000)
    }

    // MARK: - Decoding Tests

    func testDecoding_activeChain() throws {
        let json: [String: Any] = [
            "current": 50,
            "maximum": 100,
            "timeout": 1700000300,
            "cooldown": 0
        ]
        let chain = try decode(Chain.self, from: json)

        XCTAssertEqual(chain.current, 50)
        XCTAssertEqual(chain.maximum, 100)
        XCTAssertEqual(chain.timeout, 1700000300)
        XCTAssertEqual(chain.cooldown, 0)
    }

    func testDecoding_cooldownChain() throws {
        let json = TornAPIFixtures.chainOnCooldown
        let chain = try decode(Chain.self, from: json)

        XCTAssertEqual(chain.current, 0)
        XCTAssertEqual(chain.cooldown, 3600)
        XCTAssertTrue(chain.isOnCooldown)
    }

    // MARK: - Equatable Tests

    func testEquatable() throws {
        let json: [String: Any] = [
            "current": 25,
            "maximum": 100,
            "timeout": 1000,
            "cooldown": 0
        ]
        let chain1 = try decode(Chain.self, from: json)
        let chain2 = try decode(Chain.self, from: json)
        XCTAssertEqual(chain1, chain2)
    }

    func testEquatable_different() throws {
        let json1: [String: Any] = [
            "current": 25,
            "maximum": 100,
            "timeout": 1000,
            "cooldown": 0
        ]
        let json2: [String: Any] = [
            "current": 50,
            "maximum": 100,
            "timeout": 1000,
            "cooldown": 0
        ]
        let chain1 = try decode(Chain.self, from: json1)
        let chain2 = try decode(Chain.self, from: json2)
        XCTAssertNotEqual(chain1, chain2)
    }
}
