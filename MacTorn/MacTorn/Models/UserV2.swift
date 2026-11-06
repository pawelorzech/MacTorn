import Foundation

// MARK: - Organized Crime 2.0 (player's own OC via v2 /user?selections=organizedcrime)
//
// Torn migrated every faction to Organized Crimes 2.0 (~Feb 2025). The old v1
// `faction/?selections=crimes` selection now only returns frozen OC-1.0 history (0 active) and its
// `initiated` field flipped from Bool to Int, so the player's own current OC is read from the v2
// endpoint instead. Shape verified against a live API response 2026-07-03.
struct OrganizedCrime2: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let difficulty: Int?
    let status: String?          // e.g. "Planning", "Recruiting", "Successful"
    let createdAt: Int?
    let readyAt: Int?            // epoch when the OC becomes executable
    let expiredAt: Int?
    let executedAt: Int?
    let slots: [OCSlot]?

    enum CodingKeys: String, CodingKey {
        case id, name, difficulty, status, slots
        case createdAt = "created_at"
        case readyAt = "ready_at"
        case expiredAt = "expired_at"
        case executedAt = "executed_at"
    }

    init(id: Int, name: String, difficulty: Int? = nil, status: String? = nil,
         createdAt: Int? = nil, readyAt: Int? = nil, expiredAt: Int? = nil,
         executedAt: Int? = nil, slots: [OCSlot]? = nil) {
        self.id = id; self.name = name; self.difficulty = difficulty; self.status = status
        self.createdAt = createdAt; self.readyAt = readyAt; self.expiredAt = expiredAt
        self.executedAt = executedAt; self.slots = slots
    }

    /// True once the OC has reached its ready time and hasn't been executed yet.
    /// `readyAt` is an absolute **server** timestamp, so `now` must be Torn's now
    /// (`AppState.serverNow`).
    func isReady(at now: Date) -> Bool {
        guard executedAt == nil, let readyAt, readyAt > 0 else { return false }
        return readyAt <= Int(now.timeIntervalSince1970)
    }

    var filledSlots: Int { slots?.filter { $0.user != nil }.count ?? 0 }
    var totalSlots: Int { slots?.count ?? 0 }

    /// The signed-in player's progress (0–100) in their slot, if they hold one.
    func myProgress(playerId: Int) -> Double? {
        slots?.first { $0.user?.id == playerId }?.user?.progress
    }
}

struct OCSlot: Codable, Equatable {
    let position: String?
    let checkpointPassRate: Int?
    let user: OCSlotUser?

    enum CodingKeys: String, CodingKey {
        case position, user
        case checkpointPassRate = "checkpoint_pass_rate"
    }

    init(position: String? = nil, checkpointPassRate: Int? = nil, user: OCSlotUser? = nil) {
        self.position = position; self.checkpointPassRate = checkpointPassRate; self.user = user
    }
}

struct OCSlotUser: Codable, Equatable {
    let id: Int?
    let progress: Double?
    let joinedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, progress
        case joinedAt = "joined_at"
    }

    init(id: Int? = nil, progress: Double? = nil, joinedAt: Int? = nil) {
        self.id = id; self.progress = progress; self.joinedAt = joinedAt
    }
}

// MARK: - Daily Refills (v2 /user?selections=refills)
struct Refills: Codable, Equatable {
    let energy: Bool
    let nerve: Bool
    let token: Bool
    let specialCount: Int?

    enum CodingKeys: String, CodingKey {
        case energy, nerve, token
        case specialCount = "special_count"
    }

    init(energy: Bool = false, nerve: Bool = false, token: Bool = false, specialCount: Int? = nil) {
        self.energy = energy; self.nerve = nerve; self.token = token; self.specialCount = specialCount
    }

    /// Refills the player hasn't claimed yet today (the actionable nudge).
    var unclaimed: [String] {
        var out: [String] = []
        if !energy { out.append("Energy") }
        if !nerve { out.append("Nerve") }
        if !token { out.append("Token") }
        return out
    }
}

