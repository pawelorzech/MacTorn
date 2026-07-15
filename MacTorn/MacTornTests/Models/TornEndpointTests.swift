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
        assertMatch("faction.basic", TornAPI.factionURL(for: key))
        assertMatch("faction.rankedwars", TornAPI.factionRankedWarsURL(for: key))
        assertMatch("faction.news", TornAPI.factionNewsURL(for: key))
        assertMatch("market.item", TornAPI.marketURL(itemId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("torn.stocks", TornAPI.tornStocksURL(for: key))
        assertMatch("forum.thread", TornAPI.forumThreadURL(threadId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("forum.threads", TornAPI.forumCategoryThreadsURL(categoryId: sampleId, apiKey: key), parameter: sampleId)
        assertMatch("key.info", TornAPI.keyInfoURL(for: key))
    }

    /// The contract test above is only meaningful if it covers every endpoint.
    func testEveryEndpointIsCoveredByContract() {
        XCTAssertEqual(TornEndpointRegistry.all.count, 11,
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
}
