import XCTest
@testable import MacTorn

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
    }

    /// The contract test above is only meaningful if it covers every endpoint.
    func testEveryEndpointIsCoveredByContract() {
        XCTAssertEqual(TornEndpointRegistry.all.count, 13,
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
