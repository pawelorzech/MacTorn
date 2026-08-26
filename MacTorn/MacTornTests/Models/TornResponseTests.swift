import XCTest
@testable import MacTorn

final class TornResponseTests: XCTestCase {

    // MARK: - Full Decoding Tests

    func testDecoding_validFullResponse() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.name, "TestPlayer")
        XCTAssertEqual(response.playerId, 123456)
        XCTAssertNotNil(response.energy)
        XCTAssertNotNil(response.nerve)
        XCTAssertNotNil(response.life)
        XCTAssertNotNil(response.happy)
        XCTAssertNotNil(response.cooldowns)
        XCTAssertNotNil(response.travel)
        XCTAssertNotNil(response.status)
        XCTAssertNotNil(response.chain)
        XCTAssertNotNil(response.events)
        XCTAssertNotNil(response.messages)
        XCTAssertNil(response.error)
    }

    // MARK: - Bars Computed Property Tests

    func testBars_allBarsPresent() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.validFullResponse())
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        let bars = response.bars
        XCTAssertNotNil(bars)
        XCTAssertEqual(bars?.energy.current, 100)
        XCTAssertEqual(bars?.nerve.current, 50)
        XCTAssertEqual(bars?.life.current, 7500)
        XCTAssertEqual(bars?.happy.current, 5000)
    }

    func testBars_missingBar() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "player_id": 123456,
            "energy": TornAPIFixtures.energyFull,
            "nerve": TornAPIFixtures.energyHalf
            // Missing life and happy
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertNil(response.bars) // Should be nil because not all bars present
    }

    // MARK: - Unread Messages Count Tests

    func testUnreadMessagesCount_noMessages() throws {
        let json: [String: Any] = [
            "name": "TestPlayer"
            // No messages
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 0)
    }

    func testUnreadMessagesCount_allRead() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "messages": [
                "1": ["name": "Sender1", "read": 1],
                "2": ["name": "Sender2", "read": 1]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 0)
    }

    func testUnreadMessagesCount_someUnread() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "messages": [
                "1": ["name": "Sender1", "read": 0],
                "2": ["name": "Sender2", "read": 1],
                "3": ["name": "Sender3", "read": 0]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertEqual(response.unreadMessagesCount, 2)
    }

    // MARK: - Recent Events Tests

    func testRecentEvents_noEvents() throws {
        let json: [String: Any] = [
            "name": "TestPlayer"
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertTrue(response.recentEvents.isEmpty)
    }

    func testRecentEvents_sortedByTimestamp() throws {
        let json: [String: Any] = [
            "name": "TestPlayer",
            "events": [
                "1": ["timestamp": 1000, "event": "Old event", "seen": 1],
                "2": ["timestamp": 3000, "event": "Newest event", "seen": 0],
                "3": ["timestamp": 2000, "event": "Middle event", "seen": 0]
            ]
        ]
        let data = try TornAPIFixtures.toData(json)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        let events = response.recentEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].timestamp, 3000) // Newest first
        XCTAssertEqual(events[1].timestamp, 2000)
        XCTAssertEqual(events[2].timestamp, 1000) // Oldest last
    }

    func testRecentEvents_sameTimestampRetainDistinctStableIds() throws {
        let json: [String: Any] = [
            "events": [
                "event-a": ["timestamp": 3000, "event": "First", "seen": 0],
                "event-b": ["timestamp": 3000, "event": "Second", "seen": 0]
            ]
        ]
        let response = try JSONDecoder().decode(
            TornResponse.self,
            from: TornAPIFixtures.toData(json)
        )

        let ids = response.recentEvents.map(\.id)
        XCTAssertEqual(Set(ids), Set(["event-a", "event-b"]))
    }

    // MARK: - Error Response Tests

    func testDecoding_errorResponse() throws {
        let data = try TornAPIFixtures.toData(TornAPIFixtures.tornErrorInvalidKey)
        let response = try JSONDecoder().decode(TornResponse.self, from: data)

        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, 2)
        XCTAssertEqual(response.error?.error, "Incorrect Key")
    }

    // MARK: - TornEvent Tests

    func testTornEvent_cleanEvent() throws {
        let json: [String: Any] = [
            "timestamp": 1700000000,
            "event": "You received a message from <a href='profile.php?XID=12345'>SomePlayer</a>.",
            "seen": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try JSONDecoder().decode(TornEvent.self, from: data)

        XCTAssertEqual(event.cleanEvent, "You received a message from SomePlayer.")
    }

    func testTornEvent_date() throws {
        let json: [String: Any] = [
            "timestamp": 1700000000,
            "event": "Test event",
            "seen": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try JSONDecoder().decode(TornEvent.self, from: data)

        XCTAssertEqual(event.date, Date(timeIntervalSince1970: 1700000000))
    }

    // MARK: - TornMessage Tests

    func testTornMessage_decoding() throws {
        let json: [String: Any] = [
            "name": "TestSender",
            "type": "Private",
            "title": "Hello World",
            "timestamp": 1700000000,
            "read": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let message = try JSONDecoder().decode(TornMessage.self, from: data)

        XCTAssertEqual(message.name, "TestSender")
        XCTAssertEqual(message.type, "Private")
        XCTAssertEqual(message.title, "Hello World")
        XCTAssertEqual(message.timestamp, 1700000000)
        XCTAssertEqual(message.read, 0)
    }
}

// MARK: - URL Redactor (F-02)

final class TornRedactedURLTests: XCTestCase {
    /// Documents the exact bug F-02 fixes. The previous code logged
    /// `url.absoluteString.prefix(80)`; for a short Torn API key (16 chars)
    /// the entire key landed in os_log. The redactor must never emit values.
    func testRedactor_doesNotLeakAPIKey() {
        let secret = "AbCdEfGhIjKlMnOp"
        let url = URL(string: "https://api.torn.com/user/?selections=basic,bars&key=\(secret)")!
        let redacted = tornRedactedURL(url)
        XCTAssertFalse(redacted.contains(secret), "redactor leaked API key: \(redacted)")
    }

    func testRedactor_keepsHostAndPath() {
        // URL.path strips the trailing slash in Foundation, so the redacted form is
        // .../user (no trailing slash). What we actually care about is that host + path
        // survive intact and only values are dropped.
        let url = URL(string: "https://api.torn.com/user/?selections=basic&key=XYZ")!
        let out = tornRedactedURL(url)
        XCTAssertTrue(out.contains("api.torn.com"))
        XCTAssertTrue(out.contains("/user"))
        XCTAssertFalse(out.contains("XYZ"))
    }

    func testRedactor_listsQueryKeysSorted() {
        let url = URL(string: "https://api.torn.com/v2/market/123?selections=itemmarket&key=XYZ")!
        XCTAssertEqual(tornRedactedURL(url), "https://api.torn.com/v2/market/123?[key,selections]")
    }

    func testRedactor_handlesNoQueryString() {
        let url = URL(string: "https://api.torn.com/v2/market/123")!
        XCTAssertEqual(tornRedactedURL(url), "https://api.torn.com/v2/market/123")
    }

    func testRedactor_doesNotLeakKeyEvenWithSpecialChars() {
        let secret = "Ab&Cd=Ef Gh"
        let raw = "https://api.torn.com/user/?selections=basic&key=\(secret)"
        guard let url = URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw) else {
            return XCTFail("could not build URL")
        }
        XCTAssertFalse(tornRedactedURL(url).contains("Ef"))
    }
}

// MARK: - TornAPI URL Builder (F-06)

final class TornAPIURLBuilderTests: XCTestCase {
    /// Keys with `&`, `=`, or whitespace would have produced malformed URLs under
    /// the old string-interpolation builder. URLComponents must percent-encode them
    /// AND round-trip back to the original via queryItems.
    func testURL_percentEncodesKeyWithReservedChars() {
        let key = "ab&cd=ef gh"
        guard let url = TornAPI.url(for: key),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return XCTFail("URL builder returned nil")
        }
        let keyValue = comps.queryItems?.first(where: { $0.name == "key" })?.value
        XCTAssertEqual(keyValue, key, "key should round-trip exactly through percent-encoding")
    }

    func testURL_marketURLIncludesItemIdInPath() {
        guard let url = TornAPI.marketURL(itemId: 1234, apiKey: "abc") else {
            return XCTFail("nil URL")
        }
        XCTAssertEqual(url.path, "/v2/market/1234/itemmarket")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "selections" })
    }

    func testURL_forumThreadURLIncludesThreadIdInPath() {
        guard let url = TornAPI.forumThreadURL(threadId: 567, apiKey: "abc") else {
            return XCTFail("nil URL")
        }
        XCTAssertEqual(url.path, "/v2/forum/567/thread")
    }

    func testURL_keyIsAlwaysPresent() {
        let urls: [URL?] = [
            TornAPI.url(for: "k"),
            TornAPI.factionURL(for: "k"),
            TornAPI.marketURL(itemId: 1, apiKey: "k"),
            TornAPI.tornStocksURL(for: "k"),
            TornAPI.forumThreadURL(threadId: 1, apiKey: "k"),
            TornAPI.forumCategoryThreadsURL(categoryId: 1, apiKey: "k"),
        ]
        for url in urls {
            let comps = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let keyItem = comps?.queryItems?.first { $0.name == "key" }
            XCTAssertEqual(keyItem?.value, "k", "key missing in \(url?.absoluteString ?? "nil")")
        }
    }
}

