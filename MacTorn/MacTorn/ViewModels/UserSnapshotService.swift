import Foundation
import os.log

private let userSnapshotLogger = Logger(
    subsystem: TornConstants.logSubsystem,
    category: "UserSnapshotService"
)

struct UserHTTPResponse {
    let data: Data
    let statusCode: Int
}



struct UserSnapshotPayload {
    let snapshot: TornResponse
    let money: MoneyData
    let battleStats: BattleStats
    let recentAttacks: [AttackResult]?
    let properties: [PropertyInfo]?
    let stocks: [StockHolding]
}

struct UserActivityPayload {
    let events: [TornEvent]?
    let recentAttacks: [AttackResult]?
}

/// A section update from the combined v2 user response. `unchanged` is deliberately
/// distinct from a valid empty/null value: a partial or malformed sibling section must
/// not erase data successfully decoded on the previous poll.
enum UserV2Section<Value> {
    case unchanged
    case replace(Value)
}

enum OrganizedCrimeSection {
    case unchanged
    case replace(OrganizedCrime2?)
    case unavailable(message: String)
}

struct UserV2Payload {
    let organizedCrime: OrganizedCrimeSection
    let refills: UserV2Section<Refills>
    let education: UserV2Section<EducationStatus>
    let bounties: UserV2Section<[Bounty]>
    let bountiesTimestamp: Int?
    let bountiesDelay: Int?
    let notifications: UserV2Section<TornNotifications>
    /// Requested sections whose key was absent, null where null is not valid, or failed
    /// strict decoding. Valid sibling updates remain publishable.
    let malformedSelections: [String]
}

protocol UserSnapshotServicing: Sendable {
    func load(_ url: URL) async throws -> UserHTTPResponse
    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> TornServiceResult<UserSnapshotPayload>
}

/// Transport and decoding boundary for user-owned Torn endpoints. It does not know
/// `AppState`, budgets, endpoint health, notifications or account publication rules.
final class UserSnapshotService: UserSnapshotServicing, @unchecked Sendable {
    private let session: NetworkSession

    init(session: NetworkSession) {
        self.session = session
    }

