import Foundation

// MARK: - Shared testable clock (Etap D / foundation for Etap J)
//
// A single, injectable source of "now" so time-dependent logic — the polling budget
// windows here, and the upcoming "Next Action" timeline — can be tested deterministically
// without sleeping real seconds, and so every feature reads the same clock.

protocol TimeSource: AnyObject {
    var now: Date { get }
}

/// Production clock: wall time.
final class SystemTimeSource: TimeSource {
    var now: Date { Date() }
}

/// Test/preview clock: advance time by hand.
final class MutableTimeSource: TimeSource {
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    var now: Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    func set(_ date: Date) { current = date }
}
