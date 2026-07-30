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
