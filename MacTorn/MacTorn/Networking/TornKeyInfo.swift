import Foundation

// MARK: - Key info (Etap C / ISC-16)
//
// Decodes the official Torn v2 `/key/info` endpoint — the ONLY authoritative source of
// what a key can actually access. Shape verified against the live OpenAPI spec
// (`https://www.torn.com/swagger/openapi.json`, `KeyInfoResponse`) on 2026-07-15:
//
//   { "info": {
//       "access":     { "level": Int, "type": String, "faction": Bool, "company": Bool,
//                       "log": { "custom_permissions": Bool, "available": [...] } },
//       "user":       { "id": Int, "faction_id": Int?, "company_id": Int? },
//       "selections": { "user": [String], "faction": [String], "market": [String],
//                       "property": [String], "torn": [String], "racing": [String],
//                       "forum": [String], "key": [String], "company": [String] } } }
//
// `access.type` is one of: "Custom", "Public Only", "Minimal Access", "Limited Access",
// "Full Access". A Custom key grants a hand-picked subset, so gating is driven by the
// per-category `selections` arrays (authoritative), NOT by `access.level` — a Custom key
// can, e.g., expose `bars` without `battlestats`.

/// The `info` object from `/key/info`. Only the fields MacTorn needs are modelled; the
/// `access.log` block is intentionally omitted (MacTorn reads no log categories).
struct TornKeyInfo: Decodable, Equatable, Sendable {
    let access: Access
    let user: User
    let selections: Selections

    struct Access: Decodable, Equatable, Sendable {
        let level: Int
        /// Raw Torn access-type label, shown verbatim to the user.
        let type: String
        let faction: Bool
        let company: Bool
    }

    struct User: Decodable, Equatable, Sendable {
        /// The key owner's own Torn ID. Shown to the user to confirm the right key;
        /// treated as PII — never logged, committed, or put in a diagnostics report.
        let id: Int
        let factionId: Int?
        let companyId: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case factionId = "faction_id"
            case companyId = "company_id"
        }
    }

    /// Per-category lists of the selection names this key can read.
    struct Selections: Decodable, Equatable, Sendable {
        let user: [String]
        let faction: [String]
        let market: [String]
        let property: [String]
        let torn: [String]
        let racing: [String]
        let forum: [String]
        let key: [String]
        let company: [String]

        /// The available selection names for a given key-info category.
        func names(for category: TornKeyInfo.Category) -> [String] {
            switch category {
            case .user: return user
            case .faction: return faction
            case .market: return market
            case .property: return property
            case .torn: return torn
            case .racing: return racing
            case .forum: return forum
            case .key: return key
            case .company: return company
            }
        }
    }

    /// The `selections` sub-object categories in `/key/info`.
    enum Category: String, CaseIterable, Sendable {
        case user, faction, market, property, torn, racing, forum, key, company
    }

    /// The wire wrapper: `/key/info` nests everything under `info`.
    struct Response: Decodable, Equatable, Sendable {
        let info: TornKeyInfo
    }
}

// MARK: - Validation result

/// Whether one registered endpoint is reachable with the validated key, and if not, why.
struct EndpointAvailability: Equatable, Sendable, Identifiable {
    var id: String { endpointID }
    let endpointID: String
    let name: String
    let critical: Bool
    let available: Bool
    /// Selection names the endpoint needs that the key lacks (empty when available).
    let missingSelections: [String]
}

/// The outcome of a successful `/key/info` call, ready for the onboarding UI.
struct KeyValidationResult: Equatable, Sendable {
    let accessType: String
    let accessLevel: Int
    /// PII — display only; never logged or reported.
    let playerID: Int
    let inFaction: Bool
    let availability: [EndpointAvailability]

    var allCriticalAvailable: Bool {
        availability.filter(\.critical).allSatisfy(\.available)
    }

    var unavailableCount: Int {
        availability.filter { !$0.available }.count
    }
}

/// UI state for the onboarding "Test Connection" flow. `failure` carries an
/// already-sanitized, user-facing message (from `TornAPIError.userMessage`), never a raw
/// payload.
enum KeyValidationState: Equatable, Sendable {
    case idle
    case validating
    case success(KeyValidationResult)
    case failure(String)
}

// MARK: - KeyValidator

/// Pure mapping from a decoded `TornKeyInfo` to per-endpoint availability, using the
/// endpoint registry as the source of truth for what each feature needs.
enum KeyValidator {

    /// Maps a registered endpoint to its `/key/info` selections category.
    static func category(for endpoint: TornEndpoint) -> TornKeyInfo.Category {
        let path = endpoint.path
        if path.contains("/faction") { return .faction }
        if path.contains("/market") { return .market }
        if path.contains("/forum") { return .forum }
        if path.contains("/torn") { return .torn }
        // Both the v1 `/user/` fast+activity calls and the v2 `/user` call.
        return .user
    }

    /// Availability of a single endpoint under a validated key. Endpoints that take no
    /// `selections` parameter are checked against their documented access tier and any
    /// dedicated permission bit exposed by `/key/info`.
    static func availability(of endpoint: TornEndpoint, given info: TornKeyInfo) -> EndpointAvailability {
        let required = endpoint.selections
        let missing: [String]
        if required.isEmpty {
            missing = []
        } else {
            let granted = Set(info.selections.names(for: category(for: endpoint)))
            missing = required.filter { !granted.contains($0) }
        }
        // Selection-bearing endpoints are governed by the authoritative selection list:
        // a Custom/Minimal key with one readable selection still gets a narrowed request.
        // Dedicated endpoints have no selection entry, so their documented tier is the
        // only capability signal `/key/info` gives us.
        let hasRequiredLevel = !endpoint.selections.isEmpty
            || info.access.level >= endpoint.minimumAccessLevel.rawValue
        let hasDedicatedFactionAccess = !endpoint.requiresFactionAPIAccess || info.access.faction
        let hasFaction = !endpoint.requiresFaction || info.user.factionId != nil
        return EndpointAvailability(endpointID: endpoint.id,
                                    name: endpoint.name,
                                    critical: endpoint.critical,
                                    available: missing.isEmpty && hasRequiredLevel
                                        && hasDedicatedFactionAccess && hasFaction,
                                    missingSelections: missing)
    }

    /// Full validation result across every registered endpoint.
    static func validate(_ info: TornKeyInfo,
                         endpoints: [TornEndpoint] = TornEndpointRegistry.all) -> KeyValidationResult {
        KeyValidationResult(
            accessType: info.access.type,
            accessLevel: info.access.level,
            playerID: info.user.id,
            inFaction: info.user.factionId != nil,
            availability: endpoints.map { availability(of: $0, given: info) }
        )
    }
}
