import Foundation

struct TornResponse: Codable {
    let name: String?
    let playerId: Int?
    let energy: Bar?
    let nerve: Bar?
    let life: Bar?
    let happy: Bar?
    let cooldowns: Cooldowns?
    let travel: Travel?
    let status: Status?
    let events: [String: TornEvent]?
    /// Server-side Unix epoch at which this response was generated; the anchor for converting relative
    /// durations (e.g. cooldowns) into absolute end-timestamps, so countdowns match torn.com regardless
    /// of Mac↔server clock skew.
    ///
    /// The live v1 `user` root returns it as `server_time`, NOT `timestamp` (only present when the
    /// `timestamp` selection is requested, which we don't). `legacyTimestamp` keeps the old key working
    /// as a fallback. Verified against a live API response 2026-07-03.
    let serverTimestamp: Int?
    let legacyTimestamp: Int?

    /// Best available server-time anchor: prefer `server_time`, fall back to the
    /// legacy `timestamp` key, else nil (caller drops to local `Date()`).
    var anchorTimestamp: Int? { serverTimestamp ?? legacyTimestamp }

    enum CodingKeys: String, CodingKey {
        case name
        case playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, status
        case events
        case serverTimestamp = "server_time"
        case legacyTimestamp = "timestamp"
    }
    
    var bars: Bars? {
        guard let energy = energy,
              let nerve = nerve,
              let life = life,
              let happy = happy else { return nil }
        return Bars(energy: energy, nerve: nerve, life: life, happy: happy)
    }
    
    
    var recentEvents: [TornEvent] {
        guard let events = events else { return [] }
        return events
            .map { apiID, event in event.identified(by: apiID) }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

struct Bar: Codable, Equatable {
    let current: Int
    let maximum: Int
    let increment: Double?
    let interval: Int?
    let ticktime: Int?
    let fulltime: Int?
    
    init(current: Int, maximum: Int, increment: Double? = nil, interval: Int? = nil, ticktime: Int? = nil, fulltime: Int? = nil) {
        self.current = current
        self.maximum = maximum
        self.increment = increment
        self.interval = interval
        self.ticktime = ticktime
        self.fulltime = fulltime
    }
    
    var percentage: Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum) * 100
    }
}

struct Bars: Equatable {
    let energy: Bar
    let nerve: Bar
    let life: Bar
    let happy: Bar
}

struct Cooldowns: Codable, Equatable {
    let drug: Int
    let medical: Int
    let booster: Int
}

enum CooldownKind: CaseIterable {
    case drug, booster, medical

    var emoji: String {
        switch self {
        case .drug:    return "💊"
        case .booster: return "🧪"
        case .medical: return "🩹"
        }
    }

    /// Spoken/written name of the cooldown. The emoji above is decoration; this is the
    /// meaning, and it is what VoiceOver and any text fallback must use.
    var displayName: String {
        switch self {
        case .drug:    return "Drug"
        case .booster: return "Booster"
        case .medical: return "Medical"
        }
    }
}

/// Absolute end-timestamps for each cooldown, computed once at fetch time from the server's response
/// timestamp plus the relative cooldown duration. Storing the end-time (not the duration) keeps every
/// countdown drift-free against torn.com. A value of `0` means the cooldown is not active.
struct CooldownEnds: Equatable {
    let drugEndsAt: Int
    let boosterEndsAt: Int
    let medicalEndsAt: Int

