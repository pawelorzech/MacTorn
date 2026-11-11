import XCTest
@testable import MacTorn

@MainActor
final class MarketWatchServiceTests: XCTestCase {
    /// When a test "reads" Torn. Fixed, so nothing here depends on the wall clock.
    private static let readAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testOwnsValidatedStateAndPersistence() {
        let defaults = UserDefaults.createMockDefaults()
        let service = MarketWatchService(
            defaults: defaults
        )

        XCTAssertTrue(service.add(itemID: 123, name: "  Xanax  "))
        XCTAssertFalse(service.add(itemID: 123, name: "Duplicate"))
        XCTAssertFalse(service.add(itemID: 0, name: "Invalid"))
        XCTAssertEqual(service.items.map(\.name), ["Xanax"])

        let reloaded = MarketWatchService(
            defaults: defaults
        )
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.id), [123])
    }

    func testRestorePreservesFullItemAtOriginalIndex() {
        let defaults = UserDefaults.createMockDefaults()
        let service = MarketWatchService(defaults: defaults)
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

        // A restore is persisted, including the alert settings the undo exists to bring back.
        let reloaded = MarketWatchService(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(reloaded.items[1].priceThreshold, 80)
        XCTAssertEqual(reloaded.items[1].lastAlertedPrice, 75)
    }

    func testRemoveDropsOnlyTheNamedItem() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 123, name: "Xanax"), item(id: 456, name: "Donator Pack")]

        service.remove(itemID: 999)
        XCTAssertEqual(service.items.map(\.id), [123, 456])

        service.remove(itemID: 123)
        XCTAssertEqual(service.items.map(\.id), [456])
    }

    func testApplyingPriceUpdatesStateAndReturnsThresholdAlertOnce() {
        let service = MarketWatchService(
            defaults: .createMockDefaults()
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
            to: 7,
            at: Self.readAt
        )
        let second = service.apply(
            MarketPriceSnapshot(
                lowestPrice: 900,
                lowestPriceQuantity: 2,
                secondLowestPrice: 950
            ),
            to: 7,
            at: Self.readAt
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
            defaults: .createMockDefaults()
        )

        let result = try await TornAPIClient.loadJSON(from: URL(string: "https://api.torn.com/v2/market/123/itemmarket")!, session: mock, decode: MarketWatchService.decodePrice)

        guard case .success(let snapshot?, _) = result else {
            return XCTFail("Expected market price")
        }
        XCTAssertEqual(snapshot.lowestPrice, 950)
        XCTAssertEqual(snapshot.lowestPriceQuantity, 2)
        XCTAssertEqual(snapshot.secondLowestPrice, 1_000)
        XCTAssertEqual(snapshot.dataTimestamp, Date(timeIntervalSince1970: 1_783_107_206))
        XCTAssertEqual(snapshot.cacheDelay, 3_600)
    }

    func testRepeatedOrOlderSnapshotPreservesDataAgeAndDoesNotAlertAgain() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [WatchlistItem(id: 7, name: "Target", lowestPrice: 0,
                                       lowestPriceQuantity: 0, secondLowestPrice: 0,
                                       lastUpdated: nil, error: nil, priceThreshold: 1_000)]
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = service.apply(MarketPriceSnapshot(lowestPrice: 900, lowestPriceQuantity: 1,
                                                      secondLowestPrice: 950,
                                                      dataTimestamp: timestamp, cacheDelay: 30), to: 7, at: Self.readAt)
        let repeated = service.apply(MarketPriceSnapshot(lowestPrice: 800, lowestPriceQuantity: 1,
                                                         secondLowestPrice: 850,
                                                         dataTimestamp: timestamp, cacheDelay: 30), to: 7, at: Self.readAt)

        XCTAssertNotNil(first)
        XCTAssertNil(repeated)
        XCTAssertEqual(service.items[0].lowestPrice, 900,
                       "the same global snapshot must not masquerade as newer data")
        XCTAssertEqual(service.items[0].dataTimestamp, timestamp)
        XCTAssertNotNil(service.items[0].lastFetchedAt)
    }

    func testNewerSnapshotUpdatesPriceAndMissingDelayIsSafe() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 7, name: "Target")]
        service.apply(MarketPriceSnapshot(lowestPrice: 900, lowestPriceQuantity: 1,
                                          secondLowestPrice: 950,
                                          dataTimestamp: Date(timeIntervalSince1970: 100)), to: 7, at: Self.readAt)
        service.apply(MarketPriceSnapshot(lowestPrice: 800, lowestPriceQuantity: 1,
                                          secondLowestPrice: 850,
                                          dataTimestamp: Date(timeIntervalSince1970: 200)), to: 7, at: Self.readAt)
        XCTAssertEqual(service.items[0].lowestPrice, 800)
        XCTAssertNil(service.items[0].cacheDelay)
    }

    func testFetchPriceDistinguishesMalformedResponseFromEmptyListings() async throws {
        let mock = MockNetworkSession()
        let service = MarketWatchService(defaults: .createMockDefaults())
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
            guard case .malformed = try await TornAPIClient.loadJSON(from: url, session: mock, decode: MarketWatchService.decodePrice) else {
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
            guard case .success(nil, _) = try await TornAPIClient.loadJSON(from: url, session: mock, decode: MarketWatchService.decodePrice) else {
                XCTFail("An empty listings array must remain a valid empty market")
                continue
            }
        }
    }

    func testFetchPriceSurfacesV2APIError() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIErrorV2(code: 5, message: "Too many requests")
        let service = MarketWatchService(
            defaults: .createMockDefaults()
        )

        let result = try await TornAPIClient.loadJSON(from: URL(string: "https://api.torn.com/v2/market/123/itemmarket")!, session: mock, decode: MarketWatchService.decodePrice)

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected API error")
        }
        XCTAssertEqual(error.userMessage, "Too many requests — backing off.")
    }

    // MARK: - Torn's hourly global cache (2026-11-11)

    private func snapshot(price: Int, cachedAt: Date, delay: TimeInterval = 3_600) -> MarketPriceSnapshot {
        MarketPriceSnapshot(lowestPrice: price, lowestPriceQuantity: 1, secondLowestPrice: price + 10,
                            dataTimestamp: cachedAt, cacheDelay: delay)
    }

    /// Torn serves a snapshot that is already older than its own `cache_delay`, so the
    /// documented minimum says nothing about when the next one arrives. What does is
    /// having watched the snapshot change.
    func testWatchingASnapshotChangeTellsWhenTheNextOneCanArrive() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 7, name: "Target")]
        let start = Self.readAt
        let firstCache = start.addingTimeInterval(-4_000)

        service.apply(snapshot(price: 900, cachedAt: firstCache), to: 7, at: start)
        XCTAssertNil(service.items[0].refreshNotBefore, "a first price says nothing about Torn's schedule")

        service.apply(snapshot(price: 900, cachedAt: firstCache), to: 7, at: start.addingTimeInterval(300))
        XCTAssertNil(service.items[0].refreshNotBefore, "an unchanged snapshot teaches nothing either")

        service.apply(snapshot(price: 850, cachedAt: firstCache.addingTimeInterval(3_600)),
                      to: 7, at: start.addingTimeInterval(600))
        XCTAssertEqual(service.items[0].lowestPrice, 850)
        XCTAssertEqual(service.items[0].refreshNotBefore, start.addingTimeInterval(300 + 3_600),
                       "the old snapshot was still served at +300 s, so the next cannot come before +300 s + one window")
    }

    func testLearnedScheduleSurvivesARelaunch() {
        let defaults = UserDefaults.createMockDefaults()
        let service = MarketWatchService(defaults: defaults)
        XCTAssertTrue(service.add(itemID: 7, name: "Target"))
        let start = Self.readAt
        service.apply(snapshot(price: 900, cachedAt: start.addingTimeInterval(-4_000)), to: 7, at: start)
        service.apply(snapshot(price: 850, cachedAt: start.addingTimeInterval(-400)),
                      to: 7, at: start.addingTimeInterval(300))
        service.save()

        let reloaded = MarketWatchService(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.items.first?.refreshNotBefore, start.addingTimeInterval(3_600))
        XCTAssertEqual(reloaded.items.first?.cacheDelay, 3_600)
    }

    /// The first price of a newly added item must not inherit a schedule: there was no
    /// earlier read of an older snapshot to measure from.
    func testAPriceWithoutATimestampClearsTheLearnedSchedule() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 7, name: "Target")]
        let start = Self.readAt
        service.apply(snapshot(price: 900, cachedAt: start.addingTimeInterval(-4_000)), to: 7, at: start)
        service.apply(snapshot(price: 850, cachedAt: start.addingTimeInterval(-400)),
                      to: 7, at: start.addingTimeInterval(300))
        XCTAssertNotNil(service.items[0].refreshNotBefore)

        service.apply(MarketPriceSnapshot(lowestPrice: 800, lowestPriceQuantity: 1, secondLowestPrice: 810),
                      to: 7, at: start.addingTimeInterval(4_000))
        XCTAssertNil(service.items[0].refreshNotBefore)
        XCTAssertEqual(service.items[0].dataTimestamp, start.addingTimeInterval(4_000),
                       "with no cache timestamp, the read time stands in for the data's age")
    }

    func testHeldPriceLatchesAnAlertOnceAndNeverForAFailedRow() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 7, name: "Target")]
        service.apply(snapshot(price: 900, cachedAt: Self.readAt), to: 7, at: Self.readAt)
        XCTAssertNil(service.latchAlert(for: 7), "no threshold")

        service.items[0].priceThreshold = 1_000
        service.setError("Could not connect", for: 7)
        XCTAssertNil(service.latchAlert(for: 7), "a failed row's price is only the last one known")

        service.items[0].error = nil
        XCTAssertEqual(service.latchAlert(for: 7), MarketPriceAlert(name: "Target", price: 900))
        XCTAssertNil(service.latchAlert(for: 7), "announced once")
        XCTAssertNil(service.latchAlert(for: 99), "an item that is not watched")
    }

    func testPublishedPriceLagIsReportedOnlyWhenItMatters() {
        let service = MarketWatchService(defaults: .createMockDefaults())
        service.items = [item(id: 7, name: "Target"), item(id: 8, name: "Other")]
        XCTAssertNil(service.publishedPriceLag, "nothing priced yet")

        service.apply(snapshot(price: 900, cachedAt: Self.readAt, delay: 30), to: 7, at: Self.readAt)
        XCTAssertNil(service.publishedPriceLag, "a 30-second cache is not worth a sentence")

        service.apply(snapshot(price: 900, cachedAt: Self.readAt), to: 8, at: Self.readAt)
        XCTAssertEqual(service.publishedPriceLag, 3_600)
        XCTAssertEqual(TornFormatter.spelledDuration(3_600), "1 hour")
        XCTAssertEqual(TornFormatter.spelledDuration(7_200), "2 hours")
        XCTAssertEqual(TornFormatter.spelledDuration(300), "5 minutes")
        XCTAssertEqual(TornFormatter.spelledDuration(5_400), "90 minutes")
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
        MarketWatchService(defaults: defaults)
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

    // MARK: - Audit 2026-09-26: server-clock skew (regression from 141a3cd)

    /// Torn's `cache_timestamp` is on the server clock. With the Mac two hours behind,
    /// an un-converted timestamp sits two hours in the local future, so the refresh
    /// filter skipped the item for two hours and the label read "in 2 hours ago".
    func testLocalizedSnapshotMovesServerTimestampOntoLocalClock() {
        let serverTimestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ServerClock(offset: 7_200) // Mac is 2 h behind Torn
        let snapshot = MarketPriceSnapshot(lowestPrice: 1, lowestPriceQuantity: 1, secondLowestPrice: 0,
                                           dataTimestamp: serverTimestamp, cacheDelay: 30)
        let local = snapshot.localized(using: clock)
        XCTAssertEqual(local.dataTimestamp, Date(timeIntervalSince1970: 1_800_000_000 - 7_200))
        XCTAssertEqual(local.cacheDelay, 30)
    }

    func testLocalizedSnapshotIsIdentityWhenClocksAgree() {
        let ts = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = MarketPriceSnapshot(lowestPrice: 5, lowestPriceQuantity: 2, secondLowestPrice: 6,
                                           dataTimestamp: ts, cacheDelay: 30)
        XCTAssertEqual(snapshot.localized(using: .synchronized), snapshot)
    }

    /// A hostile or corrupt `cache_delay` is persisted with the item; unclamped it would
    /// freeze that item's refresh until it is removed and re-added.
    func testLocalizedSnapshotClampsCacheDelay() {
        func delay(_ raw: TimeInterval) -> TimeInterval? {
            MarketPriceSnapshot(lowestPrice: 1, lowestPriceQuantity: 1, secondLowestPrice: 0,
                                cacheDelay: raw).localized(using: .synchronized).cacheDelay
        }
        XCTAssertEqual(delay(1_000_000_000), MarketPriceSnapshot.maxCacheDelay)
        XCTAssertEqual(delay(-50), 0)
        XCTAssertEqual(delay(30), 30)
        XCTAssertEqual(delay(3_600), 3_600,
                       "Torn's hourly item-market cache (live since 2026-11-11) must not be cut down to minutes")
        XCTAssertNil(MarketPriceSnapshot(lowestPrice: 1, lowestPriceQuantity: 1, secondLowestPrice: 0)
            .localized(using: .synchronized).dataTimestamp)
    }
}