    func load(_ url: URL) async throws -> UserHTTPResponse {
        let request = TornAPIClient.request(for: url)
        let (data, response) = try await session.data(for: request)
        return UserHTTPResponse(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> TornServiceResult<UserSnapshotPayload> {
        await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.userInfo[snapshotContractSelectionsKey] = SnapshotContractRequest(
                requested: requestedSelections,
                granted: grantedSelections
            )
            do {
                let envelope = try decoder.decode(RawUserSnapshotEnvelope.self, from: data)
                switch envelope.outcome {
                case .apiError(let apiError):
                    return .apiError(apiError, responseBytes: data.count)
                case .contractUnsatisfied:
                    return .malformed(responseBytes: data.count)
                case .payload(let payload):
                    return .success(payload, responseBytes: data.count)
                }
            } catch let DecodingError.keyNotFound(key, context) {
                userSnapshotLogger.error(
                    "TornResponse decode: missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                )
                return .malformed(responseBytes: data.count)
            } catch let DecodingError.typeMismatch(_, context) {
                userSnapshotLogger.error(
                    "TornResponse decode: type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                )
                return .malformed(responseBytes: data.count)
            } catch {
                userSnapshotLogger.error(
                    "TornResponse decode failed: \(String(describing: type(of: error)))"
                )
                return .malformed(responseBytes: data.count)
            }
        }.value
    }

    static func decodeActivity(_ data: Data, _ json: [String: Any]) -> UserActivityPayload? {
        // `TornResponse.recentEvents` collapses a *missing* key to `[]`. The payload keeps absent apart from
        // empty, the way `parseAttacks(_:)` does, so a 200 body that omits `events` leaves the user's event
        // list alone instead of emptying it.
        let events: [TornEvent]?
        if isPresent(json["events"]) {
            struct EventsEnvelope: Decodable {
                let events: [String: TornEvent]?
            }
            if let decoded = try? JSONDecoder().decode(EventsEnvelope.self, from: data) {
                events = decoded.events.map {
                    $0.map { apiID, event in event.identified(by: apiID) }
                        .sorted { $0.timestamp > $1.timestamp }
                } ?? []
            } else {
                events = nil
            }
        } else {
            events = nil
        }
        return UserActivityPayload(
            events: events,
            recentAttacks: parseAttacks(json)
        )
    }

    /// True when a top-level JSON key is present and not `null`.
    private static func isPresent(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is NSNull)
    }

    /// `requested` is the selection set the request actually carried; a selection that was
    /// narrowed away is "unchanged", not "missing".
    static func decodeUserV2(requested: Set<String>) -> @Sendable (Data, [String: Any]) -> UserV2Payload? {
        { data, _ in
            let decoder = JSONDecoder()
            decoder.userInfo[requestedUserSelectionsKey] = requested
            return try? decoder.decode(UserV2Payload.self, from: data)
        }
    }

    /// Decodes `/v2/user/virus`. An explicit `null` is the normal "not programming"
    /// answer. Missing or malformed data is a contract failure and must preserve the
    /// previous value rather than falsely announcing that a virus finished.
    static func decodeVirus(_ data: Data, _ json: [String: Any]) -> VirusProgramming?? {
        guard json.keys.contains("virus") else { return nil }
        if json["virus"] is NSNull { return .some(nil) }
        guard let dict = json["virus"] as? [String: Any],
              let until = dict["until"] as? Int,
              let item = dict["item"] as? [String: Any],
              let itemID = item["id"] as? Int,
              let name = item["name"] as? String else { return nil }
        return .some(VirusProgramming(itemID: itemID, name: name, until: until))
    }

    static func parseMoney(_ json: [String: Any]) -> MoneyData {
        let cash = json["money_onhand"] as? Int ?? 0
        let vault: Int
        if let value = json["vault_amount"] as? Int {
            vault = value
        } else if let value = json["property_vault"] as? Int {
            vault = value
        } else if let money = json["money"] as? [String: Any] {
            vault = money["vault"] as? Int ?? 0
        } else {
            vault = 0
        }
        return MoneyData(
            cash: cash,
            vault: vault,
            points: json["points"] as? Int ?? 0,
            tokens: json["donator"] as? Int ?? 0,
            cayman: json["cayman_bank"] as? Int ?? 0
        )
    }

    static func parseBattleStats(_ json: [String: Any]) -> BattleStats {
        BattleStats(
            strength: json["strength"] as? Int ?? 0,
            defense: json["defense"] as? Int ?? 0,
            speed: json["speed"] as? Int ?? 0,
            dexterity: json["dexterity"] as? Int ?? 0
        )
    }

    static func parseAttacks(_ json: [String: Any]) -> [AttackResult]? {
        guard let attacks = json["attacks"] as? [String: [String: Any]] else { return nil }
        return attacks.values.compactMap { attack in
            guard let code = attack["code"] as? String else { return nil }
            return AttackResult(
                code: code,
                timestampStarted: attack["timestamp_started"] as? Int,
                timestampEnded: attack["timestamp_ended"] as? Int,
                attackerId: attack["attacker_id"] as? Int,
                attackerName: attack["attacker_name"] as? String,
                defenderId: attack["defender_id"] as? Int,
                defenderName: attack["defender_name"] as? String,
                result: attack["result"] as? String,
                respect: attack["respect"] as? Double
            )
        }.sorted { ($0.timestampEnded ?? 0) > ($1.timestampEnded ?? 0) }
    }

    static func parseProperties(_ json: [String: Any]) -> [PropertyInfo]? {
        guard let properties = json["properties"] as? [String: [String: Any]] else {
            return nil
        }
        return properties.values.map { property in
            let rented = property["rented"] as? [String: Any]
            return PropertyInfo(
                id: property["property_id"] as? Int ?? 0,
                propertyType: property["property"] as? String ?? "",
                status: property["status"] as? String ?? "",
                cost: property["cost"] as? Int ?? 0,
                marketprice: property["marketprice"] as? Int ?? 0,
                happy: property["happy"] as? Int ?? 0,
                rented: rented != nil,
                rentDaysLeft: rented?["days_left"] as? Int
            )
        }.sorted { $0.id < $1.id }
    }
}

private let snapshotContractSelectionsKey = CodingUserInfoKey(rawValue: "snapshotContractSelections")!

private struct SnapshotContractRequest {
    let requested: [String]
    let granted: [String]?
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    init(_ raw: String) { self.stringValue = raw; self.intValue = Int(raw) }
}

/// Single-pass decoder for the v1 fast-user payload. Checks the Torn error envelope and
/// semantic contract before decoding `TornResponse`, `MoneyData`, `BattleStats`, attacks,
/// properties and stocks from the same JSON parse tree — eliminating the double parse and
/// per-stock `JSONSerialization.data` round-trip.
private struct RawUserSnapshotEnvelope: Decodable {
    enum Outcome {
        case apiError(TornAPIError)
        case contractUnsatisfied
        case payload(UserSnapshotPayload)
    }

    let outcome: Outcome

    private enum Keys: String, CodingKey {
        case error, code
        case name, playerId = "player_id"
        case energy, nerve, life, happy
        case cooldowns, travel, properties, stocks, attacks
        case money, moneyOnhand = "money_onhand", vaultAmount = "vault_amount"
        case propertyVault = "property_vault", points, donator, caymanBank = "cayman_bank", networth
        case strength, defense, speed, dexterity
    }

    private enum ErrorKeys: String, CodingKey { case code, error }
    private enum MoneyNestedKeys: String, CodingKey { case vault }
    private enum AttackKeys: String, CodingKey {
        case code, result, respect
        case timestampStarted = "timestamp_started"
        case timestampEnded = "timestamp_ended"
        case attackerId = "attacker_id"
        case attackerName = "attacker_name"
        case defenderId = "defender_id"
        case defenderName = "defender_name"
    }
    private enum PropertyKeys: String, CodingKey {
        case propertyId = "property_id", property, status, cost, marketprice, happy, rented
    }
    private enum RentedKeys: String, CodingKey { case daysLeft = "days_left" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)

        // 1. Torn API error envelope (v1 nested or v2 top-level).
        if let nested = try? container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error) {
            let code = (try? nested.decode(Int.self, forKey: .code)) ?? 0
            let message = (try? nested.decode(String.self, forKey: .error)) ?? ""
            outcome = .apiError(TornAPIError.classify(code: code, message: message))
            return
        }
        if let code = try? container.decode(Int.self, forKey: .code),
           let message = try? container.decode(String.self, forKey: .error) {
            outcome = .apiError(TornAPIError.classify(code: code, message: message))
            return
        }

        // 2. Semantic contract evidence check on the already-parsed JSON tree.
        if let req = decoder.userInfo[snapshotContractSelectionsKey] as? SnapshotContractRequest {
            let requested = Set(req.requested)
            let available = req.granted.map { requested.intersection(Set($0)) } ?? requested
            guard !available.isEmpty, available.contains(where: { Self.hasEvidence(for: $0, in: container) }) else {
                outcome = .contractUnsatisfied
                return
            }
        }

        // 3. Decode core `TornResponse` from the same decoder (no re-tokenization).
        let snapshot = try TornResponse(from: decoder)

        // 4. Decode companion sections from the same container with identical lenient rules.
        let money = Self.decodeMoney(from: container)
        let battleStats = Self.decodeBattleStats(from: container)
        let attacks = Self.decodeAttacks(from: container)
        let properties = Self.decodeProperties(from: container)
        let stocks = Self.decodeStocks(from: container)

        outcome = .payload(
            UserSnapshotPayload(
                snapshot: snapshot,
                money: money,
                battleStats: battleStats,
                recentAttacks: attacks,
                properties: properties,
                stocks: stocks
            )
        )
    }

