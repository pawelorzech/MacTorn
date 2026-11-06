import Foundation

struct BattleStats {
    let strength: Int
    let defense: Int
    let speed: Int
    let dexterity: Int
    let total: Int?

    init(strength: Int = 0, defense: Int = 0, speed: Int = 0, dexterity: Int = 0) {
        self.strength = strength
        self.defense = defense
        self.speed = speed
        self.dexterity = dexterity
        self.total = NumericSafety.total([strength, defense, speed, dexterity])
    }
}

struct AttackResult: Identifiable {
    let code: String?
    let timestampStarted: Int?
    let timestampEnded: Int?
    let attackerId: Int?
    let attackerName: String?
    let defenderId: Int?
    let defenderName: String?
    let result: String?
    let respect: Double?

    let id: String

    init(code: String?, timestampStarted: Int?, timestampEnded: Int?, attackerId: Int?, attackerName: String?, defenderId: Int?, defenderName: String?, result: String?, respect: Double?) {
        self.code = code
        self.timestampStarted = timestampStarted
        self.timestampEnded = timestampEnded
        self.attackerId = attackerId
        self.attackerName = attackerName
        self.defenderId = defenderId
        self.defenderName = defenderName
        self.result = result
        self.respect = respect
        self.id = code ?? UUID().uuidString
    }

    func opponentName(forUserId userId: Int) -> String {
        let name: String?
        if attackerId == userId {
            name = defenderName
        } else {
            name = attackerName
        }

        if let name = name, !name.isEmpty {
            return name
        }
        return "Someone"
    }

    func opponentId(forUserId userId: Int) -> Int? {
        if attackerId == userId {
            return defenderId
        } else {
            return attackerId
        }
    }

    func wasAttacker(userId: Int) -> Bool {
        return attackerId == userId
    }
    
    /// `timestampEnded` is Torn's clock, so `now` should be too (`AppState.serverNow`).
    func timeAgo(at now: Date) -> String {
        guard let ts = timestampEnded else { return "" }
        return TornFormatter.timeAgo(since: ts, now: Int(now.timeIntervalSince1970)) ?? ""
    }
}
