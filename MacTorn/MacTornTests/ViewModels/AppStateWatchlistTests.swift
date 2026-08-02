import XCTest
@testable import MacTorn

@MainActor
final class AppStateWatchlistTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var appState: AppState!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults = .createMockDefaults()
        mockSession = MockNetworkSession()
        appState = AppState(session: mockSession, defaults: testDefaults)
        // Clear watchlist
        testDefaults.removeObject(forKey: "watchlist")
        appState.watchlistItems = []
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        testDefaults.removeObject(forKey: "watchlist")
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

    func testRestoreWatchlistItem_restoresFullModelAtOriginalIndexAndPersists() {
        let removed = WatchlistItem(
            id: 456,
            name: "Donator Pack",
            lowestPrice: 9_000_000,
            lowestPriceQuantity: 3,
            secondLowestPrice: 9_500_000,
            lastUpdated: Date(timeIntervalSince1970: 1_234),
            error: "Previous error",
            priceThreshold: 8_500_000,
            lastAlertedPrice: 8_400_000
        )
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1_000, lowestPriceQuantity: 5, secondLowestPrice: 1_100, lastUpdated: nil, error: nil),
            WatchlistItem(id: 789, name: "Vicodin", lowestPrice: 800, lowestPriceQuantity: 2, secondLowestPrice: 850, lastUpdated: nil, error: nil)
        ]

        XCTAssertTrue(appState.restoreWatchlistItem(removed, at: 1))

        XCTAssertEqual(appState.watchlistItems.map(\.id), [123, 456, 789])
        let restored = appState.watchlistItems[1]
        XCTAssertEqual(restored.name, removed.name)
        XCTAssertEqual(restored.lowestPrice, removed.lowestPrice)
        XCTAssertEqual(restored.lowestPriceQuantity, removed.lowestPriceQuantity)
        XCTAssertEqual(restored.secondLowestPrice, removed.secondLowestPrice)
        XCTAssertEqual(restored.lastUpdated, removed.lastUpdated)
        XCTAssertEqual(restored.error, removed.error)
        XCTAssertEqual(restored.priceThreshold, removed.priceThreshold)
        XCTAssertEqual(restored.lastAlertedPrice, removed.lastAlertedPrice)

        let reloaded = AppState(session: mockSession, defaults: testDefaults)
        XCTAssertEqual(reloaded.watchlistItems.map(\.id), [123, 456, 789])
        XCTAssertEqual(reloaded.watchlistItems[1].priceThreshold, removed.priceThreshold)
        XCTAssertEqual(reloaded.watchlistItems[1].lastAlertedPrice, removed.lastAlertedPrice)
    }

    func testRestoreWatchlistItem_doesNotDuplicateExistingItem() {
        let item = WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1_000, lowestPriceQuantity: 5, secondLowestPrice: 1_100, lastUpdated: nil, error: nil)
        appState.watchlistItems = [item]

        XCTAssertFalse(appState.restoreWatchlistItem(item, at: 0))
        XCTAssertEqual(appState.watchlistItems.map(\.id), [123])
    }

    func testPositiveIntegerInput_acceptsOnlyPositiveInts() {
        XCTAssertEqual(PositiveIntegerInput.value(from: " 42 "), 42)
        XCTAssertNil(PositiveIntegerInput.value(from: ""))
        XCTAssertNil(PositiveIntegerInput.value(from: "0"))
        XCTAssertNil(PositiveIntegerInput.value(from: "-1"))
        XCTAssertNil(PositiveIntegerInput.value(from: "1.5"))
        XCTAssertNil(PositiveIntegerInput.value(from: "abc"))
    }

    func testPositiveIntegerInput_explainsInvalidInput() {
        XCTAssertEqual(PositiveIntegerInput.errorMessage(for: ""), "Enter a price.")
        XCTAssertEqual(PositiveIntegerInput.errorMessage(for: "0"), "Price must be greater than zero.")
        XCTAssertEqual(PositiveIntegerInput.errorMessage(for: "-5"), "Price must be greater than zero.")
        XCTAssertEqual(PositiveIntegerInput.errorMessage(for: "1.5"), "Enter a whole number.")
        XCTAssertNil(PositiveIntegerInput.errorMessage(for: "2500"))
    }

    // MARK: - Persistence Tests

    func testSaveWatchlist_persists() {
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: Date(), error: nil)
        ]

        appState.saveWatchlist()

        // Create new instance and load
        let newAppState = AppState(session: mockSession, defaults: testDefaults)
        newAppState.loadWatchlist()

        XCTAssertEqual(newAppState.watchlistItems.count, 1)
        XCTAssertEqual(newAppState.watchlistItems.first?.id, 123)
    }

    func testLoadWatchlist_emptyWhenNothingSaved() {
        testDefaults.removeObject(forKey: "watchlist")

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

    func testRefreshWatchlistPricesLimitsConcurrencyToFour() async throws {
        let probe = try ConcurrencyProbeNetworkSession(
            json: TornAPIFixtures.marketItemSuccess,
            delayNanoseconds: 120_000_000
        )
        let state = AppState(
            session: probe,
            connectivity: ControllableConnectivity(),
            defaults: .createMockDefaults()
        )
        state.apiKey = "valid_key"
        state.watchlistItems = (1...12).map {
            WatchlistItem(
                id: $0,
                name: "Item \($0)",
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: nil
            )
        }

        state.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(probe.requestCount, 12)
        XCTAssertEqual(probe.maximumConcurrentRequests, 4)
    }

    func testAccountSwitchCancelsQueuedWatchlistRequests() async throws {
        let probe = try ConcurrencyProbeNetworkSession(
            json: TornAPIFixtures.marketItemSuccess,
            delayNanoseconds: 300_000_000
        )
        let state = AppState(
            session: probe,
            connectivity: ControllableConnectivity(),
            defaults: .createMockDefaults()
        )
        state.apiKey = "account_a"
        state.watchlistItems = (1...20).map {
            WatchlistItem(
                id: $0,
                name: "Item \($0)",
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: nil
            )
        }

        state.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 80_000_000)
        state.apiKey = "account_b"
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertLessThanOrEqual(probe.requestCount, 4)
        XCTAssertTrue(state.watchlistItems.allSatisfy { $0.lastUpdated == nil })
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

    // MARK: - Price Alert Tests

    func testPriceAlert_triggeredWhenBelowThreshold() async throws {
        appState.apiKey = "valid_key"
        // marketItemSuccess fixture returns lowest price of 950 (from bazaar)
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        // Add item with threshold of 1000 — fixture price 950 is below threshold
        appState.watchlistItems = [
            WatchlistItem(
                id: 123,
                name: "Xanax",
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: nil,
                priceThreshold: 1000,
                lastAlertedPrice: nil
            )
        ]

        appState.refreshWatchlistPrices()

        // Wait for price fetch to complete
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.lowestPrice, 950)
        // lastAlertedPrice should be set because price (950) < threshold (1000)
        XCTAssertEqual(item?.lastAlertedPrice, 950)
    }

    func testPriceAlert_notTriggeredWhenAboveThreshold() async throws {
        appState.apiKey = "valid_key"
        // marketItemSuccess fixture returns lowest price of 950
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        // Add item with threshold of 100 — fixture price 950 is above threshold
        appState.watchlistItems = [
            WatchlistItem(
                id: 123,
                name: "Xanax",
                lowestPrice: 0,
                lowestPriceQuantity: 0,
                secondLowestPrice: 0,
                lastUpdated: nil,
                error: nil,
                priceThreshold: 100,
                lastAlertedPrice: nil
            )
        ]

        appState.refreshWatchlistPrices()

        // Wait for price fetch to complete
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlistItems.first
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.lowestPrice, 950)
        // lastAlertedPrice should remain nil because price (950) > threshold (100)
        XCTAssertNil(item?.lastAlertedPrice)
    }

    func testPriceThreshold_persistedWithWatchlist() throws {
        let original = WatchlistItem(
            id: 789,
            name: "Speed",
            lowestPrice: 500,
            lowestPriceQuantity: 2,
            secondLowestPrice: 550,
            lastUpdated: nil,
            error: nil,
            priceThreshold: 600,
            lastAlertedPrice: 520
        )
        appState.watchlistItems = [original]
        appState.saveWatchlist()

        let newAppState = AppState(session: mockSession, defaults: testDefaults)
        newAppState.loadWatchlist()

        let loaded = newAppState.watchlistItems.first
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.priceThreshold, 600)
        XCTAssertEqual(loaded?.lastAlertedPrice, 520)
    }

    // MARK: - Input Validation (F-07)

    func testAddToWatchlist_rejectsZeroAndNegativeIds() {
        appState.addToWatchlist(itemId: 0, name: "Bad")
        appState.addToWatchlist(itemId: -1, name: "Bad")
        XCTAssertEqual(appState.watchlistItems.count, 0)
    }

    func testAddToWatchlist_rejectsImplausiblyLargeIds() {
        appState.addToWatchlist(itemId: 999_999_999, name: "Bad")
        XCTAssertEqual(appState.watchlistItems.count, 0)
    }

    func testAddToWatchlist_trimsAndCapsName() {
        let longName = "  " + String(repeating: "x", count: 200) + "  "
        appState.addToWatchlist(itemId: 123, name: longName)
        let stored = appState.watchlistItems.first?.name ?? ""
        XCTAssertLessThanOrEqual(stored.count, 64)
        XCTAssertFalse(stored.hasPrefix(" "), "leading whitespace not trimmed")
        XCTAssertFalse(stored.hasSuffix(" "), "trailing whitespace not trimmed")
    }

    func testAddToWatchlist_rejectsWhitespaceOnlyName() {
        appState.addToWatchlist(itemId: 123, name: "   \n ")
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    // MARK: - Item ID Field (GitHub #49)
    //
    // These target a testable string-input entry point that mirrors
    // ForumWatchView's `parseThreadInput` / `addWatchedThread(input:)` pair
    // (AppState+MarketForum.swift ~194-205). Nothing named `parseItemIdInput`
    // or `addToWatchlist(input:)` exists on AppState yet — the numeric-grid
    // add path only takes an already-parsed `itemId: Int`. This file will
    // not compile until the implementer adds those two entry points.

    func testParseItemIdInput_acceptsPositiveNumericString() {
        XCTAssertEqual(appState.parseItemIdInput("206"), 206)
    }

    func testParseItemIdInput_rejectsNonNumericString() {
        XCTAssertNil(appState.parseItemIdInput("abc"))
    }

    func testParseItemIdInput_rejectsEmptyString() {
        XCTAssertNil(appState.parseItemIdInput(""))
    }

    func testParseItemIdInput_rejectsZero() {
        XCTAssertNil(appState.parseItemIdInput("0"))
    }

    func testParseItemIdInput_rejectsNegative() {
        XCTAssertNil(appState.parseItemIdInput("-5"))
    }

    func testAddToWatchlistByInput_validNumericIdIsAcceptedAndAdded() {
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(appState.watchlistItems.count, 1)
        XCTAssertEqual(appState.watchlistItems.first?.id, 206)
    }

    func testAddToWatchlistByInput_rejectsNonNumericInput() {
        XCTAssertEqual(appState.addToWatchlist(input: "abc"), .notANumber)
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsEmptyInput() {
        XCTAssertEqual(appState.addToWatchlist(input: ""), .notANumber)
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsZero() {
        XCTAssertEqual(appState.addToWatchlist(input: "0"), .notANumber)
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsNegative() {
        XCTAssertEqual(appState.addToWatchlist(input: "-1"), .notANumber)
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsDuplicateId() {
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .alreadyWatched)
        XCTAssertEqual(appState.watchlistItems.count, 1)
    }

    /// An id above Torn's item range must report *why* it was rejected. It used to
    /// come back as a bare `false`, which the panel rendered as "already on your
    /// watchlist" — a statement about an item the user had never added.
    func testAddToWatchlistByInput_rejectsOutOfRangeIdAsOutOfRangeNotDuplicate() {
        let outcome = appState.addToWatchlist(input: "200000")
        XCTAssertEqual(outcome, .outOfRange(maximum: MarketWatchService.maximumItemID))
        XCTAssertNotEqual(outcome, .alreadyWatched)
        XCTAssertTrue(appState.watchlistItems.isEmpty)
    }

    /// The boundary itself is exclusive, and one below it is a normal add.
    func testAddToWatchlistByInput_boundaryIsExclusive() {
        XCTAssertEqual(
            appState.addToWatchlist(input: String(MarketWatchService.maximumItemID)),
            .outOfRange(maximum: MarketWatchService.maximumItemID)
        )
        XCTAssertEqual(
            appState.addToWatchlist(input: String(MarketWatchService.maximumItemID - 1)),
            .added(itemId: MarketWatchService.maximumItemID - 1)
        )
    }

    // MARK: - Price-Alert Threshold Clear Undo (GitHub #54)
    //
    // Removing a watchlist item already has a full Undo primitive at the
    // AppState layer (`restoreWatchlistItem(_:at:)` in WatchlistView.swift,
    // covered above). Clearing a price-alert threshold has no equivalent —
    // `onSetThreshold(nil)` (WatchlistView.swift ~331-334) writes straight
    // through with nothing captured to undo. These tests target a
    // `restoreWatchlistThreshold(itemId:threshold:lastAlertedPrice:)`
    // function that does not exist yet, mirroring `restoreWatchlistItem`'s
    // shape so the View's six-second Undo banner can reuse the same
    // mechanism for both flows as the issue requires. This file will not
    // compile until the implementer adds it.

    func testRestoreWatchlistThreshold_restoresPreviousThresholdAndAlertPrice() {
        appState.watchlistItems = [
            WatchlistItem(
                id: 123,
                name: "Xanax",
                lowestPrice: 1000,
                lowestPriceQuantity: 5,
                secondLowestPrice: 1100,
                lastUpdated: Date(),
                error: nil,
                priceThreshold: nil,
                lastAlertedPrice: nil
            )
        ]

        XCTAssertTrue(appState.restoreWatchlistThreshold(itemId: 123, threshold: 900, lastAlertedPrice: 850))

        XCTAssertEqual(appState.watchlistItems.first?.priceThreshold, 900)
        XCTAssertEqual(appState.watchlistItems.first?.lastAlertedPrice, 850)
    }

    func testRestoreWatchlistThreshold_returnsFalseForMissingItem() {
        appState.watchlistItems = []

        XCTAssertFalse(appState.restoreWatchlistThreshold(itemId: 999, threshold: 900, lastAlertedPrice: nil))
    }

    func testRestoreWatchlistThreshold_persistsAcrossReload() {
        appState.watchlistItems = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: nil, error: nil)
        ]

        XCTAssertTrue(appState.restoreWatchlistThreshold(itemId: 123, threshold: 750, lastAlertedPrice: nil))

        let reloaded = AppState(session: mockSession, defaults: testDefaults)
        XCTAssertEqual(reloaded.watchlistItems.first?.priceThreshold, 750)
    }

    // MARK: - v2 Error Envelope Contract (market endpoint)

    /// The market endpoint is v2 (`/v2/market/{id}`). Torn's v2 error envelope is
    /// `{"code":Int,"error":String}` with `error` as a TOP-LEVEL string. When the
    /// error is swallowed it gets mis-reported to the user as "No listings"; this
    /// must surface the real message (e.g. rate-limit) instead.
    func testFetchItemPrice_surfacesV2RateLimitError() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIErrorV2(code: 5, message: "Too many requests")

        appState.addToWatchlist(itemId: 123, name: "Xanax")
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(appState.watchlistItems.first?.error, "Too many requests — backing off.",
                       "v2 market error envelope must be surfaced, not swallowed as 'No listings'")
    }

    func testFetchItemPrice_surfacesV2IncorrectKeyError() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIErrorV2(code: 2, message: "Incorrect key")

        appState.addToWatchlist(itemId: 456, name: "Item")
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(appState.watchlistItems.first?.error, "Incorrect key",
                       "v2 incorrect-key error must surface")
    }
}

private final class ConcurrencyProbeNetworkSession: NetworkSession, @unchecked Sendable {
    private let responseData: Data
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var activeRequests = 0
    private var recordedRequestCount = 0
    private var recordedMaximum = 0

    init(json: [String: Any], delayNanoseconds: UInt64) throws {
        self.responseData = try JSONSerialization.data(withJSONObject: json)
        self.delayNanoseconds = delayNanoseconds
    }

    var requestCount: Int {
        lock.withLock { recordedRequestCount }
    }

    var maximumConcurrentRequests: Int {
        lock.withLock { recordedMaximum }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            recordedRequestCount += 1
            activeRequests += 1
            recordedMaximum = max(recordedMaximum, activeRequests)
        }
        defer {
            lock.withLock {
                activeRequests -= 1
            }
        }

        try await Task.sleep(nanoseconds: delayNanoseconds)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.torn.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