    private static func isJSONObject(_ container: KeyedDecodingContainer<Keys>, key: Keys) -> Bool {
        (try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)) != nil
    }

    private static func isJSONNumberOrBool(_ container: KeyedDecodingContainer<Keys>, key: Keys) -> Bool {
        (try? container.decode(Int.self, forKey: key)) != nil
            || (try? container.decode(Double.self, forKey: key)) != nil
            || (try? container.decode(Bool.self, forKey: key)) != nil
    }

    private static func hasEvidence(for selection: String, in c: KeyedDecodingContainer<Keys>) -> Bool {
        switch selection {
        case "basic", "profile":
            return (try? c.decode(String.self, forKey: .name)) != nil || isJSONNumberOrBool(c, key: .playerId)
        case "bars":
            return isJSONObject(c, key: .energy) && isJSONObject(c, key: .nerve)
                && isJSONObject(c, key: .life) && isJSONObject(c, key: .happy)
        case "cooldowns":
            return isJSONObject(c, key: .cooldowns)
        case "travel":
            return isJSONObject(c, key: .travel)
        case "properties":
            return isJSONObject(c, key: .properties)
        case "stocks":
            return isJSONObject(c, key: .stocks)
        case "money":
            return c.contains(.moneyOnhand) || c.contains(.points) || c.contains(.caymanBank)
                || c.contains(.vaultAmount) || c.contains(.propertyVault) || c.contains(.networth)
        case "battlestats":
            return isJSONNumberOrBool(c, key: .strength) || isJSONNumberOrBool(c, key: .defense)
                || isJSONNumberOrBool(c, key: .speed) || isJSONNumberOrBool(c, key: .dexterity)
        default:
            return false
        }
    }

    private static func decodeMoney(from c: KeyedDecodingContainer<Keys>) -> MoneyData {
        let cash = (try? c.decode(Int.self, forKey: .moneyOnhand)) ?? 0
        let vault: Int
        if let value = try? c.decode(Int.self, forKey: .vaultAmount) {
            vault = value
        } else if let value = try? c.decode(Int.self, forKey: .propertyVault) {
            vault = value
        } else if let money = try? c.nestedContainer(keyedBy: MoneyNestedKeys.self, forKey: .money) {
            vault = (try? money.decode(Int.self, forKey: .vault)) ?? 0
        } else {
            vault = 0
        }
        return MoneyData(
            cash: cash,
            vault: vault,
            points: (try? c.decode(Int.self, forKey: .points)) ?? 0,
            tokens: (try? c.decode(Int.self, forKey: .donator)) ?? 0,
            cayman: (try? c.decode(Int.self, forKey: .caymanBank)) ?? 0
        )
    }

    private static func decodeBattleStats(from c: KeyedDecodingContainer<Keys>) -> BattleStats {
        BattleStats(
            strength: (try? c.decode(Int.self, forKey: .strength)) ?? 0,
            defense: (try? c.decode(Int.self, forKey: .defense)) ?? 0,
            speed: (try? c.decode(Int.self, forKey: .speed)) ?? 0,
            dexterity: (try? c.decode(Int.self, forKey: .dexterity)) ?? 0
        )
    }

    private static func decodeAttacks(from c: KeyedDecodingContainer<Keys>) -> [AttackResult]? {
        guard let map = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .attacks) else {
            return nil
        }
        var results: [AttackResult] = []
        results.reserveCapacity(map.allKeys.count)
        for key in map.allKeys {
            guard let attack = try? map.nestedContainer(keyedBy: AttackKeys.self, forKey: key) else {
                return nil
            }
            guard let code = try? attack.decode(String.self, forKey: .code) else { continue }
            results.append(
                AttackResult(
                    code: code,
                    timestampStarted: try? attack.decode(Int.self, forKey: .timestampStarted),
                    timestampEnded: try? attack.decode(Int.self, forKey: .timestampEnded),
                    attackerId: try? attack.decode(Int.self, forKey: .attackerId),
                    attackerName: try? attack.decode(String.self, forKey: .attackerName),
                    defenderId: try? attack.decode(Int.self, forKey: .defenderId),
                    defenderName: try? attack.decode(String.self, forKey: .defenderName),
                    result: try? attack.decode(String.self, forKey: .result),
                    respect: try? attack.decode(Double.self, forKey: .respect)
                )
            )
        }
        return results.sorted { ($0.timestampEnded ?? 0) > ($1.timestampEnded ?? 0) }
    }

    private static func decodeProperties(from c: KeyedDecodingContainer<Keys>) -> [PropertyInfo]? {
        guard let map = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties) else {
            return nil
        }
        var results: [PropertyInfo] = []
        results.reserveCapacity(map.allKeys.count)
        for key in map.allKeys {
            guard let prop = try? map.nestedContainer(keyedBy: PropertyKeys.self, forKey: key) else {
                return nil
            }
            let rented = try? prop.nestedContainer(keyedBy: RentedKeys.self, forKey: .rented)
            results.append(
                PropertyInfo(
                    id: (try? prop.decode(Int.self, forKey: .propertyId)) ?? 0,
                    propertyType: (try? prop.decode(String.self, forKey: .property)) ?? "",
                    status: (try? prop.decode(String.self, forKey: .status)) ?? "",
                    cost: (try? prop.decode(Int.self, forKey: .cost)) ?? 0,
                    marketprice: (try? prop.decode(Int.self, forKey: .marketprice)) ?? 0,
                    happy: (try? prop.decode(Int.self, forKey: .happy)) ?? 0,
                    rented: rented != nil,
                    rentDaysLeft: rented.flatMap { try? $0.decode(Int.self, forKey: .daysLeft) }
                )
            )
        }
        return results.sorted { $0.id < $1.id }
    }

    private static func decodeStocks(from c: KeyedDecodingContainer<Keys>) -> [StockHolding] {
        guard let map = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .stocks) else {
            return []
        }
        var results: [StockHolding] = []
        results.reserveCapacity(map.allKeys.count)
        for key in map.allKeys {
            if let holding = try? map.decode(StockHolding.self, forKey: key) {
                results.append(holding)
            } else if (try? map.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)) == nil {
                // Mirror `json["stocks"] as? [String: [String: Any]]`: a non-object entry rejects the map.
                return []
            }
        }
        return results.sorted { $0.stockId < $1.stockId }
    }
}

