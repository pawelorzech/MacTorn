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

enum UserServiceResult<Value> {
    case success(Value, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case malformed(responseBytes: Int)
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
    let unreadMessages: Int?
    let recentAttacks: [AttackResult]?
}

struct UserV2Payload {
    let organizedCrime: OrganizedCrime2?
    let refills: Refills?
    let education: EducationStatus?
    let bounties: [Bounty]
    let notifications: TornNotifications?
}

protocol UserSnapshotServicing: Sendable {
    func load(_ url: URL) async throws -> UserHTTPResponse
    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> UserServiceResult<UserSnapshotPayload>
    func loadActivity(_ url: URL) async throws -> UserServiceResult<UserActivityPayload>
    func loadUserV2(_ url: URL) async throws -> UserServiceResult<UserV2Payload>
    func loadVirus(_ url: URL) async throws -> UserServiceResult<VirusProgramming?>
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
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return UserHTTPResponse(data: data, statusCode: http.statusCode)
    }

    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> UserServiceResult<UserSnapshotPayload> {
        await Task.detached(priority: .userInitiated) {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .malformed(responseBytes: data.count)
            }
            if let apiError = tornAPIError(in: json) {
                return .apiError(apiError, responseBytes: data.count)
            }
            guard UserSnapshotContract.isSatisfied(
                by: json,
                requestedSelections: requestedSelections,
                grantedSelections: grantedSelections
            ) else {
                return .malformed(responseBytes: data.count)
            }

            let snapshot: TornResponse
            do {
                snapshot = try JSONDecoder().decode(TornResponse.self, from: data)
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

            let money = Self.parseMoney(json)
            let battleStats = Self.parseBattleStats(json)
            let attacks = Self.parseAttacks(json)
            let properties = Self.parseProperties(json)
            let stocks = Self.parseStocks(json)

            return .success(
                UserSnapshotPayload(
                    snapshot: snapshot,
                    money: money,
                    battleStats: battleStats,
                    recentAttacks: attacks,
                    properties: properties,
                    stocks: stocks
                ),
                responseBytes: data.count
            )
        }.value
    }

    func loadActivity(_ url: URL) async throws -> UserServiceResult<UserActivityPayload> {
        let response = try await load(url)
        let data = response.data
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }

        let decoded = try? JSONDecoder().decode(TornResponse.self, from: data)
        // `TornResponse.recentEvents` / `.unreadMessagesCount` are non-optional and
        // collapse a *missing* key to `[]` / `0`. `UserActivityPayload` must instead
        // preserve the absent-vs-zero distinction the way `parseAttacks(_:)` does:
        // `AppState.fetchActivityData` only overwrites its state when the payload field
        // is non-nil, so a 200 body that simply omits `events` must report `nil` rather
        // than silently emptying the user's event list (issue #84).
        return .success(
            UserActivityPayload(
                events: Self.isPresent(json["events"]) ? decoded?.recentEvents : nil,
                unreadMessages: Self.isPresent(json["messages"]) ? decoded?.unreadMessagesCount : nil,
                recentAttacks: Self.parseAttacks(json)
            ),
            responseBytes: data.count
        )
    }

    /// True when a top-level JSON key is present and not `null`.
    private static func isPresent(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is NSNull)
    }

    func loadUserV2(_ url: URL) async throws -> UserServiceResult<UserV2Payload> {
        let response = try await load(url)
        let data = response.data
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }

        let decoder = JSONDecoder()
        var organizedCrime: OrganizedCrime2?
        if let dictionary = json["organizedCrime"] as? [String: Any],
           dictionary["id"] is Int,
           let encoded = try? JSONSerialization.data(withJSONObject: dictionary) {
            organizedCrime = try? decoder.decode(OrganizedCrime2.self, from: encoded)
        }

        var refills: Refills?
        if let dictionary = json["refills"] as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: dictionary) {
            refills = try? decoder.decode(Refills.self, from: encoded)
        }

        var education: EducationStatus?
        if let dictionary = json["education"] as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: dictionary) {
            education = try? decoder.decode(EducationStatus.self, from: encoded)
        }

        var bounties: [Bounty] = []
        if let array = json["bounties"] as? [[String: Any]],
           let encoded = try? JSONSerialization.data(withJSONObject: array) {
            bounties = (try? decoder.decode([Bounty].self, from: encoded)) ?? []
        }

        var notifications: TornNotifications?
        if let dictionary = json["notifications"] as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: dictionary) {
            notifications = try? decoder.decode(TornNotifications.self, from: encoded)
        }

        return .success(
            UserV2Payload(
                organizedCrime: organizedCrime,
                refills: refills,
                education: education,
                bounties: bounties,
                notifications: notifications
            ),
            responseBytes: data.count
        )
    }

    /// Decodes `/v2/user/virus`. A `null` virus is the normal "not programming anything"
    /// answer, not a failure — hence the double optional collapsing to `.success(nil)`.
    func loadVirus(_ url: URL) async throws -> UserServiceResult<VirusProgramming?> {
        let response = try await load(url)
        let data = response.data
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }
        guard let dictionary = json["virus"] as? [String: Any],
              let encoded = try? JSONSerialization.data(withJSONObject: dictionary),
              let virus = try? JSONDecoder().decode(VirusProgramming.self, from: encoded)
        else {
            return .success(nil, responseBytes: data.count)
        }
        return .success(virus, responseBytes: data.count)
    }

    private static func parseMoney(_ json: [String: Any]) -> MoneyData {
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

    private static func parseBattleStats(_ json: [String: Any]) -> BattleStats {
        BattleStats(
            strength: json["strength"] as? Int ?? 0,
            defense: json["defense"] as? Int ?? 0,
            speed: json["speed"] as? Int ?? 0,
            dexterity: json["dexterity"] as? Int ?? 0
        )
    }

    private static func parseAttacks(_ json: [String: Any]) -> [AttackResult]? {
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

    private static func parseProperties(_ json: [String: Any]) -> [PropertyInfo]? {
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

    private static func parseStocks(_ json: [String: Any]) -> [StockHolding] {
        guard let stocks = json["stocks"] as? [String: [String: Any]] else { return [] }
        return stocks.values.compactMap { stock in
            guard let data = try? JSONSerialization.data(withJSONObject: stock) else {
                return nil
            }
            return try? JSONDecoder().decode(StockHolding.self, from: data)
        }.sorted { $0.stockId < $1.stockId }
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
