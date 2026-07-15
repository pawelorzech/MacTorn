import Foundation

// MARK: - Polling budget accounting (Etap D)
//
// Measures and caps MacTorn's Torn API usage so it stays well under Torn's limits and
// never silently drifts over (the class of bug that caused error 14 in v1.9.2). It
// tracks two independent budgets, both keyed off the typed `TornEndpoint` registry:
//
//   • Requests — a rolling per-minute and per-day count. Torn allows 100 req/min; we
//     cap at a conservative `hardCapPerMinute` (60) and treat `softTargetPerMinute` (15)
//     as the "healthy" line for diagnostics. `canMakeRequest()` is the gate no code path
//     may bypass.
//   • Records — row-based categories (events, attacks, news, forum) count against Torn's
//     50,000-rows/day-per-category cap. We track rows/day per `TornBudgetCategory` and
//     flag anything approaching `recordBudgetPerDayPerCategory` (15,000, a safe target).
//
// Time comes from an injected `TimeSource`, so the rolling windows are testable without
// waiting real minutes. Ownership of the actual poll *schedule* (moving the Combine
// timer out of AppState) is a later step — see ISA backlog D-02.
@MainActor
final class PollingCoordinator {
    private let time: TimeSource

    /// Conservative per-minute ceiling (Torn's own limit is 100/min).
    let hardCapPerMinute: Int
    /// "Healthy" per-minute cadence used for diagnostics coloring.
    let softTargetPerMinute: Int
    /// Per-category daily row budget (Torn's hard cap is 50,000).
    let recordBudgetPerDayPerCategory: Int

    private static let minuteWindow: TimeInterval = 60
    private static let dayWindow: TimeInterval = 24 * 60 * 60

    private var requestTimestamps: [Date] = []
    private var recordEvents: [(at: Date, category: TornBudgetCategory, count: Int)] = []

    init(time: TimeSource = SystemTimeSource(),
         hardCapPerMinute: Int = 60,
         softTargetPerMinute: Int = 15,
         recordBudgetPerDayPerCategory: Int = 15_000) {
        self.time = time
        self.hardCapPerMinute = hardCapPerMinute
        self.softTargetPerMinute = softTargetPerMinute
        self.recordBudgetPerDayPerCategory = recordBudgetPerDayPerCategory
    }

    // MARK: Gate

    /// Whether another request may be issued now without breaching the per-minute hard
    /// cap. Every request-issuing path should consult this so no UI action can bypass
    /// the limiter.
    func canMakeRequest() -> Bool {
        prune()
        return requestsInLastMinute < hardCapPerMinute
    }

    // MARK: Recording

    /// Record that a request to `endpoint` was issued (call at issue time). Point-in-time
    /// endpoints count as one request with zero rows; row-based endpoints also add
    /// `recordsPerCall` to their category's daily row total.
    func record(_ endpoint: TornEndpoint) {
        let now = time.now
        requestTimestamps.append(now)
        if endpoint.recordsPerCall > 0 {
            recordEvents.append((now, endpoint.budget, endpoint.recordsPerCall))
        }
        prune()
    }

    // MARK: Readouts (for Diagnostics, Etap F)

    var requestsInLastMinute: Int { count(requestTimestamps, within: Self.minuteWindow) }
    var requestsInLastDay: Int { count(requestTimestamps, within: Self.dayWindow) }

    func recordsInLastDay(_ category: TornBudgetCategory) -> Int {
        let cutoff = time.now.addingTimeInterval(-Self.dayWindow)
        var total = 0
        for event in recordEvents where event.category == category && event.at >= cutoff {
            total += event.count
        }
        return total
    }

    /// Rows/day for every category that has traffic — for the diagnostics readout.
    func recordsPerDayByCategory() -> [TornBudgetCategory: Int] {
        var result: [TornBudgetCategory: Int] = [:]
        for category in TornBudgetCategory.allCases {
            let rows = recordsInLastDay(category)
            if rows > 0 { result[category] = rows }
        }
        return result
    }

    /// Whether a category is still comfortably under its daily row budget.
    func isWithinRecordBudget(_ category: TornBudgetCategory) -> Bool {
        recordsInLastDay(category) < recordBudgetPerDayPerCategory
    }

    // MARK: Internals

    private func count(_ times: [Date], within window: TimeInterval) -> Int {
        let cutoff = time.now.addingTimeInterval(-window)
        return times.filter { $0 >= cutoff }.count
    }

    /// Drop entries older than the day window so the arrays stay bounded.
    private func prune() {
        let cutoff = time.now.addingTimeInterval(-Self.dayWindow)
        requestTimestamps.removeAll { $0 < cutoff }
        recordEvents.removeAll { $0.at < cutoff }
    }
}
