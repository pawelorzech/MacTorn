import Foundation

/// Remote numbers may fit individually while their derived value does not. Nil means
/// unavailable, never a wrapped, saturated or invented total presented as real data.
enum NumericSafety {
    static func total(_ values: [Int]) -> Int? {
        var total = 0
        for value in values {
            guard value >= 0 else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    static func optionalTotal(_ values: [Int?]) -> Int? {
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return total(values.compactMap { $0 })
    }

    static func product(_ lhs: Int, _ rhs: Int) -> Int? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : result
    }

    static func integerAmount(_ value: Double) -> Int? {
        // Double(Int.max) rounds UP to 2^63 on supported 64-bit Macs.
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return Int(value)
    }

    static func progress(current: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, Double(current) / Double(maximum)))
    }

    static func scoreLead(mine: Int, opponent: Int) -> Int? {
        guard mine >= 0, opponent >= 0 else { return nil }
        let (lead, overflow) = mine.subtractingReportingOverflow(opponent)
        return overflow ? nil : lead
    }

    static func remaining(until deadline: Int?, now: Int) -> Int? {
        guard let deadline, deadline > 0, now >= 0 else { return nil }
        let (difference, overflow) = deadline.subtractingReportingOverflow(now)
        return overflow ? nil : max(0, difference)
    }

    static func elapsed(since timestamp: Int, now: Int) -> Int? {
        guard timestamp > 0, now >= 0 else { return nil }
        let (difference, overflow) = now.subtractingReportingOverflow(timestamp)
        return overflow ? nil : max(0, difference)
    }
}
