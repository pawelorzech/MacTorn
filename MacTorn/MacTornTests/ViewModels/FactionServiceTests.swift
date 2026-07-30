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

        let result = try await service.loadBasic(from: endpoint("faction"))

        XCTAssertNil(service.basic, "Transport must not bypass facade publication policy")
        guard case .success(let payload, let bytes) = result else {
            return XCTFail("Expected decoded faction.basic payload")
        }
        XCTAssertEqual(payload.name, "The Masters")
        XCTAssertEqual(payload.factionId, 11_559)
        XCTAssertEqual(payload.respect, 12_345)
        XCTAssertEqual(payload.chain.current, 42)
        XCTAssertEqual(bytes, mock.mockData?.count)

        service.publishBasic(payload)
        XCTAssertEqual(service.basic?.factionId, 11_559)
    }

    func testLoadsAndPublishesRankedWarsOnlyAfterFacadeDecision() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())

        let result = try await service.loadWars(from: endpoint("rankedwars"))

        XCTAssertTrue(service.wars.isEmpty)
        guard case .success(let payload, _) = result else {
            return XCTFail("Expected decoded faction.wars payload")
        }
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.first?.id, 44_751)

        service.publishWars(payload)
        XCTAssertEqual(service.wars.count, 2)
    }

    func testLoadsAndPublishesNewsOnlyAfterFacadeDecision() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: TornAPIFixtures.factionNewsResponse)

        let result = try await service.loadNews(from: endpoint("news"))

        XCTAssertTrue(service.news.isEmpty)
        guard case .success(let payload, _) = result else {
            return XCTFail("Expected decoded faction.news payload")
        }
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.first?.id, "zL8X")

        service.publishNews(payload)
        XCTAssertEqual(service.news.count, 2)
    }

    func testBasicReportsAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIError(code: 2, message: "Incorrect key")

        let result = try await service.loadBasic(from: endpoint("faction"))

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.basic API error")
        }
        XCTAssertTrue(error.haltsAllRequests)
        XCTAssertNil(service.basic)
    }

    func testWarsReportsAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIErrorV2(code: 16, message: "Access level too low")

        let result = try await service.loadWars(from: endpoint("rankedwars"))

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.wars API error")
        }
        XCTAssertTrue(error.haltsAllRequests)
        XCTAssertTrue(service.wars.isEmpty)
    }

    func testNewsReportsCategoryAPIErrorWithoutPublishing() async throws {
        let (service, mock) = makeService()
        try mock.setTornAPIErrorV2(code: 14, message: "Daily read limit reached")

        let result = try await service.loadNews(from: endpoint("news"))

        guard case .apiError(let error, _) = result else {
            return XCTFail("Expected faction.news API error")
        }
        XCTAssertTrue(error.haltsCategoryOnly)
        XCTAssertTrue(service.news.isEmpty)
    }

    func testBasicRejectsMissingRequiredFieldsAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["name": "Looks plausible"])

        let result = try await service.loadBasic(from: endpoint("faction"))

        guard case .malformed(let bytes) = result else {
            return XCTFail("Expected malformed faction.basic response")
        }
        XCTAssertEqual(bytes, mock.mockData?.count)
    }

    func testWarsRejectsMalformedElementAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["rankedwars": [["id": "not-an-int"]]])

        let result = try await service.loadWars(from: endpoint("rankedwars"))

        guard case .malformed = result else {
            return XCTFail("Expected malformed faction.wars response")
        }
    }

    func testNewsRejectsMissingArrayAsMalformed() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: ["news": "not-an-array"])

        let result = try await service.loadNews(from: endpoint("news"))

        guard case .malformed = result else {
            return XCTFail("Expected malformed faction.news response")
        }
    }

    func testResetClearsAllOwnedFactionState() async throws {
        let (service, mock) = makeService()
        try mock.setSuccessResponse(json: basicJSON)
        if case .success(let basic, _) = try await service.loadBasic(from: endpoint("faction")) {
            service.publishBasic(basic)
        }
        try mock.setSuccessResponse(json: TornAPIFixtures.rankedWarsResponse())
        if case .success(let wars, _) = try await service.loadWars(from: endpoint("rankedwars")) {
            service.publishWars(wars)
        }
        try mock.setSuccessResponse(json: TornAPIFixtures.factionNewsResponse)
        if case .success(let news, _) = try await service.loadNews(from: endpoint("news")) {
            service.publishNews(news)
        }

        service.reset()

        XCTAssertNil(service.basic)
        XCTAssertTrue(service.wars.isEmpty)
        XCTAssertTrue(service.news.isEmpty)
    }

    func testAppStateFacadePublishesServiceStateAndResetsItOnAccountChange() {
        let service = FactionService(session: MockNetworkSession())
        let state = AppState(
            session: MockNetworkSession(),
            connectivity: ControllableConnectivity(),
            defaults: .createMockDefaults(),
            factionService: service
        )
        state.apiKey = "account-a"
        service.publishBasic(
            FactionData(
                name: "Faction A",
                factionId: 1,
                respect: 2,
                chain: FactionChain(current: 3, max: 4, timeout: 5, cooldown: 0)
            )
        )
        service.publishWars([])
        service.publishNews([])

        XCTAssertEqual(state.factionData?.name, "Faction A")
        XCTAssertEqual(state.rankedWars.count, service.wars.count)
        XCTAssertEqual(state.factionNews.count, service.news.count)

        state.apiKey = "account-b"

        XCTAssertNil(state.factionData)
        XCTAssertTrue(state.rankedWars.isEmpty)
        XCTAssertTrue(state.factionNews.isEmpty)
    }

    private func makeService() -> (FactionService, MockNetworkSession) {
        let mock = MockNetworkSession()
        return (FactionService(session: mock), mock)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: "https://api.torn.com/\(path)")!
    }
}
