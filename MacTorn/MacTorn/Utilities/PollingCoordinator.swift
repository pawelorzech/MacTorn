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

    /// One counter per window. The old implementation kept every timestamp in an array and
    /// scanned the whole thing on each gate check (`prune()` on every record, and again on
    /// every `canMakeRequest`), which grew to tens of thousands of entries over a day and
    /// ran several O(n) scans per request on the main actor (audit W-2). Each counter now
    /// buckets events by whole second and drops expired buckets from the front, so both
    /// recording and reading are O(1) amortised.
    private var requestsInMinute = SlidingWindowCounter(windowSeconds: Int(minuteWindow))
    private var requestsInDay = SlidingWindowCounter(windowSeconds: Int(dayWindow))
    private var recordsByCategory: [TornBudgetCategory: SlidingWindowCounter] = [:]

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
        requestsInMinute.count(nowSecond: currentSecond) < hardCapPerMinute
    }

    // MARK: Recording

    /// Record that a request to `endpoint` was issued (call at issue time). Point-in-time
    /// endpoints count as one request with zero rows; row-based endpoints also add
    /// `recordsPerCall` to their category's daily row total.
    func record(_ endpoint: TornEndpoint) {
        let second = currentSecond
        requestsInMinute.add(1, at: second)
        requestsInDay.add(1, at: second)
        if endpoint.recordsPerCall > 0 {
            recordsByCategory[endpoint.budget, default: SlidingWindowCounter(windowSeconds: Int(Self.dayWindow))]
                .add(endpoint.recordsPerCall, at: second)
        }
    }

    // MARK: Readouts (for Diagnostics, Etap F)

    var requestsInLastMinute: Int { requestsInMinute.count(nowSecond: currentSecond) }
    var requestsInLastDay: Int { requestsInDay.count(nowSecond: currentSecond) }

    func recordsInLastDay(_ category: TornBudgetCategory) -> Int {
        recordsByCategory[category]?.count(nowSecond: currentSecond) ?? 0
    }

    /// Rows/day for every category that has traffic — for the diagnostics readout.
    func recordsPerDayByCategory() -> [TornBudgetCategory: Int] {
        var result: [TornBudgetCategory: Int] = [:]
        let second = currentSecond
        for (category, var counter) in recordsByCategory {
            let rows = counter.count(nowSecond: second)
            if rows > 0 { result[category] = rows }
        }
        return result
    }

    /// Whether a category is still comfortably under its daily row budget.
    func isWithinRecordBudget(_ category: TornBudgetCategory) -> Bool {
        recordsInLastDay(category) < recordBudgetPerDayPerCategory
    }

    // MARK: Internals

    /// Whole-second bucket for `now`. Budget windows are defined at second resolution.
    private var currentSecond: Int { Int(time.now.timeIntervalSince1970) }
}

/// A time-bucketed sliding counter: reports how many events fall inside a moving window,
/// with O(1) amortised record and query. Events are grouped by whole second and expired
/// buckets are dropped from the front as time advances — each bucket is inserted once and
/// removed once, so a day's worth of activity never costs a full-array scan.
private struct SlidingWindowCounter {
    private var buckets: [(second: Int, count: Int)] = []
    private var total = 0
    private let windowSeconds: Int

    init(windowSeconds: Int) {
        self.windowSeconds = windowSeconds
    }

    mutating func add(_ count: Int, at second: Int) {
        total += count
        if let last = buckets.last, second == last.second {
            buckets[buckets.count - 1].count += count
        } else if let last = buckets.last, second < last.second {
            // The clock moved backwards. Rare, so keep the array sorted with an insert
            // rather than complicating the common append path.
            var index = buckets.count - 1
            while index >= 0, buckets[index].second > second { index -= 1 }
            if index >= 0, buckets[index].second == second {
                buckets[index].count += count
            } else {
                buckets.insert((second, count), at: index + 1)
            }
        } else {
            buckets.append((second, count))
        }
    }

    mutating func count(nowSecond: Int) -> Int {
        prune(nowSecond: nowSecond)
        return total
    }

    /// Drop buckets strictly below `now - window`; the boundary second is kept. Both
    /// instants are truncated to whole seconds, so keeping it can hold an event up to one
    /// second past its window (over-count, the safe side of a rate cap) but never drops one
    /// that is still inside it — which would let a request slip past the cap.
    private mutating func prune(nowSecond: Int) {
        let cutoff = nowSecond - windowSeconds
        var index = 0
        var removed = 0
        while index < buckets.count, buckets[index].second < cutoff {
            removed += buckets[index].count
            index += 1
        }
        if index > 0 {
            buckets.removeFirst(index)
            total -= removed
        }
    }
}