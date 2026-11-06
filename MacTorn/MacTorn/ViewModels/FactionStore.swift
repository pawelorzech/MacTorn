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
        guard json["name"] is String,
              json["ID"] is Int,
              json["respect"] is Int,
              let chain = json["chain"] as? [String: Any],
              chain["current"] is Int,
              chain["max"] is Int,
              chain["timeout"] is Int,
              chain["cooldown"] is Int else { return nil }
        return try? JSONDecoder().decode(FactionData.self, from: data)
    }

    nonisolated static func decodeWars(_ data: Data, _ json: [String: Any]) -> [RankedWar]? {
        decodeArray(json, key: "rankedwars")
    }

    nonisolated static func decodeNews(_ data: Data, _ json: [String: Any]) -> [FactionNews]? {
        decodeArray(json, key: "news")
    }

    private nonisolated static func decodeArray<Value: Decodable>(_ json: [String: Any], key: String) -> [Value]? {
        guard let array = json[key] as? [Any],
              let encoded = try? JSONSerialization.data(withJSONObject: array) else { return nil }
        return try? JSONDecoder().decode([Value].self, from: encoded)
    }
}