// MARK: - Notification Sanitizer (F-08)

final class NotificationSanitizerTests: XCTestCase {
    func testSanitize_capsLength() {
        let input = String(repeating: "x", count: 500)
        let out = NotificationManager.sanitize(input, maxLength: 200)
        XCTAssertEqual(out.count, 200)
    }

    func testSanitize_stripsControlCharacters() {
        let input = "hello\u{0}\nworld\u{1}\u{7}!"
        let out = NotificationManager.sanitize(input, maxLength: 100)
        XCTAssertFalse(out.contains("\n"))
        XCTAssertFalse(out.contains("\u{0}"))
        XCTAssertFalse(out.contains("\u{1}"))
        XCTAssertEqual(out, "helloworld!")
    }

    func testSanitize_passesThroughNormalText() {
        let input = "Travel: Mexico"
        XCTAssertEqual(NotificationManager.sanitize(input, maxLength: 200), input)
    }
}

// MARK: - KeychainStore (F-01)

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Tests run against the `.tests` service so the prod entry is untouched.
        KeychainStore.delete()
    }

    override func tearDown() {
        KeychainStore.delete()
        super.tearDown()
    }

    func testKeychain_setAndGetRoundtrip() {
        KeychainStore.set("AbCdEfGh12345678")
        XCTAssertEqual(KeychainStore.get(), "AbCdEfGh12345678")
    }

    func testKeychain_setOverwrites() {
        KeychainStore.set("first")
        KeychainStore.set("second")
        XCTAssertEqual(KeychainStore.get(), "second")
    }

    func testKeychain_deleteClears() {
        KeychainStore.set("xyz")
        KeychainStore.delete()
        XCTAssertNil(KeychainStore.get())
    }

    func testKeychain_setEmptyDeletes() {
        KeychainStore.set("xyz")
        KeychainStore.set("")
        XCTAssertNil(KeychainStore.get())
    }

    /// Defense-in-depth: ensure tests don't accidentally use the production keychain
    /// service. If this asserts, an environment change broke isolation.
    func testKeychain_serviceIsTestIsolated() {
        XCTAssertTrue(KeychainStore.service.hasPrefix("com.mactorn.app.tests"),
                      "service should be test-isolated, got: \(KeychainStore.service)")
        XCTAssertNotEqual(KeychainStore.service, "com.mactorn.app")
    }
}

