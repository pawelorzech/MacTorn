import XCTest
@testable import MacTorn

// Independent URL oracle, intentionally not derived from the production registry.
// MARK: - API Configuration
enum TornAPI {
    static let baseURL = "https://api.torn.com/user/"
    static let factionURL = "https://api.torn.com/faction/"
    static let marketURL = "https://api.torn.com/market/"
    static let tornURL = "https://api.torn.com/torn/"

    /// Fast poll: only point-in-time selections. Deliberately EXCLUDES the row-based
    /// cloud categories (`events`, `attacks`) — those count against Torn's 50,000-
    /// rows/day-per-category cap (error code 14 "Daily read limit reached"), which is
    /// a separate limit from the 100-requests/minute rate limit. Pulling a full
    /// `events`/`attacks` page every 30 s, 24/7 blows past 50k rows/day ~5×. Row-based
    /// data now lives on `activityURL` below (slow cadence + hard row limit).
    static let selections = "basic,bars,cooldowns,travel,profile,money,battlestats,properties,stocks"

    /// Slow poll: the row-based / display-only categories. Capped with `limit` and
    /// fetched every few minutes so each category stays well under 50k rows/day.
    ///
    /// `messages` used to be here purely to produce one unread count, at the price of 25
    /// rows a call against the daily cap. That count now comes free from the point-in-time
    /// `notifications` selection on the v2 poll, so this call carries a third fewer rows.
    static let activitySelections = "events,attacks"
    /// Rows per category per activity call. The UI only ever shows a handful, so 25 is
    /// generous; at a 5-minute cadence that is 25 × 288 ≈ 7,200 rows/day/category.
    static let activityRowLimit = 25

