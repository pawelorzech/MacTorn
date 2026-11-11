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
        appState.watchlist.items = []
    }

    override func tearDown() async throws {
        appState.stopPolling()
        appState = nil
        mockSession = nil
        testDefaults.removeObject(forKey: "watchlist")
        try await super.tearDown()
    }

    // MARK: - Add Item Tests

    func testAddToWatchlist_fetchesPriceImmediately() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Xanax")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should have made a request to fetch price
        XCTAssertTrue(mockSession.requestedURLs.contains { $0.absoluteString.contains("123") })
    }

    // MARK: - Remove Item Tests

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

    // MARK: - Price Refresh Tests

    func testRefreshWatchlistPrices_refreshesAllItems() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.watchlist.items = [
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
        state.watchlist.items = (1...12).map {
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
        state.watchlist.items = (1...20).map {
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
        XCTAssertTrue(state.watchlist.items.allSatisfy { $0.lastUpdated == nil })
    }

    /// A refresh superseded mid-run must still deliver the alerts it already latched.
    ///
    /// `MarketWatchService.apply` writes `lastAlertedPrice` the moment a price crosses the
    /// threshold, so the alert epoch is spent at that point. The pending alerts used to
    /// live in one shared array that the next refresh cleared on entry, and the cancelled
    /// run skipped its own flush — the latch was set, the banner never shown, and the
    /// superseding run saw the same cache timestamp and stayed silent. (Audit F-04.)
    func testSupersededRefreshStillDeliversAlertsItAlreadyLatched() async throws {
        let probe = try ConcurrencyProbeNetworkSession(
            json: TornAPIFixtures.marketItemSuccess,
            delayNanoseconds: 300_000_000
        )
        let notifier = RecordingNotifier()
        let state = AppState(
            session: probe,
            connectivity: ControllableConnectivity(),
            defaults: .createMockDefaults(),
            notifier: notifier
        )
        state.apiKey = "valid_key"
        // Five items at a 1,000 threshold; the fixture's lowest price is 950. With the
        // queue limit at four, the first wave lands at ~300 ms and item 5 at ~600 ms.
        state.watchlist.items = (1...5).map {
            WatchlistItem(id: $0, name: "Item \($0)", lowestPrice: 0,
                          lowestPriceQuantity: 0, secondLowestPrice: 0,
                          lastUpdated: nil, error: nil, priceThreshold: 1_000)
        }

        state.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(state.watchlist.items.filter { $0.lastAlertedPrice == 950 }.count, 4,
                       "precondition: the first wave latched its alerts")
        state.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertEqual(notifier.sent.map(\.title).map(Self.alertsAnnounced).reduce(0, +), 5,
                       "every latched alert reaches the user, each exactly once")
    }

    /// How many price alerts one banner announces: "Price Alert: X" is one, "N price alerts" is N.
    private static func alertsAnnounced(_ title: String) -> Int {
        title.hasPrefix("Price Alert:") ? 1 : Int(title.split(separator: " ").first ?? "") ?? 0
    }

    // MARK: - Price Update Tests

    func testPriceFetch_updatesPrices() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlist.items.first
        XCTAssertNotNil(item)
        // Prices should be updated from fixtures (950 is the lowest item-market listing)
        XCTAssertGreaterThan(item?.lowestPrice ?? 0, 0)
        XCTAssertEqual(item?.dataTimestamp, Date(timeIntervalSince1970: 1_783_107_206))
        XCTAssertEqual(item?.cacheDelay, 3_600)
        XCTAssertNotNil(item?.lastFetchedAt)
    }

    func testRepeatedNetworkSnapshotDoesNotReplacePriceOrRetriggerAlert() async throws {
        // The second read has to be far enough after the first to be asked for at all.
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1_783_110_000))
        appState = AppState(session: mockSession, defaults: testDefaults, time: clock)
        appState.apiKey = "valid_key"
        appState.watchlist.items = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 0,
                          lowestPriceQuantity: 0, secondLowestPrice: 0,
                          lastUpdated: nil, error: nil, priceThreshold: 1_000)
        ]
        var response = TornAPIFixtures.marketItemSuccess
        var market = try XCTUnwrap(response["itemmarket"] as? [String: Any])
        market["cache_delay"] = 0
        response["itemmarket"] = market
        try mockSession.setSuccessResponse(json: response)

        appState.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(appState.watchlist.items.first?.lowestPrice, 950)
        XCTAssertEqual(appState.watchlist.items.first?.lastAlertedPrice, 950)

        market["listings"] = [["price": 800, "amount": 1], ["price": 850, "amount": 1]]
        response["itemmarket"] = market
        try mockSession.setSuccessResponse(json: response)
        clock.advance(AppState.priceAlertPollInterval)
        appState.refreshWatchlistPrices()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(appState.watchlist.items.first?.lowestPrice, 950,
                       "same cache timestamp must not be published as a price change")
        XCTAssertEqual(appState.watchlist.items.first?.lastAlertedPrice, 950,
                       "same cache timestamp must not create another alert epoch")
        XCTAssertEqual(appState.watchlist.items.first?.dataTimestamp,
                       Date(timeIntervalSince1970: 1_783_107_206))
        XCTAssertEqual(mockSession.requestedURLs.filter { $0.absoluteString.contains("/123/") }.count, 2)
    }

    func testPriceFetch_noListings() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemNoListings)

        appState.addToWatchlist(itemId: 123, name: "Rare Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlist.items.first
        XCTAssertEqual(item?.error, "No listings")
    }

    func testPriceFetch_networkError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setNetworkError(MockNetworkError.connectionFailed)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlist.items.first
        XCTAssertEqual(item?.error, TornRequestFailure.transport(nil).userMessage)
    }

    func testPriceFetch_httpError() async throws {
        appState.apiKey = "valid_key"
        mockSession.setHTTPError(statusCode: 500)

        appState.addToWatchlist(itemId: 123, name: "Test Item")

        // Wait for price fetch
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let item = appState.watchlist.items.first
        XCTAssertEqual(item?.error, TornRequestFailure.http(500).userMessage)
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

    // MARK: - Input Validation (F-07)

    func testAddToWatchlist_rejectsZeroAndNegativeIds() {
        appState.addToWatchlist(itemId: 0, name: "Bad")
        appState.addToWatchlist(itemId: -1, name: "Bad")
        XCTAssertEqual(appState.watchlist.items.count, 0)
    }

    func testAddToWatchlist_rejectsImplausiblyLargeIds() {
        appState.addToWatchlist(itemId: 999_999_999, name: "Bad")
        XCTAssertEqual(appState.watchlist.items.count, 0)
    }

    func testAddToWatchlist_trimsAndCapsName() {
        let longName = "  " + String(repeating: "x", count: 200) + "  "
        appState.addToWatchlist(itemId: 123, name: longName)
        let stored = appState.watchlist.items.first?.name ?? ""
        XCTAssertLessThanOrEqual(stored.count, 64)
        XCTAssertFalse(stored.hasPrefix(" "), "leading whitespace not trimmed")
        XCTAssertFalse(stored.hasSuffix(" "), "trailing whitespace not trimmed")
    }

    func testAddToWatchlist_rejectsWhitespaceOnlyName() {
        appState.addToWatchlist(itemId: 123, name: "   \n ")
        XCTAssertTrue(appState.watchlist.items.isEmpty)
    }

    // MARK: - Item ID Field (GitHub #49)

    func testAddToWatchlistByInput_validNumericIdIsAcceptedAndAdded() {
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(appState.watchlist.items.count, 1)
        XCTAssertEqual(appState.watchlist.items.first?.id, 206)
    }

    func testAddToWatchlistByInput_rejectsNonNumericInput() {
        XCTAssertEqual(appState.addToWatchlist(input: "abc"), .notANumber)
        XCTAssertTrue(appState.watchlist.items.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsEmptyInput() {
        XCTAssertEqual(appState.addToWatchlist(input: ""), .notANumber)
        XCTAssertTrue(appState.watchlist.items.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsZero() {
        XCTAssertEqual(appState.addToWatchlist(input: "0"), .notANumber)
        XCTAssertTrue(appState.watchlist.items.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsNegative() {
        XCTAssertEqual(appState.addToWatchlist(input: "-1"), .notANumber)
        XCTAssertTrue(appState.watchlist.items.isEmpty)
    }

    func testAddToWatchlistByInput_rejectsDuplicateId() {
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(appState.addToWatchlist(input: "206"), .alreadyWatched)
        XCTAssertEqual(appState.watchlist.items.count, 1)
    }

    /// An id above Torn's item range must report *why* it was rejected. It used to
    /// come back as a bare `false`, which the panel rendered as "already on your
    /// watchlist" — a statement about an item the user had never added.
    func testAddToWatchlistByInput_rejectsOutOfRangeIdAsOutOfRangeNotDuplicate() {
        let outcome = appState.addToWatchlist(input: "200000")
        XCTAssertEqual(outcome, .outOfRange(maximum: MarketWatchService.maximumItemID))
        XCTAssertNotEqual(outcome, .alreadyWatched)
        XCTAssertTrue(appState.watchlist.items.isEmpty)
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

    func testRestoreWatchlistThreshold_restoresPreviousThresholdAndAlertPrice() {
        appState.watchlist.items = [
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

        XCTAssertEqual(appState.watchlist.items.first?.priceThreshold, 900)
        XCTAssertEqual(appState.watchlist.items.first?.lastAlertedPrice, 850)
    }

    func testRestoreWatchlistThreshold_returnsFalseForMissingItem() {
        appState.watchlist.items = []

        XCTAssertFalse(appState.restoreWatchlistThreshold(itemId: 999, threshold: 900, lastAlertedPrice: nil))
    }

    func testRestoreWatchlistThreshold_persistsAcrossReload() {
        appState.watchlist.items = [
            WatchlistItem(id: 123, name: "Xanax", lowestPrice: 1000, lowestPriceQuantity: 5, secondLowestPrice: 1100, lastUpdated: nil, error: nil)
        ]

        XCTAssertTrue(appState.restoreWatchlistThreshold(itemId: 123, threshold: 750, lastAlertedPrice: nil))

        let reloaded = AppState(session: mockSession, defaults: testDefaults)
        XCTAssertEqual(reloaded.watchlist.items.first?.priceThreshold, 750)
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

        XCTAssertEqual(appState.watchlist.items.first?.error, "Too many requests — backing off.",
                       "v2 market error envelope must be surfaced, not swallowed as 'No listings'")
    }

    func testFetchItemPrice_surfacesV2IncorrectKeyError() async throws {
        appState.apiKey = "valid_key"
        try mockSession.setTornAPIErrorV2(code: 2, message: "Incorrect key")

        appState.addToWatchlist(itemId: 456, name: "Item")
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(appState.watchlist.items.first?.error, "Incorrect key",
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

// MARK: - Background price-alert timer (audit F-05)

/// Price alerts used to be checked only while the Watchlist tab was on screen — the only
/// caller of `refreshWatchlistPrices` was the view. These pin the background timer that
/// refreshes threshold items with no view involved.
@MainActor
final class WatchlistPriceAlertTimerTests: XCTestCase {
    private var mockSession: MockNetworkSession!
    private var state: AppState!
    private var notifier: RecordingNotifier!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        notifier = RecordingNotifier()
        state = AppState(session: mockSession,
                         connectivity: ControllableConnectivity(),
                         defaults: .createMockDefaults(),
                         notifier: notifier)
        state.apiKey = "price-alert-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        state.stopPolling()
        state = nil
        mockSession = nil
        try await super.tearDown()
    }

    func testRemovingTheLastThresholdItemFromTheStoreStopsTheTimer() {
        state.startPolling()
        state.watchlist.items = [item(7, threshold: 1_000)]
        XCTAssertTrue(state.priceAlertTimer.isRunning)

        state.watchlist.remove(itemID: 7)

        XCTAssertFalse(state.priceAlertTimer.isRunning, "no threshold left, so nothing to poll for")
    }

    private func item(_ id: Int, threshold: Int?) -> WatchlistItem {
        WatchlistItem(id: id, name: "Item \(id)", lowestPrice: 0, lowestPriceQuantity: 0,
                      secondLowestPrice: 0, lastUpdated: nil, error: nil,
                      priceThreshold: threshold)
    }

    private var marketRequests: [URL] {
        mockSession.requestedURLs.filter { $0.absoluteString.contains("/market/") }
    }

    func testBackgroundRefreshDeliversAlertWithoutAnyView() async throws {
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        state.watchlist.items = [item(123, threshold: 1_000)]

        state.refreshPriceAlerts()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(state.watchlist.items.first?.lastAlertedPrice, 950)
        XCTAssertEqual(notifier.sent.map(\.title), ["Price Alert: Item 123"])
    }

    func testBackgroundRefreshOnlyRequestsItemsWithAThreshold() async throws {
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        state.watchlist.items = [item(123, threshold: 1_000), item(456, threshold: nil)]

        state.refreshPriceAlerts()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(marketRequests.count, 1)
        XCTAssertTrue(marketRequests.first?.absoluteString.contains("/123") == true)
    }

    func testBackgroundRefreshRespectsTheCacheDelay() async throws {
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        var fresh = item(123, threshold: 1_000)
        fresh.dataTimestamp = Date()
        fresh.cacheDelay = 600
        state.watchlist.items = [fresh]

        state.refreshPriceAlerts()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(marketRequests.isEmpty, "a price Torn has not re-cached yet is not re-requested")
    }

    func testNoThresholdsMeansNoRequestAndNoTimer() async throws {
        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        state.watchlist.items = [item(123, threshold: nil)]

        state.refreshPriceAlerts()
        state.startPolling()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(marketRequests.isEmpty)
        XCTAssertFalse(state.priceAlertTimer.isRunning)
    }

    func testTimerFollowsPollingAndThresholds() {
        state.watchlist.items = [item(123, threshold: nil)]
        state.startPolling()
        XCTAssertFalse(state.priceAlertTimer.isRunning)

        state.watchlist.items[0].priceThreshold = 1_000
        XCTAssertTrue(state.priceAlertTimer.isRunning, "setting a threshold starts it")

        state.watchlist.items[0].priceThreshold = nil
        XCTAssertFalse(state.priceAlertTimer.isRunning, "clearing the last threshold stops it")
    }

    func testTimerIsGoneAfterKeyClear() {
        state.watchlist.items = [item(123, threshold: 1_000)]
        state.startPolling()
        XCTAssertTrue(state.priceAlertTimer.isRunning)

        state.apiKey = ""

        XCTAssertFalse(state.priceAlertTimer.isRunning)
    }

    func testTimerIsGoneAfterPermanentKeyError() async throws {
        state.watchlist.items = [item(123, threshold: 1_000)]
        state.startPolling()
        XCTAssertTrue(state.priceAlertTimer.isRunning)

        state.handlePermanentKeyError(.permanentKey(code: 2, message: "Incorrect key"))
        XCTAssertFalse(state.priceAlertTimer.isRunning)

        try mockSession.setSuccessResponse(json: TornAPIFixtures.marketItemSuccess)
        state.refreshPriceAlerts()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(marketRequests.isEmpty, "a halted key spends nothing")
    }

    func testTimerIsGoneAfterStopPolling() {
        state.watchlist.items = [item(123, threshold: 1_000)]
        state.startPolling()
        XCTAssertTrue(state.priceAlertTimer.isRunning)

        state.stopPolling()

        XCTAssertFalse(state.priceAlertTimer.isRunning)
    }
}

// MARK: - Torn's hourly item-market cache (2026-11-11)

/// On 2026-11-11 Torn raised the global cache on `market → itemmarket` from 30 seconds to
/// an hour. Measured the same day: the response reports `cache_delay: 3600`, and a snapshot
/// is served from `cache_timestamp + 3600` until `+ 7200` — it is already older than its own
/// delay when it first appears. These drive the alert timer across simulated hours and
/// count the requests the mock session saw.
@MainActor
final class WatchlistHourlyCacheTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// The snapshot Torn is serving when the test begins: 4,000 s old, as live ones are.
    private static let firstCache = start.addingTimeInterval(-4_000)

    private var mockSession: MockNetworkSession!
    private var clock: MutableTimeSource!
    private var notifier: RecordingNotifier!
    private var state: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockNetworkSession()
        clock = MutableTimeSource(Self.start)
        notifier = RecordingNotifier()
        state = AppState(session: mockSession,
                         connectivity: ControllableConnectivity(),
                         defaults: .createMockDefaults(),
                         time: clock,
                         notifier: notifier)
        state.apiKey = "hourly-cache-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        state.stopPolling()
        state = nil
        mockSession = nil
        try await super.tearDown()
    }

    private func item(_ id: Int, threshold: Int?) -> WatchlistItem {
        WatchlistItem(id: id, name: "Item \(id)", lowestPrice: 0, lowestPriceQuantity: 0,
                      secondLowestPrice: 0, lastUpdated: nil, error: nil,
                      priceThreshold: threshold)
    }

    /// What Torn answers from now on: the snapshot it cached at `cachedAt`.
    private func serve(cachedAt: Date, lowest: Int) throws {
        try mockSession.setSuccessResponse(json: ["itemmarket": [
            "cache_timestamp": Int(cachedAt.timeIntervalSince1970),
            "cache_delay": 3_600,
            "listings": [["price": lowest, "amount": 2], ["price": lowest + 50, "amount": 5]]
        ]])
    }

    private var marketRequests: Int {
        mockSession.requestedURLs.filter { $0.absoluteString.contains("/market/") }.count
    }

    /// Runs `refresh` `seconds` later and asserts how many market requests have been made
    /// in total since the test began.
    private func after(_ seconds: TimeInterval, expectRequests expected: Int, _ message: String,
                       refresh: () -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        clock.advance(seconds)
        refresh()
        await quiesce()
        XCTAssertEqual(marketRequests, expected, message, file: file, line: line)
    }

    /// Waits for the refresh just started to finish: its request, if it made one, is in
    /// flight by the first suspension, and done once nothing is.
    private func quiesce() async {
        await settle(milliseconds: 50)
        _ = await eventually { !self.state.requester.isInFlight("market.item") }
        await settle(milliseconds: 50)
    }

    private func tick(after seconds: TimeInterval, expectRequests expected: Int, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) async {
        await after(seconds, expectRequests: expected, message,
                    refresh: { state.refreshPriceAlerts() }, file: file, line: line)
    }

    /// Torn as measured: the snapshot cached at T is served from T + 3,600 s until
    /// T + 7,200 s, then replaced by the one cached at T + 3,600 s.
    private func serveAsTornDoes(prices: [Int]) throws {
        let windowsElapsed = Int(clock.now.timeIntervalSince(Self.firstCache) / 3_600)
        let index = max(0, windowsElapsed - 1)
        try serve(cachedAt: Self.firstCache.addingTimeInterval(Double(index) * 3_600),
                  lowest: prices[min(index, prices.count - 1)])
    }

    /// Three and a half hours of five-minute alert ticks against Torn's real rollover:
    /// snapshots change 3,200 s, 6,800 s and 10,400 s into the test.
    func testAlertTicksCostTwoRequestsPerHourOnceTornsScheduleIsKnown() async throws {
        state.watchlist.items = [item(123, threshold: 1_000)]
        let prices = [1_500, 950, 900, 900]
        var requestedAt: [Int] = []
        var priceChangedAt: [Int] = []

        for second in stride(from: 0, through: 12_600, by: 300) {
            if second > 0 { clock.advance(300) }
            try serveAsTornDoes(prices: prices)
            let requestsBefore = marketRequests
            let priceBefore = state.watchlist.items.first?.lowestPrice
            state.refreshPriceAlerts()
            await quiesce()
            if marketRequests > requestsBefore { requestedAt.append(second) }
            if state.watchlist.items.first?.lowestPrice != priceBefore { priceChangedAt.append(second) }
        }

        XCTAssertEqual(requestedAt.filter { $0 <= 3_300 }, Array(stride(from: 0, through: 3_300, by: 300)),
                       "until a snapshot has been seen to change, Torn's schedule is unknown and every tick looks")
        XCTAssertEqual(requestedAt.filter { $0 > 3_300 }, [6_600, 6_900, 10_200, 10_500],
                       "after that: one look as the window closes and one that finds the new snapshot — two an hour, not twelve")
        XCTAssertEqual(priceChangedAt, [0, 3_300, 6_900],
                       "each new snapshot is noticed on the first tick after Torn publishes it")
        XCTAssertEqual(notifier.sent.map(\.title), ["Price Alert: Item 123", "Price Alert: Item 123"],
                       "950 crosses the threshold, 900 undercuts the price already announced")
    }

    func testReopeningTheTabDoesNotReAskForPricesItJustRead() async throws {
        state.watchlist.items = [item(123, threshold: nil), item(456, threshold: nil)]
        try serve(cachedAt: Self.firstCache, lowest: 950)
        let open = { self.state.refreshWatchlistPrices() }

        await after(0, expectRequests: 2, "opening the tab prices both items", refresh: open)
        await after(30, expectRequests: 2, "reopening it half a minute later asks for nothing", refresh: open)
        await after(AppState.priceAlertPollInterval, expectRequests: 4,
                    "minutes later the snapshot may have changed, so it looks again", refresh: open)
    }

    func testAFailedReadIsRetriedOnTheNextTick() async throws {
        state.watchlist.items = [item(123, threshold: 1_000)]
        try serve(cachedAt: Self.firstCache, lowest: 1_500)
        await tick(after: 0, expectRequests: 1, "the first price")

        mockSession.setHTTPError(statusCode: 502)
        await tick(after: 300, expectRequests: 2, "a tick that fails")
        XCTAssertNotNil(state.watchlist.items.first?.error)

        try serve(cachedAt: Self.firstCache, lowest: 1_500)
        await tick(after: 5, expectRequests: 3, "a retry does not wait out the recheck floor")
        XCTAssertNil(state.watchlist.items.first?.error)
    }

    /// With a 30-second cache a threshold set on a price that already met it was announced
    /// by the next read. With an hourly one that read may be an hour away, so the price
    /// MacTorn already holds has to answer for it.
    func testAThresholdAlreadyMetByTheHeldPriceAlertsOnTheNextTickWithoutARequest() async throws {
        state.watchlist.items = [item(123, threshold: nil)]
        try serve(cachedAt: Self.firstCache, lowest: 950)
        await after(0, expectRequests: 1, "the tab prices the item") { state.refreshWatchlistPrices() }
        XCTAssertTrue(notifier.sent.isEmpty, "no threshold, no alert")

        state.setWatchlistThreshold(1_000, for: 123)
        await tick(after: 60, expectRequests: 1, "the price was read a minute ago; nothing to ask Torn")

        XCTAssertEqual(notifier.sent.map(\.title), ["Price Alert: Item 123"])
        XCTAssertEqual(state.watchlist.items.first?.lastAlertedPrice, 950)

        await tick(after: 300, expectRequests: 2, "the next tick looks for a new snapshot")
        XCTAssertEqual(notifier.sent.count, 1, "and the same price is not announced twice")
    }

    /// The prices are over an hour old by design; the tab is judged by when it last asked.
    func testTabIsFreshAfterARecentCheckAndStaleOnceAChecksIsOverdue() async throws {
        state.watchlist.items = [item(123, threshold: 1_000)]
        try serve(cachedAt: Self.firstCache, lowest: 1_500)
        await tick(after: 0, expectRequests: 1, "the first price")

        XCTAssertEqual(state.watchlistPresentationState.kind, .fresh,
                       "a price Torn published 4,000 s ago, read just now, is as fresh as it gets")
        XCTAssertEqual(state.watchlistPresentationState.updatedAt, Self.start)

        clock.advance(3_600)
        XCTAssertEqual(state.watchlistPresentationState.kind, .fresh, "one cache window without a read is normal")

        clock.advance(601)
        XCTAssertEqual(state.watchlistPresentationState.kind, .stale,
                       "a window plus two alert ticks with no read means something stopped")
    }
}
