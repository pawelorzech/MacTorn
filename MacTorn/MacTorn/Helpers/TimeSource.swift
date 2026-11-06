import Foundation

protocol TimeSource: AnyObject {
    var now: Date { get }
}

final class SystemTimeSource: TimeSource {
    var now: Date { Date() }
}

/// The Mac↔Torn clock skew for one snapshot, in whole seconds.
///
/// Torn stamps every response with `server_time`. Derive a `ServerClock` once per snapshot and read
/// every countdown through it, so a Mac whose clock is off never shows two contradictory clocks.
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

    /// Movement below this is jitter, not a clock correction — see `merged(with:)`.
    /// The same window `CooldownEnds.merged` uses to pin cooldown end-timestamps: both
    /// are damping the identical physical wobble (whole-second integers on both sides
    /// of the subtraction, plus per-request latency), so they must not drift apart.
    static let jitterToleranceSeconds = 3

    init(offset: Int) {
        self.offset = (-Self.maxPlausibleSkewSeconds...Self.maxPlausibleSkewSeconds).contains(offset) ? offset : 0
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

    /// Keeps the pinned offset while the fresh derivation is within `toleranceSeconds`; adopts anything
    /// beyond it as a genuine correction. `server_time` is whole seconds and the local receipt is
    /// truncated, so the derived offset wobbles by a second or three between polls even when neither
    /// clock moved; unpinned, every countdown would tick backwards at each poll boundary. Comparing
    /// against the pinned value (not the previous derivation) lets slow one-directional drift cross
    /// the window and be adopted.
    func merged(with fresh: ServerClock,
                toleranceSeconds: Int = ServerClock.jitterToleranceSeconds) -> ServerClock {
        abs(fresh.offset - offset) <= toleranceSeconds ? self : fresh
    }

    func serverNow(_ localNow: Date) -> Date {
        localNow.addingTimeInterval(TimeInterval(offset))
    }

    func serverUnix(_ localNow: Date) -> Int {
        Int(localNow.timeIntervalSince1970) + offset
    }

    /// Turns a duration measured from the moment the server generated a response
    /// (`travel.time_left`, `bar.fulltime`) into an absolute *server* timestamp.
    func serverTimestamp(fetchedAt: Date, plus seconds: Int) -> Int? {
        guard seconds >= 0 else { return nil }
        let (timestamp, overflow) = serverUnix(fetchedAt).addingReportingOverflow(seconds)
        return overflow || timestamp <= 0 ? nil : timestamp
    }

    /// The local instant at which a server timestamp occurs. A scheduled local notification fires on
    /// the Mac's clock, so a server-absolute arrival time has to be converted back.
    func localDate(forServerTimestamp timestamp: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) - TimeInterval(offset))
    }
}