    /// Build a Torn API URL with proper percent-encoding via URLComponents/URLQueryItem.
    /// String interpolation (the previous approach) would silently mangle keys that
    /// happen to contain `&`, `=`, or whitespace if pasted with junk.
    ///
    /// Every request carries `comment=MacTorn` (see `TornAPIClient.comment`), so the
    /// key owner can tell MacTorn's traffic apart from every other tool sharing their
    /// key in Torn's own key log.
    fileprivate static func build(_ urlString: String, query: [String: String]) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        var query = query
        query["comment"] = TornAPIClient.comment
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return comps.url
    }

    static func url(for apiKey: String) -> URL? {
        build(baseURL, query: ["selections": selections, "key": apiKey])
    }

    /// Row-based activity call (events + messages + attacks) with a hard `limit` so
    /// it can never exhaust the 50k-rows/day category budget. Polled slowly.
    static func activityURL(for apiKey: String) -> URL? {
        build(baseURL, query: ["selections": activitySelections,
                               "limit": String(activityRowLimit),
                               "key": apiKey])
    }

    static func factionURL(for apiKey: String) -> URL? {
        // `crimes` dropped: OC 1.0 is dead (frozen history + Int/Bool decode break).
        // The player's own OC 2.0 comes from `userV2URL` instead.
        build(factionURL, query: ["selections": "basic,chain", "key": apiKey])
    }

    /// Combined API v2 `user` call. v2 accepts multiple selections in one request
    /// (verified live), so a single call covers organized crime, refills, education
    /// and bounties. v1 selections stay on the frozen v1 endpoints above.
    static let userV2Selections = "organizedcrime,refills,education,bounties,notifications"
    static func userV2URL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/user",
              query: ["selections": userV2Selections, "key": apiKey])
    }

    /// Official key-info endpoint (Etap C). Returns the key's access level/type, the
    /// owner's IDs, and the per-category selections the key can read — the authoritative
    /// source for onboarding validation. Called on demand only (never polled).
    static func keyInfoURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/key/info", query: ["key": apiKey])
    }

    /// Ranked wars use a dedicated v2 path (the combined `?selections=rankedwars,news`
    /// call returns code 21 because `news` requires a `cat` parameter).
    static func factionRankedWarsURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/faction/rankedwars", query: ["key": apiKey])
    }

    /// Faction news requires a category (`cat`); `main` is the general feed.
    /// `news` is a row-based cloud category (counts against the 50k-rows/day cap),
    /// so cap it with `limit` on top of the slow poll cadence.
    static func factionNewsURL(for apiKey: String, cat: String = "main") -> URL? {
        build("https://api.torn.com/v2/faction/news",
              query: ["cat": cat, "limit": String(activityRowLimit), "key": apiKey])
    }

    /// Item-market listings for one item.
    ///
    /// `bazaar` used to ride along here. It no longer carries prices: on API v2 the
    /// per-item `bazaar` selection returns a *directory* of the player bazaars stocking
    /// the item — `{id, name, is_open, weekly_customers}` — with no cost or quantity
    /// anywhere in the shape (`BazaarResponseSpecialized` in Torn's OpenAPI document,
    /// spec 6.13.1). Torn does not expose per-item bazaar prices on v2 at all, so asking
    /// for it bought a larger payload and nothing else.
    static func marketURL(itemId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/market/\(itemId)/itemmarket",
              query: ["key": apiKey])
    }

    /// Virus programming has no combinable `/user` selection — it is absent from Torn's
    /// `UserSelectionName` enum — so it needs its own path. Read rarely: the response is an
    /// absolute finish timestamp, and the countdown between reads is derived locally.
    static func userVirusURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/user/virus", query: ["key": apiKey])
    }

    /// The global item catalog. `cat` is deliberately omitted: the default category is
    /// "All", which is the only one that returns every item, and its details are stripped —
    /// exactly the trade MacTorn wants, since it needs names and nothing else.
    static func tornItemsURL(for apiKey: String) -> URL? {
        build("https://api.torn.com/v2/torn/items", query: ["key": apiKey])
    }

    static func tornStocksURL(for apiKey: String) -> URL? {
        build(tornURL, query: ["selections": "stocks", "key": apiKey])
    }

    static func forumThreadURL(threadId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(threadId)/thread", query: ["key": apiKey])
    }

    /// Unlike a single thread, a category listing accepts `limit` — and defaults to 100.
    /// Sending the cap explicitly is what makes the row accounting honest: without it the
    /// registry booked 20 rows for a call that was pulling five times that.
    static func forumCategoryThreadsURL(categoryId: Int, apiKey: String) -> URL? {
        build("https://api.torn.com/v2/forum/\(categoryId)/threads",
              query: ["key": apiKey, "limit": String(forumCategoryRowLimit)])
    }

    /// Threads fetched per category check. The alert only needs to spot ids it has not
    /// seen, and a busy category turns over far fewer than 20 threads in a poll interval.
    static let forumCategoryRowLimit = 20
}

/// Etap A — the typed registry must stay in lockstep with the legacy `TornAPI`
/// builders (single source of truth) and its metadata must be internally consistent.
final class TornEndpointTests: XCTestCase {

    private let key = "exampleKey123456"
    private let sampleId = 4242

    // MARK: - Contract: registry URL == legacy TornAPI builder