/// Semantic contract for the v1 user snapshot. The evidence set is derived from
/// selections requested by `user.fast` and selections granted by `/key/info`.
enum UserSnapshotContract {
    static func isSatisfied(
        by json: [String: Any],
        requestedSelections: [String],
        grantedSelections: [String]?
    ) -> Bool {
        let requested = Set(requestedSelections)
        let available = grantedSelections.map { requested.intersection(Set($0)) } ?? requested
        guard !available.isEmpty else { return false }
        return available.contains { hasEvidence(for: $0, in: json) }
    }

    private static func hasEvidence(for selection: String, in json: [String: Any]) -> Bool {
        switch selection {
        case "basic", "profile":
            return json["name"] is String || json["player_id"] is NSNumber
        case "bars":
            return ["energy", "nerve", "life", "happy"].allSatisfy {
                json[$0] is [String: Any]
            }
        case "cooldowns", "travel", "properties", "stocks":
            return json[selection] is [String: Any]
        case "money":
            return ["money_onhand", "points", "cayman_bank", "vault_amount",
                    "property_vault", "networth"].contains { json[$0] != nil }
        case "battlestats":
            return ["strength", "defense", "speed", "dexterity"].contains {
                json[$0] is NSNumber
            }
        default:
            return false
        }
    }
}

