import XCTest
@testable import MacTorn

final class WatchlistItemTests: XCTestCase {

    // MARK: - priceDifference Tests

    func testPriceDifference_normalCase() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 100)
    }

    func testPriceDifference_samePrices() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1000,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    func testPriceDifference_noSecondPrice() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 0,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    func testPriceDifference_noLowestPrice() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertEqual(item.priceDifference, 0)
    }

    // MARK: - isLoading Tests

    func testIsLoading_loading() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: nil
        )

        XCTAssertTrue(item.isLoading)
    }

    func testIsLoading_loaded() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 1000,
            lowestPriceQuantity: 5,
            secondLowestPrice: 1100,
            lastUpdated: Date(),
            error: nil
        )

        XCTAssertFalse(item.isLoading)
    }

    func testIsLoading_hasError() {
        let item = WatchlistItem(
            id: 1,
            name: "Test Item",
            lowestPrice: 0,
            lowestPriceQuantity: 0,
            secondLowestPrice: 0,
            lastUpdated: nil,
            error: "No listings"
        )

        // Has error, so not loading
        XCTAssertFalse(item.isLoading)
    }

    // MARK: - Decoding Tests

    func testDecoding_fullItem() throws {
        let json: [String: Any] = [
            "id": 123,
            "name": "Xanax",
            "lowestPrice": 850000,
            "lowestPriceQuantity": 10,
            "secondLowestPrice": 860000,
            "lastUpdated": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.id, 123)
        XCTAssertEqual(item.name, "Xanax")
        XCTAssertEqual(item.lowestPrice, 850000)
        XCTAssertEqual(item.lowestPriceQuantity, 10)
        XCTAssertEqual(item.secondLowestPrice, 860000)
    }

    func testDecoding_legacyItemMissingFields() throws {
        // Legacy items might not have all fields
        let json: [String: Any] = [
            "id": 123,
            "name": "Xanax"
            // Missing price fields
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.id, 123)
        XCTAssertEqual(item.name, "Xanax")
        XCTAssertEqual(item.lowestPrice, 0) // Default
        XCTAssertEqual(item.lowestPriceQuantity, 0) // Default
        XCTAssertEqual(item.secondLowestPrice, 0) // Default
    }

    func testDecoding_withError() throws {
        let json: [String: Any] = [
            "id": 123,
            "name": "Invalid Item",
            "lowestPrice": 0,
            "lowestPriceQuantity": 0,
            "secondLowestPrice": 0,
            "error": "Item not found"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(WatchlistItem.self, from: data)

        XCTAssertEqual(item.error, "Item not found")
        XCTAssertFalse(item.isLoading)
    }

    // MARK: - Refresh schedule (Torn's hourly item-market cache, 2026-11-11)

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An item as it looks after a read `checkedAgo` seconds ago returned a snapshot Torn
    /// cached `cachedAgo` seconds ago.
    private func pricedItem(cachedAgo: TimeInterval, checkedAgo: TimeInterval,
                            delay: TimeInterval? = 3_600, notBefore: TimeInterval? = nil,
                            error: String? = nil) -> WatchlistItem {
        WatchlistItem(id: 206, name: "Xanax", lowestPrice: 900, lowestPriceQuantity: 1,
                      secondLowestPrice: 950, lastUpdated: Self.now.addingTimeInterval(-cachedAgo),
                      error: error, lastFetchedAt: Self.now.addingTimeInterval(-checkedAgo),
                      dataTimestamp: Self.now.addingTimeInterval(-cachedAgo), cacheDelay: delay,
                      refreshNotBefore: notBefore.map { Self.now.addingTimeInterval($0) })
    }

    func testRefreshIsDueForAnItemThatWasNeverPriced() {
        let item = WatchlistItem(id: 206, name: "Xanax", lowestPrice: 0, lowestPriceQuantity: 0,
                                 secondLowestPrice: 0, lastUpdated: nil, error: nil)
        XCTAssertTrue(item.isRefreshDue(at: Self.now))
    }

    func testRefreshWaitsOutTornsDocumentedCacheDelay() {
        let item = pricedItem(cachedAgo: 600, checkedAgo: 600)
        XCTAssertFalse(item.isRefreshDue(at: Self.now), "Torn cannot have a newer snapshot for another 50 minutes")
        XCTAssertFalse(item.isRefreshDue(at: Self.now.addingTimeInterval(2_999)))
        XCTAssertTrue(item.isRefreshDue(at: Self.now.addingTimeInterval(3_000)))
    }

    /// What Torn actually serves since 2026-11-11: a snapshot already older than its
    /// `cache_delay`. The documented minimum has passed, so only the recheck floor paces it.
    func testASnapshotOlderThanItsCacheDelayIsRecheckedAtTheAlertCadenceNotOnEveryAsk() {
        let item = pricedItem(cachedAgo: 6_100, checkedAgo: 10)
        XCTAssertFalse(item.isRefreshDue(at: Self.now), "reopening the tab seconds later must not re-ask")
        XCTAssertFalse(item.isRefreshDue(at: Self.now.addingTimeInterval(229)))
        XCTAssertTrue(item.isRefreshDue(at: Self.now.addingTimeInterval(230)))
        XCTAssertLessThan(WatchlistItem.minimumRecheckInterval, AppState.priceAlertPollInterval,
                          "the floor must sit under the alert tick, or every other tick would be skipped")
    }

    func testRefreshWaitsForTheLearnedNextSnapshot() {
        let item = pricedItem(cachedAgo: 3_700, checkedAgo: 300, notBefore: 3_000)
        XCTAssertFalse(item.isRefreshDue(at: Self.now))
        XCTAssertFalse(item.isRefreshDue(at: Self.now.addingTimeInterval(2_999)))
        XCTAssertTrue(item.isRefreshDue(at: Self.now.addingTimeInterval(3_000)))
    }

    /// A failed read is retried on the next ask: the floor exists to stop repeats of a
    /// read that worked.
    func testAFailedReadIsRetriedWithoutWaitingOutTheFloor() {
        let item = pricedItem(cachedAgo: 6_100, checkedAgo: 10, error: "Could not connect")
        XCTAssertTrue(item.isRefreshDue(at: Self.now))
    }

    /// Without a `cache_delay` there is no schedule to honour — the pre-2025 response shape.
    func testAnItemWithoutACacheDelayIsAlwaysDue() {
        XCTAssertTrue(pricedItem(cachedAgo: 5, checkedAgo: 5, delay: nil).isRefreshDue(at: Self.now))
    }

    /// The wait can never exceed one cache window. One that does comes from a Mac clock
    /// that was set back, and must not freeze the item until the clock catches up.
    func testAWaitLongerThanOneCacheWindowIsTreatedAsAClockChange() {
        XCTAssertTrue(pricedItem(cachedAgo: 3_700, checkedAgo: 300, notBefore: 86_400).isRefreshDue(at: Self.now))
        XCTAssertTrue(pricedItem(cachedAgo: -86_400, checkedAgo: -86_400).isRefreshDue(at: Self.now),
                      "a cache timestamp a day in the future")
        // Set back by less than a window: the last read now lies in the future, which no
        // clock that only runs forward can produce.
        XCTAssertTrue(pricedItem(cachedAgo: 3_000, checkedAgo: -1_800, notBefore: 3_000).isRefreshDue(at: Self.now),
                      "a clock set back half an hour must not hold the item for that half hour")
    }

    func testRenamingKeepsTheRefreshSchedule() {
        let item = pricedItem(cachedAgo: 3_700, checkedAgo: 300, notBefore: 3_000)
        XCTAssertEqual(item.renamed(to: "Xanax (new name)").refreshNotBefore, item.refreshNotBefore)
    }

    func testRefreshScheduleRoundTripsThroughPersistence() throws {
        let item = pricedItem(cachedAgo: 3_700, checkedAgo: 300, notBefore: 3_000)
        let decoded = try JSONDecoder().decode(WatchlistItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.refreshNotBefore, item.refreshNotBefore)
        XCTAssertEqual(decoded.cacheDelay, 3_600)
    }
}
