import XCTest
@testable import MacTorn

/// Issue #46 — every countdown, not just cooldowns, must be computed against Torn's
/// clock.
///
/// Torn stamps each response with `server_time`. Only `CooldownEnds` ever used it
/// (`AppState+PollingUserFetch.swift`, `anchorTimestamp`); travel, hospital, jail,
/// chain and OC all measured against a bare `Date()`. On a Mac whose clock is 90 s
/// behind Torn's, that put two contradictory clocks in one window: the cooldown pill
/// was right while the menu bar claimed the plane was still 90 s from landing.
///
/// The contract pinned here is behavioural, deliberately — it names no new type and
/// no new property, so the implementation is free to store an offset on `AppState`
/// or to thread a `TimeSource` down into the models, as long as:
///
/// 1. the offset is taken from the snapshot's `server_time` (`anchorTimestamp`),
/// 2. every countdown is measured from `serverNow = AppState.time.now + offset`,
/// 3. an absent or implausible `server_time` collapses the offset to zero rather
///    than throwing the countdowns the other way,
/// 4. the offset is re-derived per snapshot and never accumulates.
///
/// Everything reads through the injected `MutableTimeSource`, so once the countdowns
/// stop calling `Date()` these numbers are exact rather than approximate. Chain comes
/// from the FACTION endpoint (`AppState.liveChain`) — `TornResponse.chain` is never
/// populated by the real API.
@MainActor
final class ServerClockOffsetTests: XCTestCase {

    /// Torn's clock runs this many seconds ahead of the Mac's in most of these tests.
    /// Matches the issue's worked example (a Mac 90 s slow).
    private let skew = 90

    private var clock: MutableTimeSource!
    private var session: MockNetworkSession!
    private var app: AppState!
    /// Whole-second local "now" — the frozen value the injected clock reports.
    private var localNow: Int!

    override func setUp() async throws {
        try await super.setUp()
        localNow = Int(Date().timeIntervalSince1970)
        clock = MutableTimeSource(Date(timeIntervalSince1970: TimeInterval(localNow)))
        session = MockNetworkSession()
        app = AppState(session: session,
                       connectivity: ControllableConnectivity(connected: true),
                       defaults: .createMockDefaults(),
                       time: clock)
    }

    override func tearDown() async throws {
        app.stopPolling()
        app.liveTimerCancellable?.cancel()
        app.liveTimerCancellable = nil
        app = nil
        session = nil
        clock = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Drives one full poll through the mock network.
    ///
    /// - Parameter serverTime: value for the response's top-level `server_time`.
    ///   `nil` removes the field entirely (the "API told us nothing" case).
    private func poll(serverTime: Int?,
                      travel: [String: Any]? = nil,
                      status: [String: Any]? = nil,
                      cooldowns: [String: Any]? = nil) async throws {
        var json = TornAPIFixtures.validFullResponse()
        if let serverTime {
            json["server_time"] = serverTime
        } else {
            json.removeValue(forKey: "server_time")
        }
        if let travel { json["travel"] = travel }
        if let status { json["status"] = status }
        if let cooldowns { json["cooldowns"] = cooldowns }

        app.apiKey = "valid_key"
        try session.setSuccessResponse(json: json)
        app.fetchData()
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    /// ETA of one Next Action category, measured from the injected clock.
    private func eta(_ category: NextActionCategory,
                     file: StaticString = #filePath,
                     line: UInt = #line) throws -> Int {
        let events = app.nextEvents(now: clock.now)
        let event = try XCTUnwrap(
            events.first { $0.category == category },
            "expected a \(category.rawValue) event, got \(events.map(\.category.rawValue))",
            file: file, line: line
        )
        return event.eta
    }

    /// Absolute fire time of one Next Action category.
    private func fireAt(_ category: NextActionCategory,
                        file: StaticString = #filePath,
                        line: UInt = #line) throws -> Int {
        let events = app.nextEvents(now: clock.now)
        let event = try XCTUnwrap(
            events.first { $0.category == category },
            "expected a \(category.rawValue) event, got \(events.map(\.category.rawValue))",
            file: file, line: line
        )
        return event.fireAt
    }

    private func travelSlice(arrivingAt arrival: Int, departedAt departed: Int, timeLeft: Int) -> [String: Any] {
        ["destination": "Mexico", "timestamp": arrival, "departed": departed, "time_left": timeLeft]
    }

    private func hospitalSlice(until: Int) -> [String: Any] {
        ["description": "In hospital", "details": "", "state": "Hospital", "until": until]
    }

    private func jailSlice(until: Int) -> [String: Any] {
        ["description": "In jail", "details": "", "state": "Jail", "until": until]
    }

    // MARK: - Capture + travel

    /// The offset comes from `server_time`, and the travel countdown — the app's only
    /// always-visible surface — is measured from it. Torn says the plane lands 300 s
    /// from *its* now; the Mac is 90 s behind, so a local-clock reading gives 390.
    func testTravelCountdownIsAnchoredToServerTimeNotTheMacClock() async throws {
        let serverNow = localNow + skew
        let arrival = serverNow + 300
        try await poll(serverTime: serverNow,
                       travel: travelSlice(arrivingAt: arrival,
                                           departedAt: serverNow - 300,
                                           timeLeft: 300))

        XCTAssertEqual(app.travelSecondsRemaining, 300,
                       "travel must count down from server_time; the Mac's 90 s lag must not inflate it")
        XCTAssertEqual(app.menuBarDisplay, .traveling(destination: "Mexico", seconds: 300),
                       "the menu bar is the surface the issue reports as wrong")
        XCTAssertEqual(try eta(.travel), 300,
                       "the Next Action timeline must agree with the menu bar")
    }

    /// Same skew, but the response carries only a relative `time_left` (no absolute
    /// arrival timestamp). `time_left` is measured from the instant the *server*
    /// generated the response, so it must be anchored on `server_time` — not on
    /// `lastFetchTime`, which is the Mac's (skewed) reading of that same instant.
    func testTravelCountdownFromRelativeTimeLeftIsAnchoredToServerTime() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow,
                       travel: travelSlice(arrivingAt: 0,
                                           departedAt: serverNow - 300,
                                           timeLeft: 300))

        XCTAssertEqual(try fireAt(.travel), serverNow + 300,
                       "time_left must be turned into an absolute time by adding it to "
                       + "server_time; adding it to lastFetchTime lands 90 s early")
        XCTAssertEqual(try eta(.travel), 300)
        XCTAssertEqual(app.travelSecondsRemaining, 300,
                       "an off-by-a-second miss here means the countdown still reads Date() "
                       + "instead of the injected AppState.time")
    }

