import Foundation

struct Chain: Codable, Equatable {
    let current: Int?
    let maximum: Int?
    let timeout: Int?
    let cooldown: Int?
    
    var isActive: Bool {
        guard let current = current, let timeout = timeout else { return false }
        return current > 0 && timeout > 0
    }
    
    var isOnCooldown: Bool {
        guard let cooldown = cooldown else { return false }
        return cooldown > 0
    }
    
    /// Seconds until the chain lapses. `timeout` is an absolute **server** timestamp, so
    /// `now` must be Torn's now (`AppState.serverNow`).
    func timeoutRemaining(at now: Date) -> Int {
        NumericSafety.secondsRemaining(until: timeout, at: now)
    }
}

/// How alarming the remaining chain time is. The thresholds (60 s / 180 s) and the red/orange/green
/// mapping live here once, shared by colour and the VoiceOver description.
enum ChainUrgency {
    case critical
    case warning
    case healthy

    init(remaining: Int) {
        if remaining < 60 {
            self = .critical
        } else if remaining < 180 {
            self = .warning
        } else {
            self = .healthy
        }
    }

    var spokenDescription: String {
        switch self {
        case .critical: return "critical"
        case .warning: return "warning"
        case .healthy: return "healthy"
        }
    }
}

struct FactionData: Codable {
    let name: String
    let factionId: Int
    let respect: Int
    let chain: FactionChain
    
    enum CodingKeys: String, CodingKey {
        case name
        case factionId = "ID"
        case respect
        case chain
    }
    
    init(name: String = "", factionId: Int = 0, respect: Int = 0, chain: FactionChain = FactionChain()) {
        self.name = name
        self.factionId = factionId
        self.respect = respect
        self.chain = chain
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        factionId = (try? container.decode(Int.self, forKey: .factionId)) ?? 0
        respect = (try? container.decode(Int.self, forKey: .respect)) ?? 0
        chain = (try? container.decode(FactionChain.self, forKey: .chain)) ?? FactionChain()
    }

    /// A copy whose `chain.timeout` is an absolute server timestamp. See
    /// `FactionChain.resolvingExpiry(fetchedAt:clock:)`.
    func resolvingChainExpiry(fetchedAt: Date, clock: ServerClock) -> FactionData {
        FactionData(name: name, factionId: factionId, respect: respect,
                    chain: chain.resolvingExpiry(fetchedAt: fetchedAt, clock: clock))
    }
}

/// The `chain` object of v1 `faction/?selections=chain`.
///
/// **Wire semantics (verified live 2026-09-01):** Torn sends `timeout` as the number of
/// **seconds remaining** when the response was built, and `end` as the absolute Unix expiry —
/// `{"current":1,"timeout":146,"start":1788292282,"end":1788292582}` next to a `server_time` of
/// 1788292436. Every consumer compares `timeout` against the server clock as an absolute timestamp,
/// so a raw payload must go through `resolvingExpiry(fetchedAt:clock:)` before it is published;
/// after that `timeout == end`.
struct FactionChain: Codable {
    let current: Int
    let max: Int
    /// Raw off the wire: seconds remaining. After `resolvingExpiry`: absolute expiry.
    let timeout: Int
    let cooldown: Int
    /// Absolute Unix expiry as reported by Torn (`nil` when absent or 0).
    let end: Int?

    init(current: Int = 0, max: Int = 0, timeout: Int = 0, cooldown: Int = 0, end: Int? = nil) {
        self.current = current
        self.max = max
        self.timeout = timeout
        self.cooldown = cooldown
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = (try? container.decode(Int.self, forKey: .current)) ?? 0
        max = (try? container.decode(Int.self, forKey: .max)) ?? 0
        timeout = (try? container.decode(Int.self, forKey: .timeout)) ?? 0
        cooldown = (try? container.decode(Int.self, forKey: .cooldown)) ?? 0
        let rawEnd = (try? container.decode(Int.self, forKey: .end)) ?? 0
        end = rawEnd > 0 ? rawEnd : nil
    }

    enum CodingKeys: String, CodingKey {
        case current, max, timeout, cooldown, end
    }

    /// Turns the wire shape (relative `timeout`) into the app shape (absolute `timeout`).
    ///
    /// Prefers Torn's own `end` timestamp; without one, anchors the remaining seconds to
    /// the server clock at the moment the response arrived, the same way `travel.time_left`
    /// and `bar.fulltime` are anchored. An inactive chain (no links or no time left) is
    /// returned unchanged so `timeout` stays 0 and `isActive` stays false.
    func resolvingExpiry(fetchedAt: Date, clock: ServerClock) -> FactionChain {
        guard timeout >= 0 else {
            return FactionChain(current: current, max: max, timeout: 0, cooldown: cooldown, end: nil)
        }
        guard current > 0, timeout > 0 else { return self }
        guard let expiry = end ?? clock.serverTimestamp(fetchedAt: fetchedAt, plus: timeout) else {
            // An invalid duration is not an active countdown.
            return FactionChain(current: current, max: max, timeout: 0, cooldown: cooldown, end: nil)
        }
        return FactionChain(current: current, max: max, timeout: expiry, cooldown: cooldown, end: expiry)
    }
}

// MARK: - Faction Ranked War (v2 /faction/rankedwars)
struct RankedWar: Codable, Equatable, Identifiable {
    let id: Int
    let start: Int
    let end: Int
    let target: Int
    let winner: Int?
    let factions: [RankedWarFaction]

    /// Ongoing war: no end timestamp yet. Shape verified live 2026-07-03.
    var isActive: Bool { end == 0 }

    func faction(id: Int) -> RankedWarFaction? { factions.first { $0.id == id } }
    func opponent(of factionId: Int) -> RankedWarFaction? { factions.first { $0.id != factionId } }
}

struct RankedWarFaction: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let score: Int
    let chain: Int?
}

// MARK: - Faction News (v2 /faction/news?cat=main)
struct FactionNews: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let timestamp: Int

    /// News text arrives as HTML (profile/faction links); strip tags and decode entities for display,
    /// matching `TornEvent.cleanEvent`.
    var plainText: String {
        text.strippedHTMLAndDecodedEntities
    }
}
