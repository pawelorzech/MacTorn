import Foundation

/// Spacing between retries of slow-changing reference data after failures: one minute,
/// five, then thirty for every further failure. A success clears it.
struct RetryBackoff: Equatable {
    private static let ladder: [TimeInterval] = [60, 300, 1_800]

    private(set) var failures = 0
    private(set) var retryAfter: Date?

    func allows(at now: Date) -> Bool {
        retryAfter.map { now >= $0 } ?? true
    }

    mutating func fail(at now: Date) {
        failures += 1
        retryAfter = now.addingTimeInterval(Self.ladder[min(failures, Self.ladder.count) - 1])
    }

    mutating func succeed() {
        failures = 0
        retryAfter = nil
    }
}
