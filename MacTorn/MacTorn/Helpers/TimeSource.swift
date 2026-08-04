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

// MARK: - Server clock (issue #46)
//
// Torn stamps every response with `server_time`. Cooldowns already used it, but travel,
// hospital, jail, chain and OC each measured against a bare `Date()`, so a Mac whose
// clock ran 90 s behind Torn's showed two contradictory clocks in one window: the
// cooldown pill was right while the menu bar claimed the plane was still 90 s out.
//
// `ServerClock` is the single conversion between the two clocks. Derive it once per
// snapshot, then read *every* countdown through it — never patch a call site by hand.

/// The Mac↔Torn clock skew for one snapshot, in whole seconds.
struct ServerClock: Equatable, Sendable {
    /// Seconds to add to the local clock to land on Torn's. Positive = the Mac is behind.
    let offset: Int

    /// No known skew — every conversion is the identity. Also the safe degraded state
    /// when a response carries no usable anchor.
    static let synchronized = ServerClock(offset: 0)

    /// Skew beyond this is a corrupt payload, not a slow Mac: a `server_time` a decade
    /// out would throw every countdown into the next geological era, which is far worse
    /// than the drift it was meant to correct. Generous enough that a genuinely un-synced
    /// machine (minutes, even hours) is still honoured.
    static let maxPlausibleSkewSeconds = 86_400

    init(offset: Int) {
        self.offset = offset
    }

    /// Derives the skew from a response anchor (`TornResponse.anchorTimestamp`) and the
    /// local instant that response was received. A missing, zero or implausible anchor
    /// collapses to `.synchronized` rather than throwing the countdowns the other way.
    init(anchor: Int?, localNow: Date) {
        guard let anchor, anchor > 0 else {
            self.offset = 0
            return
        }
        let delta = anchor - Int(localNow.timeIntervalSince1970)
        self.offset = abs(delta) <= Self.maxPlausibleSkewSeconds ? delta : 0
    }

    /// Torn's "now" for a given local instant.
    func serverNow(_ localNow: Date) -> Date {
        localNow.addingTimeInterval(TimeInterval(offset))
    }

    /// Torn's "now" as Unix seconds for a given local instant.
    func serverUnix(_ localNow: Date) -> Int {
        Int(localNow.timeIntervalSince1970) + offset
    }

    /// Turns a duration measured from the moment the server generated a response
    /// (`travel.time_left`, `bar.fulltime`) into an absolute *server* timestamp.
    func serverTimestamp(fetchedAt: Date, plus seconds: Int) -> Int {
        serverUnix(fetchedAt) + seconds
    }

    /// The local instant at which a server timestamp occurs. Needed whenever something
    /// outside the app holds the deadline — a scheduled local notification fires on the
    /// Mac's clock, so a server-absolute arrival time has to be converted back.
    func localDate(forServerTimestamp timestamp: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp - offset))
    }
}
