import XCTest
@testable import MacTorn

/// The two v2 additions: the free notification counters, and virus programming.
///
/// Both wire shapes are pinned to Torn's OpenAPI document (`UserNotificationsResponse`,
/// `UserVirusResponse`, spec 6.13.1) rather than to whatever the app happens to accept.
final class UserV2AdditionsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Notification counters

    func testDecodesTheSpecShape() throws {
        let counts = try decode(TornNotifications.self,
                                ["messages": 3, "events": 12, "awards": 1, "competition": 0])
        XCTAssertEqual(counts.messages, 3)
        XCTAssertEqual(counts.events, 12)
        XCTAssertEqual(counts.awards, 1)
        XCTAssertEqual(counts.competition, 0)
        XCTAssertEqual(counts.total, 16)
        XCTAssertTrue(counts.hasAny)
    }

    func testAllZeroCountsMeanNothingIsWaiting() {
        XCTAssertFalse(TornNotifications().hasAny)
        XCTAssertEqual(TornNotifications().total, 0)
    }

    /// Every field is `required` in the spec, so a payload missing one is a shape change
    /// worth failing on rather than quietly reading as zero.
    func testMissingFieldIsRejectedRatherThanDefaulted() {
        XCTAssertThrowsError(try decode(TornNotifications.self,
                                        ["messages": 1, "events": 2, "awards": 3]))
    }

    // MARK: - Virus programming

    private let virusJSON: [String: Any] = [
        "item": ["id": 226, "name": "Nock Virus"],
        "until": 1_700_086_400,
    ]

    func testDecodesTheNestedItemShape() throws {
        let virus = try decode(VirusProgramming.self, virusJSON)
        XCTAssertEqual(virus.itemID, 226)
        XCTAssertEqual(virus.name, "Nock Virus")
        XCTAssertEqual(virus.until, 1_700_086_400)
    }

    func testRoundTripsThroughItsOwnEncoder() throws {
        let original = try decode(VirusProgramming.self, virusJSON)
        let reencoded = try JSONDecoder().decode(VirusProgramming.self,
                                                 from: JSONEncoder().encode(original))
        XCTAssertEqual(original, reencoded)
    }

    func testCountdownIsMeasuredOnTheServerClock() throws {
        let virus = try decode(VirusProgramming.self, virusJSON)
        let serverNow = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(virus.secondsRemaining(at: serverNow), 86_400)
        XCTAssertFalse(virus.isReady(at: serverNow))
    }

    /// A countdown must never run backwards past zero — the same rule every other timer in
    /// the app follows (issue #46).
    func testAFinishedVirusReadsAsZeroNotNegative() throws {
        let virus = try decode(VirusProgramming.self, virusJSON)
        let wellPast = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(virus.secondsRemaining(at: wellPast), 0)
        XCTAssertTrue(virus.isReady(at: wellPast))
    }

    func testReadyExactlyOnTheBoundary() throws {
        let virus = try decode(VirusProgramming.self, virusJSON)
        let exactly = Date(timeIntervalSince1970: TimeInterval(virus.until))
        XCTAssertTrue(virus.isReady(at: exactly))
        XCTAssertEqual(virus.secondsRemaining(at: exactly), 0)
    }

    // MARK: - Timeline integration

    func testVirusAppearsOnTheNextActionTimelineUntilItFinishes() {
        var snapshot = NextActionSnapshot(now: 1_000)
        snapshot.virusFinishesAt = 1_600
        let events = NextActionEngine().events(from: snapshot)

        let virus = events.first { $0.category == .virus }
        XCTAssertNotNil(virus)
        XCTAssertEqual(virus?.eta, 600)
        XCTAssertFalse(virus?.isReady ?? true)
    }

    func testAFinishedVirusLeavesTheTimeline() {
        var snapshot = NextActionSnapshot(now: 2_000)
        snapshot.virusFinishesAt = 1_600
        XCTAssertNil(NextActionEngine().events(from: snapshot).first { $0.category == .virus },
                     "a past event is not an upcoming one")
    }

    func testVirusCanBeHiddenLikeAnyOtherCategory() {
        var snapshot = NextActionSnapshot(now: 1_000)
        snapshot.virusFinishesAt = 1_600
        let events = NextActionEngine().events(from: snapshot, hidden: [.virus])
        XCTAssertTrue(events.isEmpty)
    }

    func testTimelineOrdersVirusPurelyByWhenItFires() {
        var snapshot = NextActionSnapshot(now: 1_000)
        snapshot.virusFinishesAt = 1_100
        snapshot.energyFullAt = 1_500
        let categories = NextActionEngine().events(from: snapshot).map(\.category)
        XCTAssertEqual(categories, [.virus, .energy])
    }
}
