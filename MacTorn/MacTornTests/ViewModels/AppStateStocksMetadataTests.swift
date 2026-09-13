import XCTest
@testable import MacTorn

@MainActor
final class AppStateStocksMetadataTests: XCTestCase {

    private static let cacheKey = "stocksMetadataCache"

    var mockSession: MockNetworkSession!
    var appState: AppState!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults = .createMockDefaults()
        testDefaults.removeObject(forKey: Self.cacheKey)
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession, defaults: testDefaults)
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        testDefaults.removeObject(forKey: Self.cacheKey)
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
        let cached = testDefaults.data(forKey: Self.cacheKey)
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
        testDefaults.set(data, forKey: Self.cacheKey)

        let freshAppState = AppState(session: MockNetworkSession(), defaults: testDefaults)

        XCTAssertEqual(freshAppState.stocksMetadata[7]?.acronym, "BAG")
        XCTAssertEqual(freshAppState.stocksMetadata[7]?.currentPrice ?? 0, 42.5, accuracy: 0.001)
    }

    func testFetchStocksMetadata_emptyApiKey_isNoop() async {
        appState.apiKey = ""
        await appState.fetchStocksMetadata()
        XCTAssertTrue(appState.stocksMetadata.isEmpty)
    }

    func testFetchStocksMetadataPropagatesPermanentKeyError() async throws {
        appState.apiKey = "revoked-key"
        try mockSession.setTornAPIError(code: 2, message: "Incorrect key")

        await appState.fetchStocksMetadata()

        XCTAssertTrue(appState.keyHalted)
        XCTAssertEqual(appState.endpointHealth.latest(for: "torn.stocks")?.errorClass,
                       "permanentKey")
    }

    func testOldMetadataErrorCannotHaltNewAccount() async throws {
        for catalog in [false, true] {
            let requested = expectation(description: "Metadata request started")
            let session = HeldMetadataSession { _ in requested.fulfill() }
            let app = AppState(session: session, connectivity: ControllableConnectivity(connected: true),
                               defaults: .createMockDefaults())
            app.apiKey = "account-a"
            let old = Task {
                if catalog { await app.fetchItemCatalog() }
                else { await app.fetchStocksMetadata() }
            }
            await fulfillment(of: [requested], timeout: 2)
            app.apiKey = "account-b"
            await session.finish(Data(#"{"error":{"code":2,"error":"Incorrect key"}}"#.utf8))
            await old.value
            XCTAssertFalse(app.keyHalted, "An old metadata error must not halt account B")
            XCTAssertNil(app.errorMsg)
            XCTAssertEqual(app.stocksFailureCount, 0)
            XCTAssertEqual(app.itemCatalogFailureCount, 0)
        }
    }

    func testConcurrentMetadataCallsSpendOnlyOneRequest() async throws {
        for catalog in [false, true] {
            let requested = expectation(description: "First request")
            let duplicateFinished = expectation(description: "Duplicate skipped")
            let session = HeldMetadataSession { index in if index == 0 { requested.fulfill() } }
            let app = AppState(session: session, connectivity: ControllableConnectivity(connected: true),
                               defaults: .createMockDefaults())
            app.apiKey = "account-a"
            let first = Task {
                if catalog { await app.fetchItemCatalog() } else { await app.fetchStocksMetadata() }
            }
            await fulfillment(of: [requested], timeout: 2)
            let duplicate = Task {
                if catalog { await app.fetchItemCatalog() } else { await app.fetchStocksMetadata() }
                duplicateFinished.fulfill()
            }
            await fulfillment(of: [duplicateFinished], timeout: 2)
            let count = await session.requestCount
            await session.finish(Data("{}".utf8))
            await session.finish(Data("{}".utf8), index: 1)
            await first.value
            await duplicate.value
            XCTAssertEqual(count, 1)
        }
    }

    func testOldCompletionCannotClearNewMetadataRequest() async throws {
        for catalog in [false, true] {
            let firstRequest = expectation(description: "Old account started")
            let secondRequest = expectation(description: "New account started")
            let session = HeldMetadataSession { index in
                if index == 0 { firstRequest.fulfill() }
                if index == 1 { secondRequest.fulfill() }
            }
            let app = AppState(session: session, connectivity: ControllableConnectivity(connected: true),
                               defaults: .createMockDefaults())
            app.apiKey = "account-a"
            let old = Task {
                if catalog { await app.fetchItemCatalog() } else { await app.fetchStocksMetadata() }
            }
            await fulfillment(of: [firstRequest], timeout: 2)
            app.apiKey = "account-b"
            let new = Task {
                if catalog { await app.fetchItemCatalog() } else { await app.fetchStocksMetadata() }
            }
            await fulfillment(of: [secondRequest], timeout: 2)
            let endpoint = catalog ? "torn.items" : "torn.stocks"
            let newID = app.referenceFetchIDs[endpoint]
            XCTAssertNotNil(newID)
            await session.finish(Data("{}".utf8))
            await old.value
            XCTAssertEqual(app.referenceFetchIDs[endpoint], newID)
            await session.finish(Data("{}".utf8), index: 1)
            await new.value
            XCTAssertNil(app.referenceFetchIDs[endpoint])
        }
    }

    func testCancelledMetadataDoesNotPublishOrBackOff() async throws {
        for catalog in [false, true] {
            let requested = expectation(description: "Metadata request started")
            let session = HeldMetadataSession { _ in requested.fulfill() }
            let app = AppState(session: session, connectivity: ControllableConnectivity(connected: true),
                               defaults: .createMockDefaults())
            app.apiKey = "account-a"
            let task = Task {
                if catalog { await app.fetchItemCatalog() }
                else { await app.fetchStocksMetadata() }
            }
            await fulfillment(of: [requested], timeout: 2)
            task.cancel()
            await session.finish(Data(#"{"error":{"code":2,"error":"Incorrect key"}}"#.utf8))
            await task.value
            XCTAssertFalse(app.keyHalted)
            XCTAssertEqual(app.stocksFailureCount, 0)
            XCTAssertEqual(app.itemCatalogFailureCount, 0)
        }
    }
}

/// Deliberately ignores cancellation to exercise publication guards after transport.
private actor HeldMetadataSession: NetworkSession {
    let onRequest: @Sendable (Int) -> Void
    private(set) var requestCount = 0
    var pending: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    init(onRequest: @escaping @Sendable (Int) -> Void) { self.onRequest = onRequest }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let index = requestCount
            requestCount += 1
            pending[index] = continuation
            onRequest(index)
        }
    }
    func finish(_ data: Data, index: Int = 0) {
        let response = HTTPURLResponse(url: URL(string: "https://api.torn.com")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
        pending.removeValue(forKey: index)?.resume(returning: (data, response))
    }
}
