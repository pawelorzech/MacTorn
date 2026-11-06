import XCTest
@testable import MacTorn

@MainActor
final class FactionServiceTests: XCTestCase {
    private let basicJSON: [String: Any] = [
        "name": "The Masters",
        "ID": 11_559,
        "respect": 12_345,
        "chain": [
            "current": 42,
            "max": 100,
            "timeout": 250,
            "cooldown": 0,
        ],
    ]

    func testLoadsAndPublishesBasicFactionOnlyAfterFacadeDecision() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: basicJSON)

        let result = try await TornAPIClient.loadJSON(from: endpoint("faction"), session: mock, decode: FactionStore.decodeBasic)

        XCTAssertNil(service.basic, "Transport must not bypass facade publication policy")
        guard case .success(let payload, let bytes) = result else {
            return XCTFail("Expected decoded faction.basic payload")
        }
        XCTAssertEqual(payload.name, "The Masters")
        XCTAssertEqual(payload.factionId, 11_559)
        XCTAssertEqual(payload.respect, 12_345)
        XCTAssertEqual(payload.chain.current, 42)
        XCTAssertEqual(bytes, mock.mockData?.count)

        service.basic = payload
        XCTAssertEqual(service.basic?.factionId, 11_559)
    }

    func testLoadsAndPublishesRankedWarsOnlyAfterFacadeDecision() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())

        let result = try await TornAPIClient.loadJSON(from: endpoint("rankedwars"), session: mock, decode: FactionStore.decodeWars)

        XCTAssertTrue(service.wars.isEmpty)
        guard case .success(let payload, _) = result else {
            return XCTFail("Expected decoded faction.wars payload")
        }
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.first?.id, 44_751)

        service.wars = payload
        XCTAssertEqual(service.wars.count, 2)
    }

    func testLoadsAndPublishesNewsOnlyAfterFacadeDecision() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: TornAPIFixtures.factionNewsResponse)

        let result = try await TornAPIClient.loadJSON(from: endpoint("news"), session: mock, decode: FactionStore.decodeNews)

        XCTAssertTrue(service.news.isEmpty)
        guard case .success(let payload, _) = result else {
            return XCTFail("Expected decoded faction.news payload")
        }
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.first?.id, "zL8X")

        service.news = payload
        XCTAssertEqual(service.news.count, 2)
    }

    func testBasicReportsAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIError(code: 2, message: "Incorrect key")

        let result = try await TornAPIClient.loadJSON(from: endpoint("faction"), session: mock, decode: FactionStore.decodeBasic)

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.basic API error")
        }
        XCTAssertEqual(error.classification, .permanentKey)
        XCTAssertNil(service.basic)
    }

    func testWarsReportsAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIErrorV2(code: 16, message: "Access level too low")

        let result = try await TornAPIClient.loadJSON(from: endpoint("rankedwars"), session: mock, decode: FactionStore.decodeWars)

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.wars API error")
        }
        XCTAssertEqual(error.classification, .insufficientPermissions, "code 16 refreshes capabilities; it does not invalidate the key")
        XCTAssertTrue(service.wars.isEmpty)
    }

    func testNewsReportsCategoryAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIErrorV2(code: 14, message: "Daily read limit reached")

        let result = try await TornAPIClient.loadJSON(from: endpoint("news"), session: mock, decode: FactionStore.decodeNews)

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.news API error")
        }
        XCTAssertEqual(error.classification, .dailyRowLimit)
        XCTAssertTrue(service.news.isEmpty)
    }

    func testBasicRejectsMissingRequiredFieldsAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["name": "Looks plausible"])

        let result = try await TornAPIClient.loadJSON(from: endpoint("faction"), session: mock, decode: FactionStore.decodeBasic)

        guard case .malformed(let bytes) = result else {
            return XCTFail("Expected malformed faction.basic response")
        }
        XCTAssertEqual(bytes, mock.mockData?.count)
    }

    func testWarsRejectsMalformedElementAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["rankedwars": [["id": "not-an-int"]]])

        let result = try await TornAPIClient.loadJSON(from: endpoint("rankedwars"), session: mock, decode: FactionStore.decodeWars)

        guard case .malformed = result else {
            return XCTFail("Expected malformed faction.wars response")
        }
    }

    func testNewsRejectsMissingArrayAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["news": "not-an-array"])

        let result = try await TornAPIClient.loadJSON(from: endpoint("news"), session: mock, decode: FactionStore.decodeNews)

        guard case .malformed = result else {
            return XCTFail("Expected malformed faction.news response")
        }
    }

    func testResetClearsAllOwnedFactionState() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: basicJSON)
        if case .success(let basic, _) = try await TornAPIClient.loadJSON(from: endpoint("faction"), session: mock, decode: FactionStore.decodeBasic) {
            service.basic = basic
        }
        try mock.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())
        if case .success(let wars, _) = try await TornAPIClient.loadJSON(from: endpoint("rankedwars"), session: mock, decode: FactionStore.decodeWars) {
            service.wars = wars
        }
        try mock.setSuccessResponse(json: TornAPIFixtures.factionNewsResponse)
        if case .success(let news, _) = try await TornAPIClient.loadJSON(from: endpoint("news"), session: mock, decode: FactionStore.decodeNews) {
            service.news = news
        }

        service.reset()

        XCTAssertNil(service.basic)
        XCTAssertTrue(service.wars.isEmpty)
        XCTAssertTrue(service.news.isEmpty)
    }

    func testAppStateFacadePublishesServiceStateAndResetsItOnAccountChange() {
        let state = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(),
            defaults: .createMockDefaults()
        )
        let service = state.faction
        state.apiKey = "account-a"
        service.basic = (
            FactionData(
                name: "Faction A",
                factionId: 1,
                respect: 2,
                chain: FactionChain(current: 3, max: 4, timeout: 5, cooldown: 0)
            )
        )
        service.wars = []
        service.news = []

        XCTAssertEqual(state.factionData?.name, "Faction A")
        XCTAssertEqual(state.rankedWars.count, service.wars.count)
        XCTAssertEqual(state.factionNews.count, service.news.count)

        state.apiKey = "account-b"

        XCTAssertNil(state.factionData)
        XCTAssertTrue(state.rankedWars.isEmpty)
        XCTAssertTrue(state.factionNews.isEmpty)
    }

    private func makeService() -> (FactionStore, MockNetworkSession) {
        (FactionStore(), MockNetworkSession())
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: "https://api.torn.com/\(path)")!
    }
}