    static func from(cooldowns: Cooldowns, anchor: Int) -> CooldownEnds {
        CooldownEnds(
            drugEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.drug),
            boosterEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.booster),
            medicalEndsAt: endTimestamp(anchor: anchor, duration: cooldowns.medical)
        )
    }

    /// One cooldown's absolute end-timestamp, or `0` — the struct's existing "not active"
    /// sentinel — when the cooldown is inactive or the API's numbers cannot produce a
    /// usable one.
    ///
    /// `anchor` and `duration` are raw `Int`s decoded straight from Torn, so nothing bounds their sum;
    /// an overflowing addition would trap the process, so that cooldown degrades to "unknown" instead.
    private static func endTimestamp(anchor: Int, duration: Int) -> Int {
        guard duration > 0 else { return 0 }
        let (endsAt, overflowed) = anchor.addingReportingOverflow(duration)
        return overflowed ? 0 : endsAt
    }

    func endsAt(_ kind: CooldownKind) -> Int {
        switch kind {
        case .drug:    return drugEndsAt
        case .booster: return boosterEndsAt
        case .medical: return medicalEndsAt
        }
    }

    /// `endsAt` is an absolute **server** timestamp, so `now` must be Torn's now
    /// (`AppState.serverNow`). The `Date()` default is for pure-model callers only.
    func remainingSeconds(_ kind: CooldownKind, at now: Date = Date()) -> Int {
        NumericSafety.secondsRemaining(until: endsAt(kind), at: now)
    }

    func soonestActive(at now: Date = Date()) -> (kind: CooldownKind, seconds: Int)? {
        CooldownKind.allCases
            .map { (kind: $0, seconds: remainingSeconds($0, at: now)) }
            .filter { $0.seconds > 0 }
            .min { $0.seconds < $1.seconds }
    }

    /// Stabilises per-poll jitter in cooldown end-timestamps. Each poll re-derives
    /// `endsAt = serverTimestamp + cooldowns.{kind}`, but both inputs are integer seconds subject to
    /// network-latency variance, so the result wobbles by ±1–3 s between polls even though the true
    /// expiry is fixed; unsmoothed, every poll would visibly jump the menu bar countdown.
    ///
    /// Per kind: keep the previously-pinned `endsAt` whenever the new one is within `toleranceSeconds`.
    /// A larger gap means the cooldown was reset (new booster, drug, medical after hospitalisation), so
    /// the new value is adopted. A `0` on either side (inactive) is taken from `other` so transitions
    /// in/out of active are immediate.
    ///
    /// The tolerance is shared with `ServerClock.merged`, which damps the other half of the same
    /// subtraction: pinning `endsAt` while `now` still wobbles would give the jump back.
    func merged(with other: CooldownEnds,
                toleranceSeconds: Int = ServerClock.jitterToleranceSeconds) -> CooldownEnds {
        func pick(_ old: Int, _ new: Int) -> Int {
            if old == 0 || new == 0 { return new }
            return abs(new - old) <= toleranceSeconds ? old : new
        }
        return CooldownEnds(
            drugEndsAt:    pick(drugEndsAt,    other.drugEndsAt),
            boosterEndsAt: pick(boosterEndsAt, other.boosterEndsAt),
            medicalEndsAt: pick(medicalEndsAt, other.medicalEndsAt)
        )
    }
}

struct Status: Codable, Equatable {
    let description: String?
    let details: String?
    let state: String?
    let until: Int?
    
    var isInHospital: Bool {
        state == "Hospital"
    }
    
    var isInJail: Bool {
        state == "Jail"
    }
    
    var isOkay: Bool {
        state == "Okay" || state == nil
    }
    
    /// Seconds until release. `until` is an absolute **server** timestamp, so `now` must
    /// be Torn's now (`AppState.serverNow`).
    func timeRemaining(at now: Date) -> Int {
        NumericSafety.secondsRemaining(until: until, at: now)
    }
}

struct TornEvent: Codable, Identifiable {
    let timestamp: Int
    let event: String
    let seen: Int?
    /// Dictionary key supplied by Torn. Two events can share a second-level timestamp,
    /// so the timestamp alone is not a stable SwiftUI identity.
    private var apiID: String? = nil

    enum CodingKeys: String, CodingKey {
        case timestamp, event, seen
    }

    var id: String { apiID ?? "\(timestamp):\(event)" }

    func identified(by apiID: String) -> TornEvent {
        var copy = self
        copy.apiID = apiID
        return copy
    }
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    /// Event text with HTML tags removed, then run through the shared display sanitiser. Bodies carry
    /// names and messages supplied by other players, so control characters and bidi overrides must go
    /// too. Tags come off first so the length cap applies to what the user sees, not to markup.
    var cleanEvent: String {
        event
            .strippedHTMLAndDecodedEntities
            .sanitizedForDisplay()
    }
}