// MARK: - Torn API Error Envelope Contract

/// Contract tests for `tornAPIErrorMessage(in:)` against the two error envelopes
/// documented by Torn: the legacy v1 nested form and the v2 top-level form (per the
/// official OpenAPI spec at https://api.torn.com/v2). Mocks mirror the documented
/// schema exactly — `code` (int) + `error` (string), siblings in v2, nested in v1.
final class TornAPIErrorEnvelopeTests: XCTestCase {

    func testV2Envelope_topLevelCodeAndErrorString() {
        // Per spec ErrorTooManyRequests: {"code":5,"error":"Too many requests"}
        let json: [String: Any] = ["code": 5, "error": "Too many requests"]
        XCTAssertEqual(tornAPIErrorMessage(in: json), "Too many requests")
    }

    func testV2Envelope_incorrectKey() {
        let json: [String: Any] = ["code": 2, "error": "Incorrect key"]
        XCTAssertEqual(tornAPIErrorMessage(in: json), "Incorrect key")
    }

    func testV1Envelope_nestedErrorObject() {
        // Legacy v1: {"error":{"code":2,"error":"Incorrect Key"}}
        let json: [String: Any] = ["error": ["code": 2, "error": "Incorrect Key"]]
        XCTAssertEqual(tornAPIErrorMessage(in: json), "Incorrect Key")
    }

