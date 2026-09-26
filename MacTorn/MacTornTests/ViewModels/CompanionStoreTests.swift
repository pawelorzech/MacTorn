import XCTest
@testable import MacTorn

@MainActor
final class CompanionStoreTests: XCTestCase {
    private func makeApp(_ session: NetworkSession, defaults: UserDefaults = .createMockDefaults()) -> AppState {
        AppState(session: session, connectivity: ControllableConnectivity(), defaults: defaults,
                 accountSession: AccountSessionStore(defaults: defaults, credentialStore: CompanionTestKeyStore()))
    }
    func testStockWireKeepsFractionalTransactionPricesAndBonus() throws {
        let response = try JSONDecoder().decode(StocksV2Response.self, from: Data(#"{"stocks":[{"id":1,"shares":10,"bonus":{"available":true,"increment":1,"progress":7,"frequency":7},"transactions":[{"id":3,"shares":10,"price":12.75,"timestamp":100}]}]}"#.utf8))
        XCTAssertEqual(response.stocks[0].costBasis, 127.5)
        XCTAssertTrue(response.stocks[0].bonus.available)
    }
    func testRecruitingFiltersOccupiedSlotsAndCPRWithoutDeprecatedNumber() throws {
        let response = try JSONDecoder().decode(RecruitingResponse.self, from: Data(#"{"organizedcrimes":[{"id":1,"name":"Test crime","status":"Recruiting","slots":[{"position":"Muscle","position_info":{"id":"P1","label":"Muscle #1"},"checkpoint_pass_rate":90,"user":null},{"position":"Driver","position_info":{"id":"P2","label":"Driver"},"checkpoint_pass_rate":40,"user":null},{"position":"Thief","position_info":{"id":"P3","label":"Thief"},"checkpoint_pass_rate":99,"user":{"id":2}}]}]}"#.utf8))
        let store = CompanionStore(defaults: .createMockDefaults())
        store.minimumCPR = 70
        store.recruiting = response.organizedcrimes
        XCTAssertEqual(store.eligibleSlots.count, 1)
        XCTAssertEqual(store.eligibleSlots[0].slot.positionInfo.label, "Muscle #1")
    }
    func testEliminationNewFieldsDecodeAndOtherEventDoesNotActivateIt() throws {
        let data = Data(#"{"elimination":[{"id":2,"name":"Team","participants_left":23,"position":1,"score":8,"lives":10,"eliminated":false,"attacking_summary":[{"team_id":3,"attacks":12}]}]}"#.utf8)
        let teams = try JSONDecoder().decode(EliminationResponse.self, from: data).elimination
        XCTAssertEqual(teams[0].participantsLeft, 23)
        XCTAssertEqual(teams[0].attackingSummary[0].attacks, 12)
        let other = try JSONDecoder().decode(CompetitionResponse.self, from: Data(#"{"competition":{"name":"Halloween"}}"#.utf8))
        XCTAssertFalse(try XCTUnwrap(other.competition).isElimination)
    }
    func testShopsUseNewArrayWithNullablePrices() throws {
        let response = try JSONDecoder().decode(ShopsResponse.self, from: Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":123,"shops":[{"country":"Mexico","shop":"Flower shop","buy_price":50,"sell_price":null}]}}]}"#.utf8))
        XCTAssertEqual(response.items[0].value.shops[0].buyPrice, 50)
        XCTAssertNil(response.items[0].value.shops[0].sellPrice)
    }
    func testShopModuleReusesFreshItemCatalogRequestAndCache() async throws {
        let defaults = UserDefaults.createMockDefaults()
        let payload = Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":123,"shops":[{"country":"Mexico","shop":"Flower shop","buy_price":50,"sell_price":null}]}},{"id":3,"name":"Name only"}]}"#.utf8)
        let session = MockNetworkSession(mockData: payload)
        let app = makeApp(session, defaults: defaults)

        await app.fetchItemCatalog()
        XCTAssertEqual(session.requestedURLs.count, 1)
        XCTAssertEqual(app.itemCatalog[3], "Name only",
                       "an item without optional shop details must remain usable for names")

        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(session.requestedURLs.count, 1,
                       "enabling shops must reuse the fresh full-catalog response")
        XCTAssertEqual(app.companion.shops.first?.value.shops.first?.buyPrice, 50)

        app.companion.reset()
        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(session.requestedURLs.count, 1,
                       "account-scoped reset must reload the public cache without downloading it")
        XCTAssertEqual(app.companion.shops.map(\.id), [2])
    }

    func testMalformedCatalogRefreshPreservesCachedShops() async throws {
        let defaults = UserDefaults.createMockDefaults()
        let session = MockNetworkSession(mockData: Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":123,"shops":[{"country":"Mexico","shop":"Flowers","buy_price":50,"sell_price":null}]}}]}"#.utf8))
        let app = makeApp(session, defaults: defaults)
        await app.fetchItemCatalog()
        XCTAssertEqual(app.cachedShopItems().count, 1)

        session.mockData = Data(#"{"items":"broken"}"#.utf8)
        await app.fetchItemCatalog()
        XCTAssertEqual(app.cachedShopItems().count, 1)
        XCTAssertEqual(app.itemCatalog[2], "Flower")
    }
    func testShopEnableCoalescesWithCatalogRequestAlreadyInFlight() async {
        let payload = Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":123,"shops":[{"country":"Mexico","shop":"Flowers","buy_price":50,"sell_price":null}]}}]}"#.utf8)
        let session = CompanionSuspendedSession(responseData: payload)
        let app = makeApp(session)
        let catalog = Task { await app.fetchItemCatalog() }
        await session.waitForRequest()

        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        let countWhilePending = await session.requestCount
        XCTAssertEqual(countWhilePending, 1)

        await session.finish()
        await catalog.value
        app.companion.start(app: app)
        await app.companion.task?.value
        let finalCount = await session.requestCount
        XCTAssertEqual(finalCount, 1)
        XCTAssertEqual(app.companion.shops.map(\.id), [2])
        XCTAssertFalse(app.companion.loading.contains("torn.shops"))
    }
    func testShopGateDenialIsNotRecordedAsWeekLongSuccess() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"items":[]}"#.utf8))
        let app = makeApp(session)
        let infoData = try JSONSerialization.data(withJSONObject: [
            "info": [
                "access": ["level": 4, "type": "Custom", "faction": false, "company": false],
                "user": ["id": 42, "faction_id": NSNull(), "company_id": NSNull()],
                "selections": [
                    "user": [], "faction": [], "market": [], "property": [], "torn": [],
                    "racing": [], "forum": [], "key": ["info"], "company": []
                ]
            ]
        ])
        app.keyInfo = try JSONDecoder().decode(TornKeyInfo.Response.self, from: infoData).info
        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        await app.companion.task?.value

        XCTAssertTrue(session.requestedURLs.isEmpty)
        XCTAssertNotNil(app.companion.errors["torn.shops"])
        XCTAssertNil(app.companion.fetchedAt["torn.shops"])
        XCTAssertFalse(app.companion.loading.contains("torn.shops"))

        // A subsequent tick evaluates the gate again; denial never becomes the normal
        // one-week successful cadence.
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertNotNil(app.companion.errors["torn.shops"])
        XCTAssertNil(app.companion.fetchedAt["torn.shops"])
    }
    func testAlertBaselinesAndResetAreAccountScoped() {
        let store = CompanionStore(defaults: .createMockDefaults())
        XCTAssertTrue(store.newlyAvailable(["1"], feature: .stocks).isEmpty)
        XCTAssertTrue(store.newlyAvailable(["1"], feature: .stocks).isEmpty)
        XCTAssertEqual(store.newlyAvailable(["1", "2"], feature: .stocks), ["2"])
        store.reset()
        XCTAssertTrue(store.newlyAvailable(["1", "2"], feature: .stocks).isEmpty)
    }
    func testNoRequestsUntilOptedInAndNoDuplicatePollWithinCadence() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"trades":[]}"#.utf8))
        let app = makeApp(session)
        app.companion.start(app: app)
        XCTAssertNil(app.companion.task)
        app.companion.setEnabled(.trades, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(session.requestedURLs.count, 1)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(session.requestedURLs.count, 1)
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, 1)
        app.companion.reset()
    }
    func testCompetitionOutsideEliminationDoesNotFetchTeams() async {
        let session = MockNetworkSession(mockData: Data(#"{"competition":{"name":"Halloween"}}"#.utf8))
        let app = makeApp(session)
        app.companion.setEnabled(.competition, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(session.requestedURLs.map(\.path), ["/v2/user/competition"])
        app.companion.reset()
    }
    func testMalformedResponsePreservesLastGoodDataAndShowsError() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"trades":[{"id":1,"user":{"id":1},"trader":{"id":2},"description":"Exchange","completed_at":null,"expires_at":500,"modified_at":100}]}"#.utf8))
        let app = makeApp(session)
        app.companion.setEnabled(.trades, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertEqual(app.companion.trades.count, 1)
        session.mockData = Data(#"{"trades":"broken"}"#.utf8)
        let result: TradesResponse? = await app.companion.request("user.trades", app: app)
        XCTAssertNil(result)
        XCTAssertEqual(app.companion.trades.count, 1)
        XCTAssertNotNil(app.companion.errors["user.trades"])
        app.companion.reset()
    }
    /// Enabling v2 "Stock bonuses" must not strip `stocks` from the fast poll: the Money
    /// tab's Total Tracked and the Stocks tab state read `stocksData`, which only the
    /// fast poll fills. The selection rides the same request, so keeping it costs nothing.
    /// (Audit 2026-09-26, regression from 141a3cd.)
    func testEnablingV2StocksKeepsLegacyStocksSelection() {
        let app = makeApp(MockNetworkSession())
        func selections() -> String? {
            URLComponents(url: app.endpointURL("user.fast")!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "selections" }?.value
        }
        XCTAssertTrue(selections()!.split(separator: ",").contains("stocks"))
        app.companion.setEnabled(.stocks, true)
        XCTAssertTrue(selections()!.split(separator: ",").contains("stocks"))
    }
    func testEnablingV2StocksStillPopulatesStocksDataFromFastPoll() async throws {
        let session = MockNetworkSession()
        let app = makeApp(session)
        app.apiKey = "valid_key"
        app.companion.setEnabled(.stocks, true)
        var json = TornAPIFixtures.validFullResponse()
        json["stocks"] = TornAPIFixtures.stocksData["stocks"]
        try session.setSuccessResponse(json: json)
        app.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNotNil(app.data, "precondition: the fast poll applied")
        XCTAssertFalse(app.stocksData.isEmpty,
                       "Money Total Tracked must keep counting stocks with Stock bonuses on")
    }
    func testWarfareUsesOnlyTimestampFromNextLinkAndCompletedChainCategory() throws {
        let page = WarfarePage.parse(["warfarechains": [["id": 12, "chain": 100, "start": 200, "end": 300, "faction": ["name": "Team"]]],
                                     "_metadata": ["links": ["next": "https://untrusted.invalid/?key=secret&to=199"]]], category: .chains)
        XCTAssertEqual(page?.nextTo, 199)
        XCTAssertEqual(page?.entries.first?.detail, "100 hits")
        let url = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "faction.warfarechains")?.url(key: "test"))
        XCTAssertEqual(url.host, "api.torn.com")
        XCTAssertTrue(url.query!.contains("cat=complete"))
    }
    func testGlobalWarfareIsAllowedForFactionlessKey() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "info": [
                "access": ["level": 1, "type": "Public Only", "faction": false, "company": false],
                "user": ["id": 42, "faction_id": NSNull(), "company_id": NSNull()],
                "selections": [
                    "user": [], "faction": ["warfareranked"], "market": [], "property": [],
                    "torn": [], "racing": [], "forum": [], "key": ["info"], "company": []
                ]
            ]
        ])
        let info = try JSONDecoder().decode(TornKeyInfo.Response.self, from: data).info
        let app = makeApp(MockNetworkSession())
        XCTAssertNil(app.endpointGate.denial(for: "faction.warfareranked", keyInfo: info,
                                              coordinator: app.pollingCoordinator))
        XCTAssertFalse(try XCTUnwrap(TornEndpointRegistry.endpoint(id: "faction.warfareranked")).requiresFaction)
    }
    func testShopDisableDuringFetchCannotRepublishSuccess() async {
        let session = CompanionSuspendedSession(responseData: Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":100,"shops":[{"country":"Mexico","shop":"Shop","buy_price":50,"sell_price":null}]}}]}"#.utf8))
        let app = makeApp(session)
        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        let pending = app.companion.task
        await session.waitForRequest()
        app.companion.setEnabled(.shops, false)
        await session.finish()
        await pending?.value
        XCTAssertTrue(app.companion.shops.isEmpty)
        XCTAssertNil(app.companion.fetchedAt["torn.shops"])
        XCTAssertNil(app.companion.errors["torn.shops"])
        XCTAssertTrue(app.companion.loading.isEmpty)
    }

    func testShopAccountChangeDuringFetchCannotRepublishSuccess() async {
        let session = CompanionSuspendedSession(responseData: Data(#"{"items":[{"id":2,"name":"Flower","value":{"market_price":100,"shops":[]}}]}"#.utf8))
        let app = makeApp(session)
        app.companion.setEnabled(.shops, true)
        app.companion.start(app: app)
        let pending = app.companion.task
        await session.waitForRequest()
        app.apiKey = "other-account"
        await session.finish()
        await pending?.value
        XCTAssertTrue(app.companion.shops.isEmpty)
        XCTAssertNil(app.companion.fetchedAt["torn.shops"])
        XCTAssertNil(app.companion.errors["torn.shops"])
    }

    func testAccountSwitchDiscardsInFlightResponse() async {
        let session = CompanionSuspendedSession()
        let app = makeApp(session)
        let pending = Task { () -> TradesResponse? in await app.companion.request("user.trades", app: app) }
        await session.waitForRequest()
        app.apiKey = "other-test-key"
        await session.finish()
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertNil(app.companion.fetchedAt["user.trades"])
        XCTAssertTrue(app.companion.loading.isEmpty)
    }
    func testDisableFeatureDiscardsInFlightResponse() async {
        let session = CompanionSuspendedSession()
        let app = makeApp(session)
        app.companion.setEnabled(.trades, true)
        let pending = Task { () -> TradesResponse? in await app.companion.request("user.trades", app: app) }
        await session.waitForRequest()
        app.companion.setEnabled(.trades, false)
        await session.finish()
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertNil(app.companion.fetchedAt["user.trades"])
    }
}
private final class CompanionTestKeyStore: APIKeyStoring, @unchecked Sendable {
    private var key = "companion-test-key"
    func get() -> String? { key }
    func set(_ value: String) { key = value }
}
private actor CompanionSuspendedSession: NetworkSession {
    private var waiting: CheckedContinuation<Void, Never>?
    private var requested = false
    private(set) var requestCount = 0
    private let responseData: Data
    init(responseData: Data = Data(#"{"trades":[]}"#.utf8)) { self.responseData = responseData }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requested = true
        requestCount += 1
        await withCheckedContinuation { waiting = $0 }
        return (responseData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func waitForRequest() async { while !requested { await Task.yield() } }
    func finish() { waiting?.resume(); waiting = nil }
}