    // MARK: - Hospital / jail

    func testHospitalCountdownIsAnchoredToServerTime() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow, status: hospitalSlice(until: serverNow + 300))

        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 300),
                       "hospital release is an absolute server timestamp — compare it against server now")
        XCTAssertEqual(try eta(.hospital), 300,
                       "the Next Action timeline must agree with the menu bar")
    }

    func testJailCountdownIsAnchoredToServerTime() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow, status: jailSlice(until: serverNow + 450))

        XCTAssertEqual(app.menuBarDisplay, .jail(seconds: 450),
                       "jail release is an absolute server timestamp — compare it against server now")
        XCTAssertEqual(try eta(.jail), 450,
                       "the Next Action timeline must agree with the menu bar")
    }

    // MARK: - Chain (faction endpoint)

    /// Chain lives on the faction endpoint. `FactionChain.timeout` is an absolute
    /// server timestamp, so the same offset applies.
    func testChainTimeoutIsAnchoredToServerTime() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow)

        app.factionService.publishBasic(
            FactionData(name: "Test", factionId: 1, respect: 10,
                        chain: FactionChain(current: 25, max: 100,
                                            timeout: serverNow + 180, cooldown: 0))
        )

        XCTAssertEqual(try eta(.chain), 180,
                       "a 90 s slow Mac must not claim three extra minutes of chain")
    }

    // MARK: - Organized crime

    func testOrganizedCrimeReadyCountdownIsAnchoredToServerTime() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow)

        app.organizedCrime = OrganizedCrime2(id: 1, name: "Clinical Precision",
                                             status: "Planning",
                                             readyAt: serverNow + 240)

        XCTAssertEqual(try eta(.organizedCrime), 240,
                       "OC ready_at is an absolute server timestamp — compare it against server now")
    }

    // MARK: - One clock, not two

    /// The core symptom: cooldowns were already server-anchored while everything else
    /// was not, so one window showed two clocks 90 s apart. Two events that Torn says
    /// fire at the same instant must report the same ETA.
    func testCooldownAndHospitalCountdownsAgreeOnOneClock() async throws {
        let serverNow = localNow + skew
        try await poll(serverTime: serverNow,
                       status: hospitalSlice(until: serverNow + 300),
                       cooldowns: ["drug": 0, "booster": 0, "medical": 300])

        let medical = try eta(.medical)
        let hospital = try eta(.hospital)
        XCTAssertEqual(medical, 300)
        XCTAssertEqual(hospital, 300)
        XCTAssertEqual(medical, hospital,
                       "cooldown and hospital fire at the same server instant — one window, one clock")
    }

    // MARK: - Degrading safely

    /// No `server_time` in the payload (and no legacy `timestamp` either) → offset 0,
    /// i.e. exactly the old local-clock behaviour. A fix must not invent an offset out
    /// of nothing. (Red today only by the second that elapses between the fixture being
    /// built and the assertion — the countdown is reading `Date()` rather than the
    /// injected clock. Once it reads `AppState.time` the number is exact.)
    func testMissingServerTimeFallsBackToTheLocalClock() async throws {
        try await poll(serverTime: nil, status: hospitalSlice(until: localNow + 300))

        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 300),
                       "without an anchor the local clock is all we have — no offset, no shift")
        XCTAssertEqual(try eta(.hospital), 300)
    }

    /// A `server_time` a decade away is a corrupt payload, not clock skew: applying it
    /// would throw every countdown into the next geological era. The number must stay
    /// where the local clock puts it.
    func testImplausiblyDistantServerTimeIsIgnored() async throws {
        let tenYears = 10 * 365 * 86_400
        try await poll(serverTime: localNow + tenYears,
                       status: hospitalSlice(until: localNow + 300))

        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 300),
                       "an implausible anchor must be discarded, not applied")
        XCTAssertEqual(try eta(.hospital), 300)
    }

    /// A zero / missing-but-present anchor is the same class of nonsense.
    func testZeroServerTimeIsIgnored() async throws {
        try await poll(serverTime: 0, status: hospitalSlice(until: localNow + 300))

        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 300))
        XCTAssertEqual(try eta(.hospital), 300)
    }

    /// The plausibility guard must not be so tight that it rejects real skew. Ten
    /// minutes of drift is an entirely ordinary un-synced Mac and must be honoured.
    func testLargeButPlausibleSkewIsStillHonoured() async throws {
        let serverNow = localNow + 600
        try await poll(serverTime: serverNow, status: hospitalSlice(until: serverNow + 300))

        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 300),
                       "10 minutes of clock drift is skew, not corruption")
        XCTAssertEqual(try eta(.hospital), 300)
    }

    // MARK: - No drift

    /// The offset is re-derived from each snapshot, never added to the previous one.
    /// Both polls see the same 90 s skew, so an implementation that accumulates
    /// (`offset += anchor - localNow`) lands on 180 and reports 450 instead of 540.
    func testOffsetDoesNotAccumulateAcrossSuccessiveSnapshots() async throws {
        let release = localNow + skew + 600

        try await poll(serverTime: localNow + skew, status: hospitalSlice(until: release))
        XCTAssertEqual(try eta(.hospital), 600, "first snapshot: 600 s of hospital left")

        clock.advance(60)
        try await poll(serverTime: localNow + 60 + skew, status: hospitalSlice(until: release))

        XCTAssertEqual(try eta(.hospital), 540,
                       "a minute later, 540 s left — the offset is still 90, not 180")
        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 540))
    }

    /// Skew that shrinks between polls (the Mac's clock being corrected mid-session)
    /// must be picked up, not latched from the first snapshot.
    func testOffsetTracksAChangingSkew() async throws {
        let release = localNow + skew + 600

        try await poll(serverTime: localNow + skew, status: hospitalSlice(until: release))
        XCTAssertEqual(try eta(.hospital), 600)

        // 60 s of Torn time pass (server 90 → 150) while the Mac's clock is nudged
        // forward by 60 s on top of that (local 0 → 120). Skew is now 30, not 90.
        clock.advance(120)
        try await poll(serverTime: localNow + 150, status: hospitalSlice(until: release))

        XCTAssertEqual(try eta(.hospital), 540,
                       "offset must be re-derived as 30; latching the original 90 gives 480")
    }

    // MARK: - Regression guard: fetch-relative durations

    /// `Bar.fulltime` is a duration relative to the response, exactly like travel's
    /// `time_left`. Nudging the timeline's "now" onto the server clock without moving
    /// bar anchors with it would knock 90 s off every bar ETA. The one test in this
    /// file that is GREEN today — it must stay green.
    func testBarFulltimeStaysCorrectUnderClockSkew() async throws {
        // validFullResponse: energy 100/150 with fulltime 600.
        try await poll(serverTime: localNow + skew)

        XCTAssertEqual(try eta(.energy), 600,
                       "a relative fulltime must not be shifted by the clock offset")
    }
}
