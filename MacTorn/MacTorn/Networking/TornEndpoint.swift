import Foundation

// A single typed catalog of every Torn API endpoint and selection MacTorn calls. Request building
// (`TornEndpoint.url(key:parameter:granted:)`), request gating (`TornEndpointGate`), the "API Data
// Usage" screen and the README table (`TornEndpointRegistry.markdownTable()`, which a test asserts
// is byte-identical to README's) all derive from it instead of hand-maintained lists.

/// Torn API major version. v1 is frozen but not sunset: Torn's own OpenAPI document
/// states that a v2 selection "will default to the API v1 version" where it has not been
/// migrated, and every selection MacTorn relies on still returns its v1 shape. v2 is the
/// actively developed surface. Reviewed against spec version 6.13.8 on 2026-10-20.
enum TornAPIVersion: String, Equatable, Sendable {
    case v1
    case v2
}

/// Whether a response is a point-in-time snapshot or row-based cloud data.
///
/// Row-based categories (events, attacks, faction news, forum posts) count against
/// Torn's **50,000-rows/day-per-category** cap — the limit behind error code 14
/// ("Daily read limit reached"), which is entirely separate from the
/// 100-requests/minute rate limit. Point-in-time selections (bars, cooldowns, money…)
/// do not touch that cap and are safe to poll fast.
enum TornDataShape: String, Equatable, Sendable {
    case pointInTime
    case rowBased
}

/// Groups endpoints for request accounting and the Diagnostics screen. Row-based budgets are
/// tracked per category because the 50k/day cap is itself per-category.
enum TornBudgetCategory: String, Equatable, Sendable, CaseIterable {
    case core       // user fast poll + combined v2 user
    case activity   // events / messages / attacks (row-based)
    case faction    // faction basic/chain, ranked wars, news
    case market     // watchlist item listings
    case forum      // watched threads / category threads (row-based)
    case metadata   // slow-changing global lookups (stock names)
}

/// Torn API key access tiers. A key is issued at one of these levels and each selection requires a
/// minimum tier. The authoritative per-selection requirement is only knowable at runtime from
/// `/key/info`; the declared `minimumAccessLevel` also gates dedicated endpoints whose access is not
/// represented by a `selections` query parameter.
enum TornKeyAccessLevel: Int, Comparable, CaseIterable, Sendable {
    case publicOnly = 1
    case minimal = 2
    case limited = 3
    case full = 4

    var label: String {
        switch self {
        case .publicOnly: return "Public Only"
        case .minimal: return "Minimal Access"
        case .limited: return "Limited Access"
        case .full: return "Full Access"
        }
    }

