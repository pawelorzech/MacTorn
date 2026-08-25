import Foundation

// MARK: - Torn API Registry (Etap A)
//
// A single, typed catalog of every Torn API endpoint and selection MacTorn calls.
// This is the source of truth the rest of the app derives from instead of keeping
// several hand-maintained lists:
//
//   1. Request building        — `TornEndpoint.url(key:parameter:granted:)`, reached
//                                 through `AppState.endpointURL(_:parameter:key:)`
//   2. Request gating           — `TornEndpointGate` (what this key may ask for)
//   3. "API Data Usage" screen  — the metadata fields below (Diagnostics, Etap F)
//   4. README documentation     — `TornEndpointRegistry.markdownTable()`, which a test
//                                 asserts is byte-identical to README's table
//
// AppState builds every request through the registry (ISA backlog A-02, done). The
// legacy `TornAPI` builders in `TornModels.swift` are no longer a code path; they stay
// as the independent second implementation that `TornEndpointTests` compares each
// registry URL against, so a change to one and not the other fails the build.

/// Torn API major version. v1 is frozen but not sunset: Torn's own OpenAPI document
/// states that a v2 selection "will default to the API v1 version" where it has not been
/// migrated, and every selection MacTorn relies on still returns its v1 shape. v2 is the
/// actively developed surface. Checked against spec version 6.13.1 on 2026-08-26.
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

/// Groups endpoints for request/record accounting (PollingCoordinator, Etap D) and
/// the Diagnostics screen (Etap F). Row-based budgets are tracked per category
/// because the 50k/day cap is itself per-category.
enum TornBudgetCategory: String, Equatable, Sendable, CaseIterable {
    case core       // user fast poll + combined v2 user
    case activity   // events / messages / attacks (row-based)
    case faction    // faction basic/chain, ranked wars, news
    case market     // watchlist item listings
    case forum      // watched threads / category threads (row-based)
    case metadata   // slow-changing global lookups (stock names)
}

/// Client-side cache/throttle policy. Torn itself may serve cached data for up to
/// ~30s, so `.none` still fetches with `reloadIgnoringLocalAndRemoteCacheData` to
/// avoid the URL cache stacking a second layer on top.
enum TornCachePolicy: Equatable, Sendable {
    case none
    case throttle(seconds: TimeInterval)
}