    /// Every registry entry must produce the byte-identical URL of the `TornAPI`
    /// function AppState actually calls, so the catalog can never silently drift.
    func testRegistryURLsMatchLegacyBuilders() {
        func assertMatch(_ id: String, _ expected: URL?, parameter: Int? = nil,
                         file: StaticString = #filePath, line: UInt = #line) {
            let endpoint = TornEndpointRegistry.endpoint(id: id)
            XCTAssertNotNil(endpoint, "missing endpoint \(id)", file: file, line: line)
            XCTAssertEqual(endpoint?.url(key: key, parameter: parameter), expected,
                           "URL drift for \(id)", file: file, line: line)
        }

        assertMatch("user.fast", TornAPI.url(for: key))
        assertMatch("user.v2", TornAPI.userV2URL(for: key))
        assertMatch("user.activity", TornAPI.activityURL(for: key))
        assertMatch("user.virus", TornAPI.userVirusURL(for: key))
        assertMatch("faction.basic", TornAPI.factionURL(for: key))
        assertMatch("faction.rankedwars", TornAPI.factionRankedWarsURL(for: key))
        assertMatch("faction.news", TornAPI.factionNewsURL(for: key))
        assertMatch("market.item", TornAPI.marketURL(itemId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("torn.stocks", TornAPI.tornStocksURL(for: key))
        assertMatch("torn.items", TornAPI.tornItemsURL(for: key))
        assertMatch("forum.thread", TornAPI.forumThreadURL(threadId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("forum.threads", TornAPI.forumCategoryThreadsURL(categoryId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("key.info", TornAPI.keyInfoURL(for: key))
        let additions: [(String, String, [String: String])] = [
            ("user.recruiting", "user/organizedcrimes", [:]),
            ("user.stocksv2", "user/stocks", [:]),
            ("torn.stocksv2", "torn/stocks", [:]),
            ("user.competition", "user/competition", [:]),
            ("torn.elimination", "torn/elimination", [:]),
            ("user.trades", "user/trades", ["cat": "ongoing"]),
            ("user.trade", "user/4242/trade", [:]),
            ("torn.shops", "torn/items", [:]),
            ("faction.warfareranked", "faction/warfareranked", ["limit": "20", "sort": "DESC"]),
            ("faction.warfareraids", "faction/warfareraids", ["limit": "20", "sort": "DESC"]),
            ("faction.warfareterritory", "faction/warfareterritory", ["limit": "20", "sort": "DESC"]),
            ("faction.warfarechains", "faction/warfarechains", ["cat": "complete", "limit": "20", "sort": "DESC"]),
            ("faction.dirtybombs", "faction/dirtybombs", [:])
        ]
        for (id, path, parameters) in additions {
            var query = parameters
            query["key"] = key
            assertMatch(id, TornAPI.build("https://api.torn.com/v2/" + path, query: query),
                        parameter: id == "user.trade" ? sampleId : nil)
        }

    }

    /// The contract test above is only meaningful if it covers every endpoint.
    func testEveryEndpointIsCoveredByContract() {
        XCTAssertEqual(TornEndpointRegistry.all.count, 26,
                       "add the new endpoint to testRegistryURLsMatchLegacyBuilders too")
    }

    // MARK: - URL building

    func testParameterizedEndpointRequiresParameter() {
        let market = TornEndpointRegistry.endpoint(id: "market.item")!
        XCTAssertNil(market.url(key: key), "parameterized endpoint must return nil without a parameter")
        XCTAssertNotNil(market.url(key: key, parameter: sampleId))
    }

    func testNonParameterizedEndpointIgnoresParameter() {
        let fast = TornEndpointRegistry.endpoint(id: "user.fast")!
        XCTAssertEqual(fast.url(key: key), fast.url(key: key, parameter: 99))
    }

    func testKeyIsAlwaysPresentInQuery() {
        for endpoint in TornEndpointRegistry.all {
            let url = endpoint.url(key: key, parameter: endpoint.isParameterized ? sampleId : nil)
            XCTAssertNotNil(url)
            XCTAssertTrue(url!.query!.contains("key=\(key)"), "\(endpoint.id) missing key")
        }
    }

    // MARK: - Metadata invariants

    func testIDsAreUnique() {
        let ids = TornEndpointRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate endpoint id")
    }

    func testRowBasedEndpointsDeclareARecordLimit() {
        for endpoint in TornEndpointRegistry.all where endpoint.dataShape == .rowBased {
            XCTAssertNotNil(endpoint.recordLimit, "\(endpoint.id) is row-based but has no recordLimit")
            XCTAssertGreaterThan(endpoint.recordsPerCall, 0, "\(endpoint.id) records/call must be > 0")
        }
    }

    func testPointInTimeEndpointsCountZeroRows() {
        for endpoint in TornEndpointRegistry.all where endpoint.dataShape == .pointInTime {
            XCTAssertEqual(endpoint.recordsPerCall, 0, "\(endpoint.id) is point-in-time yet counts rows")
        }
    }

    @MainActor
    func testOngoingTradesArePointInTimeAndDoNotSpendActivityRows() throws {
        let trades = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.trades"))
        XCTAssertEqual(trades.dataShape, .pointInTime)
        XCTAssertNil(trades.recordLimit)
        XCTAssertFalse(trades.sendsLimitQuery)
        let coordinator = PollingCoordinator()
        for _ in 0..<1_000 { coordinator.record(trades) }
        XCTAssertEqual(coordinator.recordsInLastDay(.activity), 0)
    }

    /// `/forum/{threadId}/thread` returns one details object. Only the separate `/posts`
    /// route returns a 20-row page, so watching thread metadata must not spend cloud rows.
    func testForumThreadDetailsDoNotConsumeTheForumRowBudget() throws {
        let thread = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "forum.thread"))
        XCTAssertEqual(thread.dataShape, .pointInTime)
        XCTAssertEqual(thread.recordsPerCall, 0)
        XCTAssertNil(thread.recordLimit)
    }

    func testMarketUsesTheCanonicalItemMarketPath() throws {
        let endpoint = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "market.item"))
        let url = try XCTUnwrap(endpoint.url(key: key, parameter: sampleId))
        XCTAssertEqual(url.path, "/v2/market/4242/itemmarket")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "selections" })
    }