private let requestedUserSelectionsKey = CodingUserInfoKey(rawValue: "requestedUserSelections")!

extension UserV2Payload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case organizedCrime, refills, education, bounties, bountiesTimestamp = "bounties_timestamp",
             bountiesDelay = "bounties_delay", notifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requested = decoder.userInfo[requestedUserSelectionsKey] as? Set<String> ?? []
        var malformed: [String] = []

        func section<Value: Decodable>(_ type: Value.Type, key: CodingKeys) -> UserV2Section<Value> {
            let selection = key.rawValue.lowercased()
            guard requested.contains(selection) else { return .unchanged }
            guard let value = try? container.decode(type, forKey: key) else {
                malformed.append(selection)
                return .unchanged
            }
            return .replace(value)
        }

        if !requested.contains("organizedcrime") {
            organizedCrime = .unchanged
        } else if container.contains(.organizedCrime),
                  (try? container.decodeNil(forKey: .organizedCrime)) == true {
            organizedCrime = .replace(nil)
        } else {
            if let error = try? container.decode(OrganizedCrimeAPIError.self, forKey: .organizedCrime),
               error.code == 27 {
                organizedCrime = .unavailable(message: error.error)
            } else {
                switch section(OrganizedCrime2.self, key: .organizedCrime) {
                case .unchanged: organizedCrime = .unchanged
                case .replace(let value): organizedCrime = .replace(value)
                }
            }
        }
        refills = section(Refills.self, key: .refills)
        education = section(EducationStatus.self, key: .education)
        bounties = section([Bounty].self, key: .bounties)
        bountiesTimestamp = try? container.decodeIfPresent(Int.self, forKey: .bountiesTimestamp)
        bountiesDelay = try? container.decodeIfPresent(Int.self, forKey: .bountiesDelay)
        notifications = section(TornNotifications.self, key: .notifications)
        malformedSelections = malformed
    }
}

private struct OrganizedCrimeAPIError: Decodable {
    let code: Int
    let error: String
}