    func testSuccessPayload_v2Market_returnsNil() {
        // A real /v2/market/{id} success has no error envelope.
        let json: [String: Any] = ["itemmarket": ["listings": [["price": 1000, "amount": 5]]]]
        XCTAssertNil(tornAPIErrorMessage(in: json))
    }

    func testSuccessPayload_v2Forum_returnsNil() {
        let json: [String: Any] = ["thread": ["title": "Topic", "posts": 42]]
        XCTAssertNil(tornAPIErrorMessage(in: json))
    }

    func testEmptyObject_returnsNil() {
        XCTAssertNil(tornAPIErrorMessage(in: [:]))
    }

    /// A bare top-level `error` string without a sibling `code` is NOT treated as the
    /// v2 envelope — guards against false positives from unrelated `error` fields.
    func testTopLevelErrorStringWithoutCode_returnsNil() {
        let json: [String: Any] = ["error": "some unrelated field"]
        XCTAssertNil(tornAPIErrorMessage(in: json))
    }
}

// MARK: - Main user snapshot semantic contract

final class UserSnapshotContractTests: XCTestCase {
    private let requested = [
        "basic", "bars", "cooldowns", "travel", "profile", "money",
        "battlestats", "properties", "stocks",
    ]

    func testFullCapabilitiesAcceptARealSnapshot() {
        XCTAssertTrue(UserSnapshotContract.isSatisfied(
            by: TornAPIFixtures.validFullResponse(),
            requestedSelections: requested,
            grantedSelections: requested
        ))
    }

    func testCustomProfileCapabilityDoesNotArbitrarilyRequireBars() {
        let profileOnly: [String: Any] = [
            "name": "CustomKeyPlayer",
            "player_id": 42,
        ]

        XCTAssertTrue(UserSnapshotContract.isSatisfied(
            by: profileOnly,
            requestedSelections: requested,
            grantedSelections: ["profile"]
        ))
    }

    func testUnderprivilegedKeyWithoutRequestedCapabilitiesRejectsPayload() {
        XCTAssertFalse(UserSnapshotContract.isSatisfied(
            by: ["name": "Unexpected"],
            requestedSelections: requested,
            grantedSelections: []
        ))
    }

    func testEmptyObjectIsNeverASuccessfulSnapshot() {
        XCTAssertFalse(UserSnapshotContract.isSatisfied(
            by: [:],
            requestedSelections: requested,
            grantedSelections: nil
        ))
    }
}