/// Torn API key access tiers. A key is issued at one of these levels and each
/// selection requires a minimum tier.
///
/// NOTE: the authoritative per-selection requirement is only knowable at runtime
/// from the `key/?selections=info` endpoint, which is wired in Etap C (key
/// validation + onboarding — currently deferred; see ISA backlog C-01). The
/// `minimumAccessLevel` declared on each endpoint below is a documented best-effort
/// used for onboarding disclosure copy, NOT a hard gate. It is intentionally
/// conservative (never under-states the requirement).
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
    let selections: [String]
    /// Additional fixed query items beyond `key`/`selections`/`limit` (e.g. news `cat`).
    let extraQuery: [String: String]
    /// Best-effort minimum key access level (see `TornKeyAccessLevel` caveat).
    let minimumAccessLevel: TornKeyAccessLevel
    let purpose: String
    /// Human-readable polling cadence.
    let cadence: String
    let dataShape: TornDataShape
    /// Row cap requested per call for row-based endpoints (used for the rows/day
    /// estimate). `nil` for point-in-time endpoints.
    let recordLimit: Int?
    /// Whether `recordLimit` is also sent as a `limit` query item. `forum.thread` accepts
    /// no `limit`, so for that one alone the accounting and the URL diverge.
    let sendsLimitQuery: Bool
    let cachePolicy: TornCachePolicy
    let budget: TornBudgetCategory
    /// true = part of the app's core (an outage degrades the whole app);
    /// false = optional module the user can live without.
    let critical: Bool
    /// true when the endpoint only returns anything for a key whose owner is in a
    /// faction. `/key/info` reports `user.faction_id`, so MacTorn can skip these
    /// outright for a factionless player instead of spending a request every poll on a
    /// call that can only come back empty.
    var requiresFaction: Bool = false

    var isParameterized: Bool { path.contains("{param}") }

    /// Rows fetched per call — the unit of the 50k/day/category budget. Point-in-time
    /// endpoints count as 1 "request" but 0 row-based records.
    var recordsPerCall: Int { dataShape == .rowBased ? (recordLimit ?? 0) : 0 }

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

    /// Builds the request URL with the same percent-encoding + sorted query items as
    /// the legacy `TornAPI` builders. `parameter` fills a `{param}` placeholder and is
    /// required for parameterized endpoints (returns nil if missing).
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
        if sendsLimitQuery, let recordLimit {
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
            extraQuery: [:],
            minimumAccessLevel: .limited,
            purpose: "Live Energy/Nerve/Happy/Life bars, drug/medical/booster cooldowns, travel status, money & net worth, battle stats, properties and stock holdings.",
            cadence: "Every refresh interval (default 30s; 15s aggressive)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .none,
            budget: .core,
            critical: true
        ),
        TornEndpoint(
            id: "user.v2",
            name: "User v2 (combined)",
            version: .v2,
            path: "https://api.torn.com/v2/user",
            selections: ["organizedcrime", "refills", "education", "bounties", "notifications"],
            extraQuery: [:],
            minimumAccessLevel: .limited,
            purpose: "Own Organized Crime 2.0 status, daily refills remaining, in-progress education timer, bounties placed on you, and the unread message/event/award/competition counters.",
            cadence: "Every refresh interval (rides the fast poll)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .none,
            budget: .core,
            critical: false
        ),
        TornEndpoint(
            id: "user.virus",
            name: "Virus programming",
            version: .v2,
            path: "https://api.torn.com/v2/user/virus",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .minimal,
            purpose: "The virus currently being written and the moment it finishes, for the countdown and the ready alert.",
            cadence: "On demand — re-read only once the known finish time has passed (≥30 min apart)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .throttle(seconds: 1_800),
            budget: .core,
            critical: false
        ),
        TornEndpoint(
            id: "user.activity",
            name: "User activity",
            version: .v1,
            path: "https://api.torn.com/user/",
            selections: ["events", "attacks"],
            extraQuery: [:],
            minimumAccessLevel: .limited,
            purpose: "Events feed and recent attacks (display-only). The unread message count moved to the point-in-time `notifications` selection, which costs no rows.",
            cadence: "≥5 min (self-throttled; hard row limit)",
            dataShape: .rowBased,
            recordLimit: 25,
            sendsLimitQuery: true,
            cachePolicy: .throttle(seconds: 300),
            budget: .activity,
            critical: false
        ),
        TornEndpoint(
            id: "faction.basic",
            name: "Faction basic + chain",
            version: .v1,
            path: "https://api.torn.com/faction/",
            selections: ["basic", "chain"],
            extraQuery: [:],
            minimumAccessLevel: .limited,
            purpose: "Faction identity and the live chain counter/timeout that drives the chain-expiring alert.",
            cadence: "Every refresh interval (rides the fast poll)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .none,
            budget: .faction,
            critical: false,
            requiresFaction: true
        ),
        TornEndpoint(
            id: "faction.rankedwars",
            name: "Faction ranked wars",
            version: .v2,
            path: "https://api.torn.com/v2/faction/rankedwars",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .limited,
            purpose: "Active ranked war progress (your faction vs. the opponent).",
            cadence: "≥5 min (throttled — large, slow-changing payload)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .throttle(seconds: 300),
            budget: .faction,
            critical: false,
            requiresFaction: true
        ),
        TornEndpoint(
            id: "faction.news",
            name: "Faction news",
            version: .v2,
            path: "https://api.torn.com/v2/faction/news",
            selections: [],
            extraQuery: ["cat": "main"],
            minimumAccessLevel: .limited,
            purpose: "Recent faction news feed.",
            cadence: "≥5 min (throttled; hard row limit)",
            dataShape: .rowBased,
            recordLimit: 25,
            sendsLimitQuery: true,
            cachePolicy: .throttle(seconds: 300),
            budget: .faction,
            critical: false,
            requiresFaction: true
        ),
        TornEndpoint(
            id: "market.item",
            name: "Item market",
            version: .v2,
            path: "https://api.torn.com/v2/market/{param}",
            selections: ["itemmarket", "bazaar"],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "Lowest item-market listings for each watchlist item, used to drive price alerts.",
            cadence: "Watchlist refresh (manual + on price-alert timer)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .none,
            budget: .market,
            critical: false
        ),
        TornEndpoint(
            id: "torn.stocks",
            name: "Stock metadata",
            version: .v1,
            path: "https://api.torn.com/torn/",
            selections: ["stocks"],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "Global stock names/acronyms used to label the user's stock holdings (slow-changing reference data).",
            cadence: "Rarely (cached; refreshed on demand)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .throttle(seconds: 86_400),
            budget: .metadata,
            critical: false
        ),
        TornEndpoint(
            id: "torn.items",
            name: "Item catalog",
            version: .v2,
            path: "https://api.torn.com/v2/torn/items",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "Names for every Torn item, so the watchlist can be searched by name and priced items are labelled rather than numbered.",
            cadence: "Rarely (cached for a week; refreshed on demand)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .throttle(seconds: 604_800),
            budget: .metadata,
            critical: false
        ),
        TornEndpoint(
            id: "forum.thread",
            name: "Forum thread",
            version: .v2,
            path: "https://api.torn.com/v2/forum/{param}/thread",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "Post count of a watched forum thread, to alert on new replies.",
            cadence: "Forum poll (opt-in feature)",
            dataShape: .rowBased,
            recordLimit: 20,
            sendsLimitQuery: false,
            cachePolicy: .throttle(seconds: 300),
            budget: .forum,
            critical: false
        ),
        TornEndpoint(
            id: "forum.threads",
            name: "Forum category threads",
            version: .v2,
            path: "https://api.torn.com/v2/forum/{param}/threads",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "Thread list of a watched forum category, to alert on new threads.",
            cadence: "Forum poll (opt-in feature)",
            dataShape: .rowBased,
            recordLimit: 20,
            sendsLimitQuery: true,
            cachePolicy: .throttle(seconds: 300),
            budget: .forum,
            critical: false
        ),
        TornEndpoint(
            id: "key.info",
            name: "Key info",
            version: .v2,
            path: "https://api.torn.com/v2/key/info",
            selections: [],
            extraQuery: [:],
            minimumAccessLevel: .publicOnly,
            purpose: "One-off validation of the API key: its access level/type, the owner's ID, and which selections it can read — used by onboarding's Test Connection. Never polled.",
            cadence: "On demand (Test Connection / key change)",
            dataShape: .pointInTime,
            recordLimit: nil,
            sendsLimitQuery: false,
            cachePolicy: .none,
            budget: .core,
            critical: false
        ),
    ]

    static func endpoint(id: String) -> TornEndpoint? {
        all.first { $0.id == id }
    }

    static var critical: [TornEndpoint] { all.filter(\.critical) }
    static var optional: [TornEndpoint] { all.filter { !$0.critical } }

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

    /// A GitHub/README-ready markdown table generated from the registry. Kept in the
    /// codebase so README's "API Data Usage" section can be regenerated (and a test
    /// asserts the README row count matches `all.count`).
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
