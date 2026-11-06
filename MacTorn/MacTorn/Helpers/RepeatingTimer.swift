import Combine
import Foundation

/// A repeating main-run-loop timer that remembers the interval it was started with, so
/// a cadence change can tell a stale timer from a current one.
@MainActor
final class RepeatingTimer {
    private var cancellable: AnyCancellable?
    private(set) var interval: TimeInterval?
    /// When the current schedule began; a restart moves the tick phase.
    private(set) var startedAt: Date?

    var isRunning: Bool { cancellable != nil }

    /// Replaces any running timer.
    func start(every interval: TimeInterval, tolerance: TimeInterval? = nil, _ tick: @escaping @MainActor () -> Void) {
        self.interval = interval
        startedAt = Date()
        cancellable = Timer.publish(every: interval, tolerance: tolerance ?? interval / 10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick() }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        interval = nil
        startedAt = nil
    }
}
