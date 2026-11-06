import Foundation
import SwiftUI

// MARK: - Battle Stats
struct BattleStats: Codable {
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strength = (try? container.decode(Int.self, forKey: .strength)) ?? 0
        defense = (try? container.decode(Int.self, forKey: .defense)) ?? 0
        speed = (try? container.decode(Int.self, forKey: .speed)) ?? 0
        dexterity = (try? container.decode(Int.self, forKey: .dexterity)) ?? 0
        if let supplied = try? container.decode(Int.self, forKey: .total) {
            total = supplied >= 0 ? supplied : nil
        } else {
            total = NumericSafety.total([strength, defense, speed, dexterity])
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case strength, defense, speed, dexterity, total
    }
}

// MARK: - Attack Result
struct AttackResult: Codable, Identifiable {
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

    enum CodingKeys: String, CodingKey {
        case code
        case timestampStarted = "timestamp_started"
        case timestampEnded = "timestamp_ended"
        case attackerId = "attacker_id"
        case attackerName = "attacker_name"
        case defenderId = "defender_id"
        case defenderName = "defender_name"
        case result, respect
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        timestampStarted = try container.decodeIfPresent(Int.self, forKey: .timestampStarted)
        timestampEnded = try container.decodeIfPresent(Int.self, forKey: .timestampEnded)
        attackerId = try container.decodeIfPresent(Int.self, forKey: .attackerId)
        attackerName = try container.decodeIfPresent(String.self, forKey: .attackerName)
        defenderId = try container.decodeIfPresent(Int.self, forKey: .defenderId)
        defenderName = try container.decodeIfPresent(String.self, forKey: .defenderName)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        respect = try container.decodeIfPresent(Double.self, forKey: .respect)
        id = code ?? UUID().uuidString
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
    
    func resultIcon(forUserId userId: Int) -> String {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked": return userWasAttacker ? "checkmark.circle.fill" : "xmark.circle.fill"
        case "Mugged": return userWasAttacker ? "dollarsign.circle.fill" : "xmark.circle.fill"
        case "Hospitalized": return userWasAttacker ? "cross.circle.fill" : "xmark.circle.fill"
        case "Lost": return userWasAttacker ? "xmark.circle.fill" : "shield.checkered"
        case "Stalemate": return "equal.circle.fill"
        case "Escape": return userWasAttacker ? "figure.run" : "shield.checkered"
        case "Assist": return "person.2.fill"
        default: return "questionmark.circle"
        }
    }

    func resultColor(forUserId userId: Int) -> Color {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked", "Mugged", "Hospitalized":
            return userWasAttacker ? .green : .red
        case "Lost":
            return userWasAttacker ? .red : .green
        case "Stalemate":
            return .orange
        case "Escape":
            return userWasAttacker ? .orange : .green
        case "Assist":
            return .blue
        default:
            return .gray
        }
    }
    
    /// `timestampEnded` is Torn's clock, so `now` should be too (`AppState.serverNow`).
    func timeAgo(at now: Date) -> String {
        guard let ts = timestampEnded else { return "" }
        guard let diff = NumericSafety.elapsed(since: ts, now: Int(now.timeIntervalSince1970)) else { return "" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }

    var timeAgo: String { timeAgo(at: Date()) }
}
