import Foundation
import Observation

/// The signed-in player's faction: identity and live chain, ranked wars, news.
@MainActor
@Observable
final class FactionStore {
    var basic: FactionData?
    var wars: [RankedWar] = []
    var news: [FactionNews] = []

    func reset() {
        basic = nil
        wars = []
        news = []
    }

    /// `FactionData`'s decoder forgives missing fields for UI compatibility, so the wire
    /// check is stricter: `{}` must never publish a plausible empty faction or erase a
    /// valid chain.
    nonisolated static func decodeBasic(_ data: Data, _ json: [String: Any]) -> FactionData? {
        guard let name = json["name"] as? String,
              let factionId = json["ID"] as? Int,
              let respect = json["respect"] as? Int,
              let chain = json["chain"] as? [String: Any],
              let current = chain["current"] as? Int,
              let max = chain["max"] as? Int,
              let timeout = chain["timeout"] as? Int,
              let cooldown = chain["cooldown"] as? Int else { return nil }
        let rawEnd = chain["end"] as? Int ?? 0
        return FactionData(
            name: name,
            factionId: factionId,
            respect: respect,
            chain: FactionChain(
                current: current,
                max: max,
                timeout: timeout,
                cooldown: cooldown,
                end: rawEnd > 0 ? rawEnd : nil
            )
        )
    }

    nonisolated static func decodeWars(_ data: Data, _ json: [String: Any]) -> [RankedWar]? {
        guard let rows = json["rankedwars"] as? [[String: Any]] else { return nil }
        var wars: [RankedWar] = []
        wars.reserveCapacity(rows.count)
        for row in rows {
            guard let id = row["id"] as? Int,
                  let start = row["start"] as? Int,
                  let end = row["end"] as? Int,
                  let target = row["target"] as? Int,
                  let factionRows = row["factions"] as? [[String: Any]] else { return nil }
            let winner: Int?
            if let rawWinner = row["winner"], !(rawWinner is NSNull) {
                guard let parsedWinner = rawWinner as? Int else { return nil }
                winner = parsedWinner
            } else {
                winner = nil
            }
            var factions: [RankedWarFaction] = []
            factions.reserveCapacity(factionRows.count)
            for f in factionRows {
                guard let fID = f["id"] as? Int,
                      let fName = f["name"] as? String,
                      let fScore = f["score"] as? Int else { return nil }
                let chain: Int?
                if let rawChain = f["chain"], !(rawChain is NSNull) {
                    guard let parsedChain = rawChain as? Int else { return nil }
                    chain = parsedChain
                } else {
                    chain = nil
                }
                factions.append(RankedWarFaction(id: fID, name: fName, score: fScore, chain: chain))
            }
            wars.append(RankedWar(id: id, start: start, end: end, target: target, winner: winner, factions: factions))
        }
        return wars
    }

    nonisolated static func decodeNews(_ data: Data, _ json: [String: Any]) -> [FactionNews]? {
        guard let rows = json["news"] as? [[String: Any]] else { return nil }
        var items: [FactionNews] = []
        items.reserveCapacity(rows.count)
        for row in rows {
            guard let id = row["id"] as? String,
                  let text = row["text"] as? String,
                  let timestamp = row["timestamp"] as? Int else { return nil }
            items.append(FactionNews(id: id, text: text, timestamp: timestamp))
        }
        return items
    }
}
