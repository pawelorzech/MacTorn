import XCTest
@testable import MacTorn

@MainActor
final class CompanionStoreTests: XCTestCase {
    func testOnDemandHistoryExplainsOfflineAndDoesNotSpendBudget() async {
        let app = makeApp(MockNetworkSession())
        (app.connectivity as? ControllableConnectivity)?.goOffline()
        await app.companion.loadWarfare(.ranked, app: app)
        XCTAssertTrue(app.companion.errors["faction.warfareranked"]?.contains("No internet connection") == true)
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, 0)
        XCTAssertTrue(app.companion.loading.isEmpty)
    }

    func testOptionalModuleExplainsMissingPermissionsBeforeBuildingNarrowedURL() async {
        let app = makeApp(MockNetworkSession())
        app.keyInfo = TornKeyInfo(
            access: .init(level: 1, type: "Custom", faction: false, company: false),
            user: .init(id: 42, factionId: nil, companyId: nil),
            selections: .init(user: ["bars"], faction: [], market: [], property: [], torn: [],
                              racing: [], forum: [], key: ["info"], company: [])
        )
        let value: CompetitionResponse? = await app.companion.request("user.competition", app: app)
        XCTAssertNil(value)
        XCTAssertNotNil(app.companion.errors["user.competition"])
        XCTAssertEqual(app.pollingCoordinator.requestsInLastMinute, 0)
    }

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
        XCTAssertEqual(session.requestedURLs.map(\.path), ["/v2/user/competition", "/v2/torn/calendar", "/v2/user/calendar"])
        app.companion.reset()
    }
    // MARK: - Competition variants, error codes 32/33, calendar

    private func decodeCompetition(_ json: String) throws -> CompetitionV2? {
        try JSONDecoder().decode(CompetitionResponse.self, from: Data(json.utf8)).competition
    }
    func testAllFourCompetitionVariantsAndNullDecode() throws {
        let rps = try XCTUnwrap(decodeCompetition(#"{"competition":{"name":"Rock, Paper, Scissors","status":"scissors","hp":{"current":669,"maximum":671}}}"#))
        XCTAssertEqual(rps.status, "scissors")
        XCTAssertEqual(rps.hp?.current, 669)
        XCTAssertEqual(rps.hp?.maximum, 671)
        XCTAssertFalse(rps.isElimination)
        let halloween = try XCTUnwrap(decodeCompetition(#"{"competition":{"name":"Halloween","treats_collected":12,"basket":{"id":3,"name":"Pumpkin"}}}"#))
        XCTAssertEqual(halloween.treatsCollected, 12)
        XCTAssertEqual(halloween.basket?.name, "Pumpkin")
        let easter = try XCTUnwrap(decodeCompetition(#"{"competition":{"name":"Easter Egg Hunt","score":3,"total":10}}"#))
        XCTAssertEqual(easter.score, 3)
        XCTAssertEqual(easter.total, 10)
        let elimination = try XCTUnwrap(decodeCompetition(#"{"competition":{"name":"Elimination","score":5,"attacks":2,"team":"Red","team_id":4}}"#))
        XCTAssertTrue(elimination.isElimination)
        XCTAssertEqual(elimination.teamId, 4)
        XCTAssertNil(try decodeCompetition(#"{"competition":null}"#))
    }
    func testNoCompetitionCodeIsNotAvailableAndNotAFault() {
        for code in [32, 33] {
            let error = TornAPIError.classify(code: code, message: "x")
            XCTAssertEqual(error.classification, .notAvailable)
            XCTAssertEqual(error.tornCode, code)
            XCTAssertFalse(error.haltsAllRequests)
            XCTAssertFalse(error.disablesEndpoint)
            XCTAssertNil(error.pauseDuration)
        }
    }
    private let eliminationJSON = #"{"competition":{"name":"Elimination","score":5,"attacks":2,"team":"Red","team_id":4}}"#
    private func seedElimination(_ app: AppState) throws {
        app.companion.competition = try decodeCompetition(eliminationJSON)
        app.companion.teams = try JSONDecoder().decode(EliminationResponse.self, from: Data(#"{"elimination":[{"id":4,"name":"Red","participants_left":23,"position":1,"score":8,"lives":10,"eliminated":false,"attacking_summary":[]}]}"#.utf8)).elimination
    }
    func testNoCompetitionCodeClearsStateWithoutErrorOrHealthFailure() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"error":{"code":33,"error":"No competition available"}}"#.utf8))
        let app = makeApp(session)
        try seedElimination(app)
        app.companion.setEnabled(.competition, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertNil(app.companion.competition)
        XCTAssertTrue(app.companion.teams.isEmpty)
        XCTAssertNil(app.companion.errors["user.competition"])
        XCTAssertEqual(app.companion.notAvailable["user.competition"], 33)
        XCTAssertEqual(app.endpointHealth.latest(for: "user.competition")?.outcome, .ok)
        XCTAssertNil(app.errorMsg)
        app.companion.reset()
    }
    func testClosedEliminationCodeKeepsTeamsAndRecordsNoFailure() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"error":{"code":32,"error":"Closed"}}"#.utf8))
        let app = makeApp(session)
        try seedElimination(app)
        app.companion.setEnabled(.competition, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertNotNil(app.companion.competition)
        XCTAssertEqual(app.companion.teams.count, 1)
        XCTAssertEqual(app.companion.notAvailable["torn.elimination"], 32)
        XCTAssertNil(app.companion.errors["torn.elimination"])
        XCTAssertEqual(app.endpointHealth.latest(for: "torn.elimination")?.outcome, .ok)
        app.companion.reset()
    }
    func testNullCompetitionClearsStateThroughRefresh() async throws {
        let session = MockNetworkSession(mockData: Data(#"{"competition":null}"#.utf8))
        let app = makeApp(session)
        try seedElimination(app)
        app.companion.setEnabled(.competition, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertNil(app.companion.competition)
        XCTAssertTrue(app.companion.teams.isEmpty)
        XCTAssertNil(app.companion.errors["user.competition"])
        app.companion.reset()
    }

    private func liveCalendar() throws -> TornCalendarResponse {
        let json = #"""
        {"calendar":{"competitions":[{"title":"Elimination","description":"d","start":1820145600,"end":1789732800,"fixed_start_time":true}],
        "events":[{"title":"Weekend Road Trip","description":"d","start":1801396800,"end":1770033599,"fixed_start_time":true},
        {"title":"Valentine's Day","description":"d","start":1771027200,"end":1771113599,"fixed_start_time":false}]}}
        """#
        return try JSONDecoder().decode(TornCalendarResponse.self, from: Data(json.utf8))
    }
    func testCalendarEndBeforeStartQuirkUsesNextOccurrence() throws {
        let cal = try liveCalendar().calendar
        let elimination = CalendarEntry(cal.competitions[0], isCompetition: true, personalOffset: nil)
        // Start 2027-09-05 12:00 UTC; 2026-09-05 -> 2026-09-18 12:00 is 13 days, so it ends 2027-09-18.
        XCTAssertEqual(elimination.start, Date(timeIntervalSince1970: 1820145600))
        XCTAssertEqual(elimination.end, Date(timeIntervalSince1970: 1820145600 + 13 * 86_400))
        let trip = CalendarEntry(cal.events[0], isCompetition: false, personalOffset: nil)
        XCTAssertEqual(trip.start, Date(timeIntervalSince1970: 1801396800))
        XCTAssertEqual(trip.end.timeIntervalSince(trip.start), 1770033599 - (1801396800 - 365 * 86_400), accuracy: 0)
        XCTAssertTrue(trip.end > trip.start)
    }
    func testNonFixedActivitiesShiftByPersonalStartTimeAndFixedDoNot() throws {
        let cal = try liveCalendar().calendar
        let offset = CalendarEntry.offset(from: "10:30 TCT")
        XCTAssertEqual(offset, 37_800)
        let valentine = CalendarEntry(cal.events[1], isCompetition: false, personalOffset: offset)
        XCTAssertEqual(valentine.start, Date(timeIntervalSince1970: 1771027200 + 37_800))
        XCTAssertEqual(valentine.end, Date(timeIntervalSince1970: 1771113599 + 37_800))
        let fixed = CalendarEntry(cal.events[0], isCompetition: false, personalOffset: offset)
        XCTAssertEqual(fixed.start, Date(timeIntervalSince1970: 1801396800))
    }
    func testMalformedStartTimeMeansNoShift() throws {
        for bad in [nil, "", "10:30", "25:00 TCT", "10:61 TCT", "ab:cd TCT", "10:30 UTC", "10:30:00 TCT"] as [String?] {
            XCTAssertNil(CalendarEntry.offset(from: bad), "\(bad ?? "nil")")
        }
        let entry = CalendarEntry(try liveCalendar().calendar.events[1], isCompetition: false,
                                  personalOffset: CalendarEntry.offset(from: "garbage"))
        XCTAssertEqual(entry.start, Date(timeIntervalSince1970: 1771027200))
    }
    func testUserCalendarStartTimeDecodes() throws {
        let value = try JSONDecoder().decode(UserCalendarResponse.self, from: Data(#"{"calendar":{"start_time":"10:30 TCT"}}"#.utf8))
        XCTAssertEqual(value.calendar.startTime, "10:30 TCT")
    }
    func testCalendarSelectsActiveAndNextThreeUpcomingAtFixedNow() {
        func entry(_ title: String, _ start: Int, _ end: Int) -> CalendarEntry {
            CalendarEntry(CalendarActivity(title: title, description: "", start: start, end: end, fixedStartTime: true),
                          isCompetition: false, personalOffset: nil)
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entries = [
            entry("Past", 100, 200), entry("Later", 1_400_000, 1_500_000), entry("Active B", 900_000, 1_200_000),
            entry("Soon", 1_100_000, 1_150_000), entry("Active A", 950_000, 1_050_000),
            entry("Mid", 1_300_000, 1_350_000), entry("Far", 1_900_000, 2_000_000),
        ]
        let (active, upcoming) = CalendarEntry.select(entries, now: now)
        XCTAssertEqual(active.map(\.title), ["Active A", "Active B"])
        XCTAssertEqual(upcoming.map(\.title), ["Soon", "Mid", "Later"])
    }
    func testCalendarEndpointsLoadIntoStoreAndUserCalendarIsOptional() async throws {
        let session = MockNetworkSession(mockData: try JSONEncoder().encode(
            ["calendar": ["competitions": [String](), "events": [String]()]]))
        let app = makeApp(session)
        app.companion.setEnabled(.competition, true)
        app.companion.start(app: app)
        await app.companion.task?.value
        XCTAssertNotNil(app.companion.fetchedAt["torn.calendar"])
        XCTAssertNil(app.companion.calendarStartTime)
        XCTAssertTrue(app.companion.calendarEntries.isEmpty)
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
    @discardableResult func set(_ value: String) -> Bool { key = value; return true }
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
