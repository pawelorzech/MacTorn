import XCTest
@testable import MacTorn

@MainActor
final class AppStateStocksMetadataTests: XCTestCase {

    private static let cacheKey = "stocksMetadataCache"

    var mockSession: MockNetworkSession!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession)
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        try await super.tearDown()
    }

    func testFetchStocksMetadata_populatesDictionaryAndPersistsToUserDefaults() async throws {
        appState.apiKey = "test_key"
        try mockSession.setSuccessResponse(json: [
            "stocks": [
                "1": ["name": "Torn City Stock Exchange", "acronym": "TCSE", "current_price": 1234.56],
                "16": ["name": "Sym-Sym Pharmaceuticals", "acronym": "SYS", "current_price": 805.32]
            ]
        ])

        await appState.fetchStocksMetadata()

        XCTAssertEqual(appState.stocksMetadata.count, 2)
        XCTAssertEqual(appState.stocksMetadata[1]?.acronym, "TCSE")
        XCTAssertEqual(appState.stocksMetadata[16]?.name, "Sym-Sym Pharmaceuticals")

        // Persisted to cache
        let cached = UserDefaults.standard.data(forKey: Self.cacheKey)
        XCTAssertNotNil(cached)
        let decoded = try JSONDecoder().decode([Int: StockMetadata].self, from: cached!)
        XCTAssertEqual(decoded[16]?.acronym, "SYS")
    }

    func testLoadStocksMetadataFromCache_hydratesAtInit() throws {
        // Pre-populate cache as if from a previous session
        let cached: [Int: StockMetadata] = [
            7: StockMetadata(id: 7, name: "Big Al's Gun Shop", acronym: "BAG", currentPrice: 42.5)
        ]
        let data = try JSONEncoder().encode(cached)
        UserDefaults.standard.set(data, forKey: Self.cacheKey)

        let freshAppState = AppState(session: MockNetworkSession())

        XCTAssertEqual(freshAppState.stocksMetadata[7]?.acronym, "BAG")
        XCTAssertEqual(freshAppState.stocksMetadata[7]?.currentPrice ?? 0, 42.5, accuracy: 0.001)
    }

    func testFetchStocksMetadata_emptyApiKey_isNoop() async {
        appState.apiKey = ""
        await appState.fetchStocksMetadata()
        XCTAssertTrue(appState.stocksMetadata.isEmpty)
    }
}
