import XCTest
@testable import MacTorn

final class RetryBackoffTests: XCTestCase {
    func testRetryBackoffLadderCapsAtThirtyMinutesAndClearsOnSuccess() {
        var backoff = RetryBackoff()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for expected: TimeInterval in [60, 300, 1_800, 1_800] {
            backoff.fail(at: t0)
            XCTAssertEqual(backoff.retryAfter, t0.addingTimeInterval(expected))
        }
        XCTAssertFalse(backoff.allows(at: t0.addingTimeInterval(1_799)))
        XCTAssertTrue(backoff.allows(at: t0.addingTimeInterval(1_800)))
        backoff.succeed()
        XCTAssertTrue(backoff.allows(at: t0))
    }
}
