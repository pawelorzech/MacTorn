import XCTest
@testable import MacTorn

@MainActor
final class MarketWatchServiceTests: XCTestCase {
    func testOwnsValidatedStateAndPersistence() {
        let defaults = UserDefaults.createMockDefaults()
        let service = MarketWatchService(
            defaults: defaults,
            session: MockNetworkSession()
        )

        XCTAssertTrue(service.add(itemID: 123, name: "  Xanax  "))
        XCTAssertFalse(service.add(itemID: 123, name: "Duplicate"))
        XCTAssertFalse(service.add(itemID: 0, name: "Invalid"))
        XCTAssertEqual(service.items.map(\.name), ["Xanax"])

        let reloaded = MarketWatchService(
            defaults: defaults,
            session: MockNetworkSession()
        )
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.id), [123])
    }

    func testRestorePreservesFullItemAtOriginalIndex() {
        let service = MarketWatchService(
            defaults: .createMockDefaults(),
            session: MockNetworkSession()
        )
        service.items = [
            item(id: 1, name: "One"),
            item(id: 3, name: "Three")
        ]
        let restored = WatchlistItem(
            id: 2,
            name: "Two",
            lowestPrice: 90,
            lowestPriceQuantity: 4,
            secondLowestPrice: 100,
            lastUpdated: Date(timeIntervalSince1970: 123),
            error: "old",
            priceThreshold: 80,
            lastAlertedPrice: 75
        )

        XCTAssertTrue(service.restore(restored, at: 1))
        XCTAssertEqual(service.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(service.items[1].priceThreshold, 80)
        XCTAssertFalse(service.restore(restored, at: 0))
    }

    func testApplyingPriceUpdatesStateAndReturnsThresholdAlertOnce() {
        let service = MarketWatchService(
            defaults: .createMockDefaults(),
            session: MockNetworkSession()
        )
        service.items = [
            WatchlistItem(
                id: 7,
                name: "Target",
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: "loading",
                priceThreshold: 1_000
            )
        ]

        let first = service.apply(
            MarketPriceSnapshot(
                lowestPrice: 900,
                lowestPriceQuantity: 2,
                secondLowestPrice: 950
            ),
            to: 7
        )
        let second = service.apply(
            MarketPriceSnapshot(
                lowestPrice: 900,
                lowestPriceQuantity: 2,
                secondLowestPrice: 950
            ),
            to: 7
        )

        XCTAssertEqual(first, MarketPriceAlert(name: "Target", price: 900))
        XCTAssertNil(second)
        XCTAssertEqual(service.items[0].lastAlertedPrice, 900)
        XCTAssertNil(service.items[0].error)
    }

    func testFetchPriceDecodesAndSortsAllListingSources() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        let service = MarketWatchService(
            defaults: .createMockDefaults(),
            session: mock
        )

        let result = try await service.fetchPrice(
            from: URL(string: "https://api.torn.com/v2/market/123/itemmarket")!
        )

        guard case .success(let snapshot, _) = result else {
            return XCTFail("Expected market price")
        }
        XCTAssertEqual(snapshot.lowestPrice, 950)
        XCTAssertEqual(snapshot.lowestPriceQuantity, 2)
        XCTAssertEqual(snapshot.secondLowestPrice, 1_000)
    }

    func testFetchPriceDistinguishesMalformedResponseFromEmptyListings() async throws {
        let mock = MockNetworkSession()
        let service = MarketWatchService(defaults: .createMockDefaults(), session: mock)
        let url = URL(string: "https://api.torn.com/v2/market/123/itemmarket")!
        let malformedResponses: [[String: Any]] = [
            [:],
            ["itemmarket": [:]],
            ["itemmarket": ["listings": "invalid"]],
            ["itemmarket": ["listings": [["amount": 1]]]],
            ["itemmarket": [["quantity": 1]]]
        ]
        for json in malformedResponses {
            try mock.setSuccessResponse(json: json)
            guard case .malformed = try await service.fetchPrice(from: url) else {
                XCTFail("Invalid market structure must be a parse error: \(json)")
                continue
            }
        }
        let emptyResponses: [[String: Any]] = [
            ["itemmarket": ["listings": []]],
            ["itemmarket": []]
        ]
        for json in emptyResponses {
            try mock.setSuccessResponse(json: json)
            guard case .noListings = try await service.fetchPrice(from: url) else {
                XCTFail("An empty listings array must remain a valid empty market")
                continue
            }
        }
    }

    func testFetchPriceSurfacesV2APIError() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIErrorV2(code: 5, message: "Too many requests")
        let service = MarketWatchService(
            defaults: .createMockDefaults(),
            session: mock
        )

        let result = try await service.fetchPrice(
            from: URL(string: "https://api.torn.com/v2/market/123/itemmarket")!
        )

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected API error")
        }
        XCTAssertEqual(error.userMessage, "Too many requests — backing off.")
    }

    private func item(id: Int, name: String) -> WatchlistItem {
        WatchlistItem(
            id: id,
            name: name,
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: nil
        )
    }
}

// MARK: - Corrupted-store protection (audit 2026-08-01, D-01)
//
// An unreadable blob used to be indistinguishable from "no data yet": `load()` bailed
// silently leaving an empty list, and the first background price refresh called `save()`
// and overwrote the recoverable blob with `[]`. The user's watchlist was then gone
// permanently — even downgrading the app could not bring it back.

@MainActor
final class MarketWatchCorruptStoreTests: XCTestCase {

    private func makeService(_ defaults: UserDefaults) -> MarketWatchService {
        MarketWatchService(defaults: defaults, session: MockNetworkSession())
    }

    func testUnreadableBlobIsNotOverwrittenByABackgroundSave() throws {
        let defaults = UserDefaults.createMockDefaults()
        let corrupt = Data("{not json at all".utf8)
        defaults.set(corrupt, forKey: "watchlist")

        let service = makeService(defaults)
        service.load()
        XCTAssertTrue(service.items.isEmpty, "nothing could be decoded")

        service.save()   // this is what the price-refresh loop does on its own schedule

        XCTAssertEqual(defaults.data(forKey: "watchlist"), corrupt,
                       "the recoverable blob must survive — overwriting it destroys the list")
    }

    func testUnreadableBlobIsPreservedUnderARecoveryKey() {
        let defaults = UserDefaults.createMockDefaults()
        let corrupt = Data("{not json at all".utf8)
        defaults.set(corrupt, forKey: "watchlist")

        makeService(defaults).load()

        XCTAssertEqual(defaults.data(forKey: "watchlist.unreadable"), corrupt,
                       "a copy is kept so the data can be recovered by hand")
    }

    func testFirstRunWithNoStoredBlobStillPersists() {
        let defaults = UserDefaults.createMockDefaults()
        let service = makeService(defaults)
        service.load()   // no key at all — a legitimate first run, not a failure

        XCTAssertTrue(service.add(itemID: 206, name: "Xanax"))
        XCTAssertNotNil(defaults.data(forKey: "watchlist"),
                        "a clean first run must still save normally")
    }

    func testDeliberateUserEditTakesOwnershipAndResumesPersistence() throws {
        let defaults = UserDefaults.createMockDefaults()
        defaults.set(Data("{not json at all".utf8), forKey: "watchlist")

        let service = makeService(defaults)
        service.load()
        XCTAssertTrue(service.add(itemID: 206, name: "Xanax"))

        let reloaded = makeService(defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.id), [206],
                       "once the user edits the list, writes must resume")
    }
}