    static func < (lhs: TornKeyAccessLevel, rhs: TornKeyAccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One typed endpoint description. `path` may contain a single `{param}` placeholder
/// (market item id, forum thread/category id); such entries are `parameterized`.
struct TornEndpoint: Identifiable, Equatable, Sendable {
    /// Stable slug, e.g. "user.fast". Never renumbered.
    let id: String
    let name: String
    let version: TornAPIVersion
    /// Absolute URL without the query string, e.g. "https://api.torn.com/user/".
    let path: String
    /// Selection names; empty when the endpoint takes no `selections` parameter.
    var selections: [String] = []
    /// Additional fixed query items beyond `key`/`selections`/`limit` (e.g. news `cat`).
    var extraQuery: [String: String] = [:]
    /// Best-effort minimum key access level (see `TornKeyAccessLevel` caveat).
    let minimumAccessLevel: TornKeyAccessLevel
    let purpose: String
    /// Human-readable polling cadence.
    let cadence: String
    /// Rows asked for per call, sent as `limit`, for row-based endpoints — the unit of the
    /// 50,000-rows/day/category budget. `nil` marks a point-in-time endpoint.
    var recordLimit: Int? = nil
    let budget: TornBudgetCategory
    /// true = part of the app's core (an outage degrades the whole app);
    /// false = optional module the user can live without.
    let critical: Bool
    /// Capability names reported by `/key/info` for dedicated endpoints that do not
    /// send a `selections` query parameter. Enforced for Custom keys only.
    var requiredCapabilities: [String] = []
    /// true when the endpoint only returns anything for a key whose owner is in a
    /// faction. `/key/info` reports `user.faction_id`, so MacTorn can skip these
    /// outright for a factionless player instead of spending a request every poll on a
    /// call that can only come back empty.
    var requiresFaction: Bool = false
    /// true when Torn additionally requires the key's dedicated faction-API permission.
    /// `/key/info` exposes this separately as `access.faction`; faction membership alone
    /// does not grant it.
    var requiresFactionAPIAccess: Bool = false

    /// Shortest gap between two sends, for endpoints MacTorn reads on its own schedule
    /// rather than every poll. `nil` = every time it is asked.
    var minimumInterval: TimeInterval? = nil

    /// The `/key/info` selections category that grants this endpoint.
    var keyCategory: TornKeyInfo.Category {
        if path.contains("/faction") { return .faction }
        if path.contains("/market") { return .market }
        if path.contains("/forum") { return .forum }
        if path.contains("/torn") { return .torn }
        return .user
    }

    var isParameterized: Bool { path.contains("{param}") }

    var dataShape: TornDataShape { recordLimit == nil ? .pointInTime : .rowBased }

    var recordsPerCall: Int { recordLimit ?? 0 }

    /// The selections this endpoint should actually ask for, given what `/key/info` says
    /// the key can read. `granted == nil` (key never validated) means ask for everything.
    ///
    /// Narrowing matters because Torn rejects the *whole request* with error 16 when it
    /// contains one selection the key cannot read. Asking a Minimal-access key for
    /// `battlestats` therefore does not cost you battle stats — it costs you the bars,
    /// the cooldowns and the travel timer in the same call. Trimming the request to what
    /// the key can serve turns a total failure into a partial answer.
    func resolvedSelections(granted: Set<String>?) -> [String] {
        guard let granted, !selections.isEmpty else { return selections }
        return selections.filter { granted.contains($0) }
    }

    /// Builds the request URL with percent-encoding and sorted query items. `parameter` fills a
    /// `{param}` placeholder and is required for parameterized endpoints (returns nil if missing).
    ///
    /// Returns nil when `granted` rules out every selection the endpoint needs — there is
    /// no request left to make, and the caller should skip rather than send an empty one.
    func url(key: String, parameter: Int? = nil, granted: Set<String>? = nil) -> URL? {
        var resolvedPath = path
        if isParameterized {
            guard let parameter else { return nil }
            resolvedPath = resolvedPath.replacingOccurrences(of: "{param}", with: String(parameter))
        }
        var query: [String: String] = ["key": key, "comment": TornAPIClient.comment]
        if !selections.isEmpty {
            let usable = resolvedSelections(granted: granted)
            guard !usable.isEmpty else { return nil }
            query["selections"] = usable.joined(separator: ",")
        }
        if let recordLimit {
            query["limit"] = String(recordLimit)
        }
        for (name, value) in extraQuery {
            query[name] = value
        }
        guard var comps = URLComponents(string: resolvedPath) else { return nil }
        comps.queryItems = query
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return comps.url
    }
}

/// The catalog. Order is display order (core first).
enum TornEndpointRegistry {
    static let all: [TornEndpoint] = [
        TornEndpoint(
            id: "user.fast",
            name: "User (fast poll)",
            version: .v1,
            path: "https://api.torn.com/user/",
            selections: ["basic", "bars", "cooldowns", "travel", "profile", "money", "battlestats", "properties", "stocks"],
            minimumAccessLevel: .limited,
            purpose: "Live Energy/Nerve/Happy/Life bars, drug/medical/booster cooldowns, travel status, money & net worth, battle stats, properties and stock holdings.",
            cadence: "Every refresh interval (default 30s; 15s aggressive)",
            budget: .core,
            critical: true
        ),
        TornEndpoint(
            id: "user.v2",
            name: "User v2 (combined)",
            version: .v2,
            path: "https://api.torn.com/v2/user",
            selections: ["organizedcrime", "refills", "education", "bounties", "notifications"],
            minimumAccessLevel: .minimal,
            purpose: "Own Organized Crime 2.0 status, daily refills remaining, in-progress education timer, bounties placed on you, and the unread message/event/award/competition counters.",
            cadence: "Every refresh interval (rides the fast poll)",
            budget: .core,
            critical: false
        ),
        TornEndpoint(
            id: "user.virus",
            name: "Virus programming",
            version: .v2,
            path: "https://api.torn.com/v2/user/virus",
            minimumAccessLevel: .minimal,
            purpose: "The virus currently being written and the moment it finishes, for the countdown and the ready alert.",
            cadence: "On demand; re-read once the known finish time has passed, at least 30 min apart",
            budget: .core,
            critical: false,
            minimumInterval: 1_800
        ),
        TornEndpoint(
            id: "user.activity",
            name: "User activity",
            version: .v1,
            path: "https://api.torn.com/user/",
            selections: ["events", "attacks"],
            minimumAccessLevel: .limited,
            purpose: "Events feed and recent attacks (display-only). The unread message count now comes from the point-in-time `notifications` selection, which costs no rows.",
            cadence: "≥5 min (self-throttled; hard row limit)",
            recordLimit: 25,
            budget: .activity,
            critical: false,
            minimumInterval: 300
        ),
        TornEndpoint(
            id: "faction.basic",
            name: "Faction basic + chain",
            version: .v1,
            path: "https://api.torn.com/faction/",
            selections: ["basic", "chain"],
            minimumAccessLevel: .limited,
            purpose: "Faction identity and the live chain counter/timeout that drives the chain-expiring alert.",
            cadence: "Every refresh interval (rides the fast poll)",
            budget: .faction,
            critical: false,
            requiresFaction: true
        ),
        TornEndpoint(
            id: "faction.rankedwars",
            name: "Faction ranked wars",
            version: .v2,
            path: "https://api.torn.com/v2/faction/rankedwars",
            minimumAccessLevel: .publicOnly,
            purpose: "Active ranked war progress (your faction vs. the opponent).",
            cadence: "≥5 min (throttled; large, slow-changing payload)",
            budget: .faction,
            critical: false,
            requiresFaction: true,
            minimumInterval: 300
        ),
        TornEndpoint(
            id: "faction.news",
            name: "Faction news",
            version: .v2,
            path: "https://api.torn.com/v2/faction/news",
            extraQuery: ["cat": "main"],
            minimumAccessLevel: .minimal,
            purpose: "Recent faction news feed.",
            cadence: "≥5 min (throttled; hard row limit)",
            recordLimit: 25,
            budget: .faction,
            critical: false,
            requiredCapabilities: ["news"],
            requiresFaction: true,
            requiresFactionAPIAccess: true,
            minimumInterval: 300
        ),
        TornEndpoint(
            id: "market.item",
            name: "Item market",
            version: .v2,
            path: "https://api.torn.com/v2/market/{param}/itemmarket",
            minimumAccessLevel: .publicOnly,
            purpose: "Lowest item-market listings for each watchlist item, used to drive price alerts.",
            cadence: "Watchlist refresh (manual + on price-alert timer)",
            budget: .market,
            critical: false,
            requiredCapabilities: ["itemmarket"]
        ),
        TornEndpoint(
            id: "torn.stocks",
            name: "Stock metadata",
            version: .v1,
            path: "https://api.torn.com/torn/",
            selections: ["stocks"],
            minimumAccessLevel: .publicOnly,
            purpose: "Global stock names/acronyms used to label the user's stock holdings (slow-changing reference data).",
            cadence: "Rarely (cached; refreshed on demand)",
            budget: .metadata,
            critical: false
        ),
        TornEndpoint(
            id: "torn.items",
            name: "Item catalog",
            version: .v2,
            path: "https://api.torn.com/v2/torn/items",
            minimumAccessLevel: .publicOnly,
            purpose: "Names for every Torn item, so the watchlist can be searched by name and priced items are labelled rather than numbered.",
            cadence: "Rarely (cached for a week; refreshed on demand)",
            budget: .metadata,
            critical: false,
            requiredCapabilities: ["items"]
        ),
        TornEndpoint(
            id: "forum.thread",
            name: "Forum thread",
            version: .v2,
            path: "https://api.torn.com/v2/forum/{param}/thread",
            minimumAccessLevel: .publicOnly,
            purpose: "Post count of a watched forum thread, to alert on new replies.",
            cadence: "Forum poll (opt-in feature)",
            budget: .forum,
            critical: false,
            requiredCapabilities: ["thread"]
        ),
        TornEndpoint(
            id: "forum.threads",
            name: "Forum category threads",
            version: .v2,
            path: "https://api.torn.com/v2/forum/{param}/threads",
            minimumAccessLevel: .publicOnly,
            purpose: "Thread list of a watched forum category, to alert on new threads.",
            cadence: "Forum poll (opt-in feature)",
            recordLimit: 20,
            budget: .forum,
            critical: false,
            requiredCapabilities: ["threads"]
        ),
        TornEndpoint(
            id: "key.info",
            name: "Key info",
            version: .v2,
            path: "https://api.torn.com/v2/key/info",
            minimumAccessLevel: .publicOnly,
            purpose: "One-off validation of the API key: its access level/type, the owner's ID, and which selections it can read, for onboarding's Test Connection. Never polled.",
            cadence: "On demand (Test Connection / key change)",
            budget: .core,
            critical: false
        ),
    ] + companion

    static func endpoint(id: String) -> TornEndpoint? {
        endpointsByID[id]
    }

    /// O(1) lookup over the registry; it sits on the request hot path.
    private static let endpointsByID: [String: TornEndpoint] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Distinct selections across all endpoints, for onboarding disclosure.
    static var allSelections: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for endpoint in all {
            for selection in endpoint.selections where !seen.contains(selection) {
                seen.insert(selection)
                ordered.append(selection)
            }
        }
        return ordered
    }

    /// Highest access level any endpoint requires — the level a key must have to
    /// unlock every MacTorn module.
    static var requiredAccessLevel: TornKeyAccessLevel {
        all.map(\.minimumAccessLevel).max() ?? .publicOnly
    }

    /// A GitHub/README-ready markdown table generated from the registry. A test asserts README's
    /// table matches it.
    static func markdownTable() -> String {
        var rows = ["| Endpoint | API | Selections | Data | Cadence | Rows/call | Budget | Critical | Purpose |",
                    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for e in all {
            let sel = e.selections.isEmpty ? "—" : e.selections.joined(separator: ", ")
            let rows_ = e.dataShape == .rowBased ? "\(e.recordsPerCall)" : "—"
            let shape = e.dataShape == .rowBased ? "row-based" : "point-in-time"
            rows.append("| \(e.name) | \(e.version.rawValue) | \(sel) | \(shape) | \(e.cadence) | \(rows_) | \(e.budget.rawValue) | \(e.critical ? "yes" : "no") | \(e.purpose) |")
        }
        return rows.joined(separator: "\n")
    }
}
