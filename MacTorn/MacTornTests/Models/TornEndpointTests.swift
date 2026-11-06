import XCTest
@testable import MacTorn

/// The typed registry is the single source of truth for every URL and its metadata must
/// be internally consistent.
final class TornEndpointTests: XCTestCase {

    private let key = "exampleKey123456"
    private let sampleId = 4242

    // MARK: - URL building

    /// A key with reserved characters must survive percent-encoding and round-trip exactly.
    func testKeyWithReservedCharactersRoundTripsThroughTheQuery() throws {
        let reserved = "ab&cd=ef gh"
        let url = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.fast")?.url(key: reserved))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "key" }?.value, reserved)
    }

    /// The fast poll runs every ~30 s, so it must never ask for row-based categories: those
    /// count against Torn's 50,000-rows/day cap (error 14).
    func testFastUserPollRequestsNoRowBasedSelections() throws {
        let url = tornURL("user.fast", key: key)
        let selections = Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "selections" }?.value?.split(separator: ",").map(String.init) ?? [])
        XCTAssertTrue(selections.contains("bars"))
        XCTAssertTrue(selections.isDisjoint(with: ["events", "messages", "attacks", "chain"]), "\(selections)")
    }

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

    func testForumThreadUsesThePerThreadPath() {
        XCTAssertEqual(tornURL("forum.thread", key: key, parameter: 567).path, "/v2/forum/567/thread")
    }

    func testMarketUsesTheCanonicalItemMarketPath() throws {
        let endpoint = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "market.item"))
        let url = try XCTUnwrap(endpoint.url(key: key, parameter: sampleId))
        XCTAssertEqual(url.path, "/v2/market/4242/itemmarket")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "selections" })
    }

    // MARK: - Documentation generation

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
