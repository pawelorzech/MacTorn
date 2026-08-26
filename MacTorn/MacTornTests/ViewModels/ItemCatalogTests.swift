import XCTest
import os.log
@testable import MacTorn

/// The item catalog turns "Item #206" into "Xanax" and lets the watchlist be searched by
/// name. These tests cover the parse, the search ranking, and the one rule that keeps the
/// backfill safe: it may only overwrite the app's own placeholders.
@MainActor
final class ItemCatalogTests: XCTestCase {

    private let logger = Logger(subsystem: "com.mactorn.tests", category: "ItemCatalog")

    private func makeState() -> AppState {
        AppState(session: MockNetworkSession(),
                 defaults: UserDefaults(suiteName: "com.mactorn.tests.\(UUID().uuidString)")!)
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Parsing

    func testParsesTheSpecShapeDownToIdAndName() {
        let data = json(["items": [
            ["id": 206, "name": "Xanax", "type": "Drug", "circulation": 500_000],
            ["id": 180, "name": "Erotic DVD", "type": "Special"],
        ]])
        let parsed = AppState.parseItemCatalog(from: data, logger: logger)
        XCTAssertEqual(parsed, [206: "Xanax", 180: "Erotic DVD"])
    }

    func testSkipsEntriesThatCannotBeUsedRatherThanFailingTheWholeParse() {
        let data = json(["items": [
            ["id": 206, "name": "Xanax"],
            ["name": "No id here"],
            ["id": 999],
            ["id": 500, "name": "   "],
            ["id": 261, "name": "Energy Drink"],
        ]])
        let parsed = AppState.parseItemCatalog(from: data, logger: logger)
        XCTAssertEqual(parsed, [206: "Xanax", 261: "Energy Drink"],
                       "one malformed row must not cost the other 1,400")
    }

    func testAnErrorEnvelopeYieldsNothingRatherThanAPartialCatalog() {
        let data = json(["error": ["code": 2, "error": "Incorrect key"]])
        XCTAssertTrue(AppState.parseItemCatalog(from: data, logger: logger).isEmpty)
    }

    func testNonJSONYieldsNothing() {
        XCTAssertTrue(AppState.parseItemCatalog(from: Data("not json".utf8), logger: logger).isEmpty)
    }

    func testFetchPropagatesTypedRateLimitAccountWide() async throws {
        let mock = MockNetworkSession()
        try mock.setTornAPIErrorV2(code: 5, message: "Too many requests")
        let state = AppState(session: mock, defaults: .createMockDefaults())
        state.apiKey = "rate-limited"

        await state.fetchItemCatalog()

        XCTAssertTrue(state.isRowSourcePaused("forum.thread"),
                      "code 5 from reference data must pause unrelated endpoint families")
        XCTAssertEqual(state.endpointHealth.latest(for: "torn.items")?.errorClass, "rateLimit")
        state.stopPolling()
    }

    func testNamesAreTrimmed() {
        let data = json(["items": [["id": 1, "name": "  Padded Name  "]]])
        XCTAssertEqual(AppState.parseItemCatalog(from: data, logger: logger)[1], "Padded Name")
    }

    // MARK: - Lookup

    func testNameFallsBackToThePlaceholderWithoutACatalog() {
        XCTAssertEqual(makeState().itemName(for: 206), "Item #206")
    }

    func testNameComesFromTheCatalogOnceItIsThere() {
        let state = makeState()
        state.itemCatalog = [206: "Xanax"]
        XCTAssertEqual(state.itemName(for: 206), "Xanax")
        XCTAssertEqual(state.itemName(for: 999), "Item #999", "an unknown id still gets a label")
    }

    // MARK: - Search

    func testSearchRanksPrefixMatchesAboveSubstringMatches() {
        let state = makeState()
        state.itemCatalog = [1: "Beer", 2: "Ice Beer", 3: "Bee Costume"]
        XCTAssertEqual(state.searchItems("bee").map(\.name), ["Bee Costume", "Beer", "Ice Beer"])
    }

    func testSearchIsCaseInsensitive() {
        let state = makeState()
        state.itemCatalog = [206: "Xanax"]
        XCTAssertEqual(state.searchItems("XAN").map(\.id), [206])
        XCTAssertEqual(state.searchItems("xan").map(\.id), [206])
    }

    func testSearchIgnoresSurroundingWhitespaceAndEmptyQueries() {
        let state = makeState()
        state.itemCatalog = [206: "Xanax"]
        XCTAssertEqual(state.searchItems("  xanax  ").map(\.id), [206])
        XCTAssertTrue(state.searchItems("").isEmpty)
        XCTAssertTrue(state.searchItems("   ").isEmpty)
    }

    /// A two-letter query matches hundreds of the ~1,400 items. The popover cannot render
    /// hundreds of rows, so the limit is part of the contract, not an optimisation.
    func testSearchIsCappedSoThePopoverStaysRenderable() {
        let state = makeState()
        state.itemCatalog = Dictionary(uniqueKeysWithValues: (1...200).map { ($0, "Item \($0) alpha") })
        XCTAssertEqual(state.searchItems("alpha").count, 12)
        XCTAssertEqual(state.searchItems("alpha", limit: 3).count, 3)
    }

    func testSearchReturnsNothingWhenTheCatalogIsEmpty() {
        XCTAssertTrue(makeState().searchItems("xanax").isEmpty)
    }

    // MARK: - Backfill

    func testBackfillReplacesPlaceholderNames() {
        let state = makeState()
        XCTAssertTrue(state.addToWatchlist(itemId: 206, name: "Item #206"))
        state.itemCatalog = [206: "Xanax"]
        state.backfillWatchlistNames()
        XCTAssertEqual(state.watchlistItems.first?.name, "Xanax")
    }

    /// A name the user typed is theirs. The catalog arriving is not a reason to overwrite
    /// it — that would silently undo a deliberate edit.
    func testBackfillLeavesUserChosenNamesAlone() {
        let state = makeState()
        XCTAssertTrue(state.addToWatchlist(itemId: 206, name: "My Xanax Stash"))
        state.itemCatalog = [206: "Xanax"]
        state.backfillWatchlistNames()
        XCTAssertEqual(state.watchlistItems.first?.name, "My Xanax Stash")
    }

    func testBackfillPreservesPriceStateAndThresholds() {
        let state = makeState()
        XCTAssertTrue(state.addToWatchlist(itemId: 206, name: "Item #206"))
        state.watchlistItems[0].lowestPrice = 830_000
        state.watchlistItems[0].priceThreshold = 800_000
        state.watchlistItems[0].lastAlertedPrice = 795_000

        state.itemCatalog = [206: "Xanax"]
        state.backfillWatchlistNames()

        let item = state.watchlistItems[0]
        XCTAssertEqual(item.name, "Xanax")
        XCTAssertEqual(item.id, 206, "the id is the identity; a rename must not move it")
        XCTAssertEqual(item.lowestPrice, 830_000)
        XCTAssertEqual(item.priceThreshold, 800_000)
        XCTAssertEqual(item.lastAlertedPrice, 795_000)
    }

    func testBackfillWithoutACatalogChangesNothing() {
        let state = makeState()
        XCTAssertTrue(state.addToWatchlist(itemId: 206, name: "Item #206"))
        state.backfillWatchlistNames()
        XCTAssertEqual(state.watchlistItems.first?.name, "Item #206")
    }

    // MARK: - Adding

    func testAddingByIdUsesTheCatalogNameWhenItIsKnown() {
        let state = makeState()
        state.itemCatalog = [206: "Xanax"]
        XCTAssertEqual(state.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(state.watchlistItems.first?.name, "Xanax")
    }

    func testAddingByIdStillWorksWithoutACatalog() {
        let state = makeState()
        XCTAssertEqual(state.addToWatchlist(input: "206"), .added(itemId: 206))
        XCTAssertEqual(state.watchlistItems.first?.name, "Item #206")
    }
}