// MARK: - Notification counters (v2 /user?selections=notifications)

/// The four counters Torn's own header badges are built from.
///
/// The cheap way to know something is waiting: point-in-time, costs no rows, needs only a
/// Minimal-access key and rides the poll MacTorn already makes. The row-based `messages` selection
/// spends rows against the 50,000-a-day-per-category cap for the same single integer. Also carries
/// pending awards and an active competition.
struct TornNotifications: Codable, Equatable, Sendable {
    let messages: Int
    let events: Int
    let awards: Int
    let competition: Int

    init(messages: Int = 0, events: Int = 0, awards: Int = 0, competition: Int = 0) {
        self.messages = messages
        self.events = events
        self.awards = awards
        self.competition = competition
    }

    var total: Int { messages + events + awards + competition }
    var hasAny: Bool { total > 0 }
}

// MARK: - Virus programming (v2 /user/virus)

/// A virus being written, and the instant it finishes.
///
/// `nil` at the response level means no virus is being programmed. Torn gives an absolute
/// Unix timestamp rather than a duration, so the countdown is derived locally and the
/// endpoint only needs re-reading when it lapses — see `AppState.fetchVirusIfNeeded`.
struct VirusProgramming: Codable, Equatable, Sendable {
    let itemID: Int
    let name: String
    /// Absolute Unix timestamp the virus is finished at.
    let until: Int

    init(itemID: Int, name: String, until: Int) {
        self.itemID = itemID
        self.name = name
        self.until = until
    }

    private enum CodingKeys: String, CodingKey { case item, until }
    private enum ItemKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let item = try container.nestedContainer(keyedBy: ItemKeys.self, forKey: .item)
        itemID = try item.decode(Int.self, forKey: .id)
        name = try item.decode(String.self, forKey: .name)
        until = try container.decode(Int.self, forKey: .until)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var item = container.nestedContainer(keyedBy: ItemKeys.self, forKey: .item)
        try item.encode(itemID, forKey: .id)
        try item.encode(name, forKey: .name)
        try container.encode(until, forKey: .until)
    }

    /// Seconds left, measured against the Torn-side clock the caller supplies. Never negative: a
    /// finished virus reads as zero.
    func secondsRemaining(at serverNow: Date) -> Int {
        NumericSafety.secondsRemaining(until: until, at: serverNow)
    }

    func isReady(at serverNow: Date) -> Bool { Int(serverNow.timeIntervalSince1970) >= until }
}

// MARK: - Education (v2 /user?selections=education)
struct EducationStatus: Codable, Equatable {
    let complete: [Int]
    let current: CurrentEducation?

    init(complete: [Int] = [], current: CurrentEducation? = nil) {
        self.complete = complete; self.current = current
    }

    var isStudying: Bool { current?.until != nil }

    /// When the in-progress course finishes; nil if not studying.
    var endsDate: Date? {
        guard let until = current?.until, until > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(until))
    }
}

struct CurrentEducation: Codable, Equatable {
    let id: Int?
    let until: Int?   // epoch when the current course completes
}

// MARK: - Bounty (v2 /user?selections=bounties)
struct Bounty: Codable, Equatable, Identifiable {
    let targetId: Int
    let targetName: String?
    let targetLevel: Int?
    let listerId: Int?
    let listerName: String?     // null when the bounty is anonymous
    let reward: Int
    let reason: String?
    let quantity: Int?
    let isAnonymous: Bool?
    let validUntil: Int?

    // The payload has no stable per-bounty id; a composite key is enough to
    // de-dup "bounty on you" notifications across polls.
    var id: String { "\(targetId)-\(reward)-\(listerId ?? 0)-\(validUntil ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case targetId = "target_id"
        case targetName = "target_name"
        case targetLevel = "target_level"
        case listerId = "lister_id"
        case listerName = "lister_name"
        case reward, reason, quantity
        case isAnonymous = "is_anonymous"
        case validUntil = "valid_until"
    }
}
