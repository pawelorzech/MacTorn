import XCTest
@testable import MacTorn

@MainActor
final class AppStateWatchlistTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession)
        // Clear watchlist
        UserDefaults.standard.removeObject(forKey: "watchlist")
        appState.watchlistItems = []
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        UserDefaults.standard.removeObject(forKey: "watchlist")
        try await super.tearDown()
    }

    // MARK: - Add Item Tests

    func testAddToWatchlist_addsItem() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Xanax")

        XCTAssertEqual(appState.watchlistItems.count, 1)
        XCTAssertEqual(appState.watchlistItems.first?.id, 123)
        XCTAssertEqual(appState.watchlistItems.first?.name, "Xanax")
    }

    func testAddToWatchlist_preventsDuplicate() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Xanax")
        appState.addToWatchlist(itemId: 123, name: "Xanax") // Duplicate

        XCTAssertEqual(appState.watchlistItems.count, 1) // Should still be 1
    }

    func testAddToWatchlist_fetchesPriceImmediately() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Xanax")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should have made a request to fetch price
        XCTAssertTrue(mockSession.requestedURLs.contains { $0.absoluteString.contains("123") })
    }

    func testAddToWatchlist_multipleItems() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Xanax")
        appState.addToWatchlist(itemId: 456, name: "Donator Pack")
        appState.addToWatchlist(itemId: 789, name: "Vicodin")

        XCTAssertEqual(appState.watchlistItems.count, 3)
    }

    // MARK: - Remove Item Tests

    func testRemoveFromWatchlist_removesItem() {
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: Date(), error: nil),
            WatchlistItem(id: 456, name: "Donator Pack", lowestPrice: 9000000, lowestPriceQuantity: 3, secondLowestPrice: 9500000, lastUpdated: Date(), error: nil)
        ]

        appState.removeFromWatchlist(123)

        XCTAssertEqual(appState.watchlistItems.count, 1)
        XCTAssertNil(appState.watchlistItems.first(where: { $0.id == 123 }))
        XCTAssertNotNil(appState.watchlistItems.first(where: { $0.id == 456 }))
    }

    func testRemoveFromWatchlist_nonExistentItem() {
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: Date(), error: nil)
        ]

        appState.removeFromWatchlist(999) // Non-existent

        XCTAssertEqual(appState.watchlistItems.count, 1) // Should still have 1 item
    }

    // MARK: - Persistence Tests

    func testSaveWatchlist_persists() {
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: Date(), error: nil)
        ]

        appState.saveWatchlist()

        // Create new instance and load
        let newAppState = AppState(session: mockSession)
        newAppState.loadWatchlist()

        XCTAssertEqual(newAppState.watchlistItems.count, 1)
        XCTAssertEqual(newAppState.watchlistItems.first?.id, 123)
    }

    func testLoadWatchlist_emptyWhenNothingSaved() {
        UserDefaults.standard.removeObject(forKey: "watchlist")

        appState.loadWatchlist()

        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    // MARK: - Price Refresh Tests

    func testRefreshWatchlistPrices_refreshesAllItems() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 0, lowestPriceQuantity: 0, secondLowestPrice: 0, lastUpdated: nil, error: nil),
            WatchlistItem(id: 456, name: "Donator Pack", lowestPrice: 0, lowestPriceQuantity: 0, secondLowestPrice: 0, lastUpdated: nil, error: nil)
        ]

        appState.refreshWatchlistPrices()

        // Wait for price fetches
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Should have made requests for both items
        let requestedURLStrings = mockSession.requestedURLs.map { $0.absoluteString }
        XCTAssertTrue(requestedURLStrings.contains { $0.contains("123") })
        XCTAssertTrue(requestedURLStrings.contains { $0.contains("456") })
    }

    // MARK: - Price Update Tests

    func testPriceFetch_updatesPrices() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertNotNil(item)
        // Prices should be updated from fixtures (950 is lowest from bazaar)
        XCTAssertGreaterThan(item?.lowestPrice ?? 0, 0)
    }

    func testPriceFetch_noListings() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemNoListings)

        appState.addToWatchlist(itemId: 123, name: "Rare Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertEqual(item?.error, "No listings")
    }

    func testPriceFetch_networkError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setNetworkError(MockNetworkError.connectionFailed)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertEqual(item?.error, "Network Error")
    }

    func testPriceFetch_httpError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setHTTPError(statusCode: 500)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertEqual(item?.error, "HTTP 500")
    }

    // MARK: - Empty API Key Tests

    func testPriceFetch_emptyAPIKey() async throws {
        appState.apiKey = ""

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait
        try await Task.sleep(nanoseconds: 500_000_000)

        // No requests should be made
        XCTAssertTrue(mockSession.requestedURLs.isEmpty)
    }
}