    func testSharedItemCatalogDeclaresCustomItemsCapability() throws {
        let endpoint = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "torn.items"))
        XCTAssertEqual(endpoint.requiredCapabilities, ["items"])
    }

    func testDedicatedEndpointAccessLevelsMatchTheOpenAPISpec() throws {
        XCTAssertEqual(try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.v2")).minimumAccessLevel,
                       .minimal)
        XCTAssertEqual(try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.virus")).minimumAccessLevel,
                       .minimal)
        XCTAssertEqual(try XCTUnwrap(TornEndpointRegistry.endpoint(id: "faction.rankedwars")).minimumAccessLevel,
                       .publicOnly)
        XCTAssertEqual(try XCTUnwrap(TornEndpointRegistry.endpoint(id: "faction.news")).minimumAccessLevel,
                       .minimal)
    }

    func testUserFastPollIsTheOnlyCriticalEndpoint() {
        XCTAssertEqual(TornEndpointRegistry.critical.map(\.id), ["user.fast"])
    }

    func testRequiredAccessLevelIsLimited() {
        // The user/faction selections need Limited; no endpoint needs Full.
        XCTAssertEqual(TornEndpointRegistry.requiredAccessLevel, .limited)
    }

    func testAllSelectionsAreDeduplicated() {
        let selections = TornEndpointRegistry.allSelections
        XCTAssertEqual(selections.count, Set(selections).count)
        XCTAssertTrue(selections.contains("bars"))
        XCTAssertTrue(selections.contains("organizedcrime"))
    }

    // MARK: - Documentation generation

    func testMarkdownTableHasARowPerEndpoint() {
        let lines = TornEndpointRegistry.markdownTable().split(separator: "\n")
        // header + separator + one row per endpoint
        XCTAssertEqual(lines.count, TornEndpointRegistry.all.count + 2)
    }

    /// README's "API Data Usage" table must be exactly what the registry generates.
    ///
    /// The registry has always described itself as the source of truth for that table, but
    /// nothing checked it — so the README kept advertising `forum.threads` as a live
    /// endpoint for as long as the code declared it and never called it. A row count is not
    /// enough: cadence, row limits and purposes drift silently. This compares the text.
    func testREADMETableIsExactlyWhatTheRegistryGenerates() throws {
        let readmeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Models
            .deletingLastPathComponent()   // MacTornTests
            .deletingLastPathComponent()   // MacTorn
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        let generated = TornEndpointRegistry.markdownTable()
        guard let header = generated.split(separator: "\n").first else {
            return XCTFail("the registry produced no table")
        }
        guard let start = readme.range(of: String(header)) else {
            return XCTFail("README has no API Data Usage table starting with the generated header")
        }
        let rest = readme[start.lowerBound...]
        let table = rest.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { $0.hasPrefix("|") }
            .joined(separator: "\n")

        XCTAssertEqual(table, generated, """
        README's API table is out of date. Replace it with:

        \(generated)
        """)
    }
}
