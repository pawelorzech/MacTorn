import XCTest
@testable import MacTorn

/// How MacTorn identifies itself to Torn and where it puts the key.
///
/// Both behaviours here are things Torn's own OpenAPI document asks clients to do, and
/// both are invisible in normal use — which is exactly why they need tests. A dropped
/// `comment` is only noticed by a user squinting at their key log; a key that stays in the
/// query string is only noticed after it has been logged somewhere it should not be.
final class TornAPIClientTests: XCTestCase {

    private let key = "exampleKey123456"

    private func queryItems(_ url: URL) -> [String: String] {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    // MARK: - Tool identification

    func testEveryRegisteredEndpointIdentifiesItselfInTheKeyLog() throws {
        for endpoint in TornEndpointRegistry.all {
            let url = try XCTUnwrap(endpoint.url(key: key, parameter: 1), endpoint.id)
            XCTAssertEqual(queryItems(url)["comment"], TornAPIClient.comment,
                           "\(endpoint.id) must be attributable in the owner's key log")
        }
    }

    // MARK: - Key placement

    func testV2RequestsCarryTheKeyInTheHeaderAndNotTheURL() throws {
        let v2 = TornEndpointRegistry.all.filter { $0.version == .v2 }
        XCTAssertFalse(v2.isEmpty)
        for endpoint in v2 {
            let url = try XCTUnwrap(endpoint.url(key: key, parameter: 1), endpoint.id)
            let request = TornAPIClient.request(for: url)

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "ApiKey \(key)", endpoint.id)
            let sent = try XCTUnwrap(request.url, endpoint.id)
            XCTAssertNil(queryItems(sent)["key"], "\(endpoint.id) leaves the key in the URL")
            XCTAssertFalse(sent.absoluteString.contains(key), "\(endpoint.id) leaks the key")
        }
    }

    func testV1RequestsKeepTheQueryKeyBecauseHeaderAuthIsUndocumentedThere() throws {
        let v1 = TornEndpointRegistry.all.filter { $0.version == .v1 }
        XCTAssertFalse(v1.isEmpty)
        for endpoint in v1 {
            let url = try XCTUnwrap(endpoint.url(key: key, parameter: 1), endpoint.id)
            let request = TornAPIClient.request(for: url)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), endpoint.id)
            XCTAssertEqual(queryItems(try XCTUnwrap(request.url))["key"], key, endpoint.id)
        }
    }

    func testOtherQueryParametersSurviveTheKeyMove() throws {
        let news = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "faction.news"))
        let request = TornAPIClient.request(for: try XCTUnwrap(news.url(key: key)))
        let items = queryItems(try XCTUnwrap(request.url))
        XCTAssertEqual(items["cat"], "main")
        XCTAssertEqual(items["limit"], String(news.recordLimit ?? -1))
        XCTAssertEqual(items["comment"], TornAPIClient.comment)
    }

    // MARK: - Caching

    func testEveryRequestBypassesTheURLCache() throws {
        for endpoint in TornEndpointRegistry.all {
            let url = try XCTUnwrap(endpoint.url(key: key, parameter: 1), endpoint.id)
            XCTAssertEqual(TornAPIClient.request(for: url).cachePolicy,
                           .reloadIgnoringLocalAndRemoteCacheData,
                           "\(endpoint.id) must not stack a client cache on Torn's own")
        }
    }

    // MARK: - Selection narrowing

    func testNarrowingAsksOnlyForWhatTheKeyCanRead() throws {
        let fastPoll = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.fast"))
        let url = try XCTUnwrap(fastPoll.url(key: key, granted: ["bars", "cooldowns", "travel"]))
        let selections = try XCTUnwrap(queryItems(url)["selections"]).split(separator: ",").map(String.init)

        XCTAssertEqual(Set(selections), ["bars", "cooldowns", "travel"])
        XCTAssertFalse(selections.contains("battlestats"),
                       "one forbidden selection would fail the whole request with error 16")
    }

    func testNarrowingPreservesTheRegistrysOrder() throws {
        let fastPoll = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.fast"))
        let url = try XCTUnwrap(fastPoll.url(key: key, granted: Set(fastPoll.selections)))
        XCTAssertEqual(queryItems(url)["selections"], fastPoll.selections.joined(separator: ","))
    }

    func testNoGrantedSetMeansAskForEverything() throws {
        let fastPoll = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "user.fast"))
        let url = try XCTUnwrap(fastPoll.url(key: key, granted: nil))
        XCTAssertEqual(queryItems(url)["selections"], fastPoll.selections.joined(separator: ","))
    }

    func testNothingGrantedMeansNoRequestAtAll() {
        let fastPoll = TornEndpointRegistry.endpoint(id: "user.fast")!
        XCTAssertNil(fastPoll.url(key: key, granted: []),
                     "an empty selections list would be a malformed request, not an empty one")
    }

    func testEndpointsWithoutSelectionsAreUnaffectedByNarrowing() throws {
        let keyInfo = try XCTUnwrap(TornEndpointRegistry.endpoint(id: "key.info"))
        XCTAssertTrue(keyInfo.selections.isEmpty)
        XCTAssertNotNil(keyInfo.url(key: key, granted: []),
                        "narrowing must not disable an endpoint that never asked for selections")
    }

    // MARK: - Redaction

    func testRedactedURLNeverCarriesAValue() throws {
        for endpoint in TornEndpointRegistry.all {
            let url = try XCTUnwrap(endpoint.url(key: key, parameter: 1), endpoint.id)
            XCTAssertFalse(tornRedactedURL(url).contains(key), endpoint.id)
        }
    }
}
