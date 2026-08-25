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

    // MARK: - The offset must not itself be jittery (issue #46, review finding)
    //
    // `server_time` is whole seconds and the response takes real time to arrive, so the
    // quantity `server_time - Int(localReceiptTime)` wobbles by a second or three between
    // polls even when neither clock has moved. Re-deriving it from scratch every poll and
    // then measuring EVERY countdown against it feeds that wobble into the menu bar: the
    // number counts down for a minute and then jumps back UP at the poll boundary.
    //
    // This is the exact hazard `CooldownEnds.merged` was written for ("without smoothing,
    // every poll causes a visible jump in the menu bar countdown") — and routing `now`
    // through a jittery offset defeats that pin for every surface at once. So the offset
    // gets the same treatment as `endsAt`: ignore sub-tolerance movement, track real
    // corrections.
    //
    // Each test below runs the same shape — two polls 60 s of injected time apart, the
    // second response's anchor 2 s "late" (ordinary network latency) — and asserts the
    // countdown fell by exactly 60. Any implementation that lets latency reach `now`
    // reports 62 and has visibly ticked backwards on screen.

    /// The proof case from the review: 300 → 240 over a minute, never 242.
    func testCooldownCountdownDoesNotJumpBackWhenTheAnchorJitters() async throws {
        try await poll(serverTime: localNow,
                       cooldowns: ["drug": 0, "booster": 0, "medical": 300])
        XCTAssertEqual(app.serverClock.offset, 0, "first poll: anchor and receipt agree")
        XCTAssertEqual(try eta(.medical), 300)

        clock.advance(60)
        try await poll(serverTime: localNow + 58,
                       cooldowns: ["drug": 0, "booster": 0, "medical": 240])

        XCTAssertEqual(app.serverClock.offset, 0,
                       "2 s of request latency is jitter, not a clock correction — "
                       + "re-deriving the offset from scratch reads it as -2")
        XCTAssertEqual(try eta(.medical), 240,
                       "the menu bar counted 300…241 over that minute; 242 is a visible "
                       + "jump backwards on the app's only always-visible surface")
        XCTAssertEqual(app.menuBarDisplay, .cooldown(kind: .medical, seconds: 240))
    }

    /// Travel carries an absolute arrival timestamp, so the deadline is provably
    /// unchanged between the two polls — only `now` can move it.
    func testTravelCountdownDoesNotJumpBackWhenTheAnchorJitters() async throws {
        let arrival = localNow + 300
        try await poll(serverTime: localNow,
                       travel: travelSlice(arrivingAt: arrival,
                                           departedAt: localNow - 300,
                                           timeLeft: 300))
        XCTAssertEqual(app.travelSecondsRemaining, 300)

        clock.advance(60)
        try await poll(serverTime: localNow + 58,
                       travel: travelSlice(arrivingAt: arrival,
                                           departedAt: localNow - 300,
                                           timeLeft: 240))

        XCTAssertEqual(app.travelSecondsRemaining, 240,
                       "same arrival timestamp, 60 s later — the plane cannot get further away")
        XCTAssertEqual(app.menuBarDisplay, .traveling(destination: "Mexico", seconds: 240))
        XCTAssertEqual(try eta(.travel), 240)
    }

    func testHospitalCountdownDoesNotJumpBackWhenTheAnchorJitters() async throws {
        let release = localNow + 300
        try await poll(serverTime: localNow, status: hospitalSlice(until: release))
        XCTAssertEqual(try eta(.hospital), 300)

        clock.advance(60)
        try await poll(serverTime: localNow + 58, status: hospitalSlice(until: release))

        XCTAssertEqual(try eta(.hospital), 240,
                       "`until` never moved, so the countdown can only fall")
        XCTAssertEqual(app.menuBarDisplay, .hospitalAtHome(seconds: 240))
    }

    func testJailCountdownDoesNotJumpBackWhenTheAnchorJitters() async throws {
        let release = localNow + 450
        try await poll(serverTime: localNow, status: jailSlice(until: release))
        XCTAssertEqual(try eta(.jail), 450)

        clock.advance(60)
        try await poll(serverTime: localNow + 58, status: jailSlice(until: release))

        XCTAssertEqual(try eta(.jail), 390)
        XCTAssertEqual(app.menuBarDisplay, .jail(seconds: 390))
    }

    /// Chain and OC deadlines arrive on their own endpoints, so they are re-published
    /// verbatim after the second poll — identical absolute timestamps, nothing about
    /// them changed. Only the shared "now" can move these numbers.
    func testChainAndOrganizedCrimeCountdownsDoNotJumpBackWhenTheAnchorJitters() async throws {
        let chainTimeout = localNow + 180
        let ocReadyAt = localNow + 240

        try await poll(serverTime: localNow)
        publishChain(timeout: chainTimeout)
        app.organizedCrime = OrganizedCrime2(id: 1, name: "Clinical Precision",
                                             status: "Planning", readyAt: ocReadyAt)
        XCTAssertEqual(try eta(.chain), 180)
        XCTAssertEqual(try eta(.organizedCrime), 240)

        clock.advance(60)
        try await poll(serverTime: localNow + 58)
        publishChain(timeout: chainTimeout)
        app.organizedCrime = OrganizedCrime2(id: 1, name: "Clinical Precision",
                                             status: "Planning", readyAt: ocReadyAt)

        XCTAssertEqual(try eta(.chain), 120,
                       "the chain lapses at a fixed server instant — 122 is a jump backwards")
        XCTAssertEqual(try eta(.organizedCrime), 180,
                       "ready_at is a fixed server instant — 182 is a jump backwards")
    }

    /// Damping must not become latching. Four seconds is past the tolerance the cooldown
    /// pin already uses, so it is a real correction and has to be adopted — otherwise a
    /// Mac whose clock is being nudged would silently keep the stale skew.
    func testSkewChangeBeyondToleranceIsStillAdopted() async throws {
        let release = localNow + 600
        try await poll(serverTime: localNow, status: hospitalSlice(until: release))
        XCTAssertEqual(app.serverClock.offset, 0)

        // 60 s of local time pass; Torn's clock advanced 64 → the Mac lost 4 s.
        clock.advance(60)
        try await poll(serverTime: localNow + 64, status: hospitalSlice(until: release + 4))

        XCTAssertEqual(app.serverClock.offset, 4,
                       "4 s is past the jitter tolerance — a real correction, so track it")
        XCTAssertEqual(try eta(.hospital), 540)
    }

    /// Part (a) of the fix: the receipt instant must be sampled the moment the transport
    /// returns, not after the off-actor decode. Decoding burns real time, and folding it
    /// into `server_time - receiptTime` makes the app believe the Mac runs that much fast
    /// — freezing the countdown for exactly as long as the parse took.
    func testOffsetIsNotInflatedByDecodeTime() async throws {
        // 5 s of "decode" — deliberately past the jitter tolerance, so this test can only
        // pass by sampling the receipt earlier, never by damping.
        let slowService = ClockBurningSnapshotService(
            wrapping: UserSnapshotService(session: session),
            clock: clock,
            decodeSeconds: 5
        )
        app.stopPolling()
        app = AppState(session: session,
                       connectivity: ControllableConnectivity(connected: true),
                       defaults: .createMockDefaults(),
                       time: clock,
                       userSnapshotService: slowService)

        try await poll(serverTime: localNow, status: hospitalSlice(until: localNow + 300))

        XCTAssertEqual(app.serverClock.offset, 0,
                       "the decode took 5 s of wall time; that is not clock skew")
        XCTAssertEqual(try eta(.hospital), 295,
                       "5 s really did elapse, so 5 s came off the countdown — reading the "
                       + "receipt after the decode reports a frozen 300")
    }

    // MARK: - Helpers for the jitter suite

    private func publishChain(timeout: Int) {
        app.factionService.publishBasic(
            FactionData(name: "Test", factionId: 1, respect: 10,
                        chain: FactionChain(current: 25, max: 100,
                                            timeout: timeout, cooldown: 0))
        )
    }
}

/// Wraps the real snapshot service and burns injected clock time inside `parseSnapshot`,
/// the way a large payload's off-actor decode burns real time. Everything else passes
/// straight through.
private final class ClockBurningSnapshotService: UserSnapshotServicing, @unchecked Sendable {
    private let wrapped: UserSnapshotServicing
    private let clock: MutableTimeSource
    private let decodeSeconds: TimeInterval

    init(wrapping: UserSnapshotServicing, clock: MutableTimeSource, decodeSeconds: TimeInterval) {
        self.wrapped = wrapping
        self.clock = clock
        self.decodeSeconds = decodeSeconds
    }

    func load(_ url: URL) async throws -> UserHTTPResponse {
        try await wrapped.load(url)
    }

    func parseSnapshot(
        data: Data,
        requestedSelections: [String],
        grantedSelections: [String]?
    ) async -> UserServiceResult<UserSnapshotPayload> {
        let result = await wrapped.parseSnapshot(data: data,
                                                 requestedSelections: requestedSelections,
                                                 grantedSelections: grantedSelections)
        let seconds = decodeSeconds
        let clock = self.clock
        await MainActor.run { clock.advance(seconds) }
        return result
    }

    func loadActivity(_ url: URL) async throws -> UserServiceResult<UserActivityPayload> {
        try await wrapped.loadActivity(url)
    }

    func loadUserV2(_ url: URL) async throws -> UserServiceResult<UserV2Payload> {
        try await wrapped.loadUserV2(url)
    }

    func loadVirus(_ url: URL) async throws -> UserServiceResult<VirusProgramming?> {
        .success(nil, responseBytes: 0)
    }
}

/// The pure conversion `ServerClockOffsetTests` drives end-to-end. These pin the two
/// things the behavioural suite leaves open: exactly where the plausibility guard sits,
/// and that the server→local direction is a true inverse (the notification scheduler
/// depends on it — a local alert fires on the Mac's clock, so a server-absolute landing
/// time has to be converted back).
final class ServerClockTests: XCTestCase {

    private let localNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Deriving the offset

    func testAnchorAheadOfLocalYieldsPositiveOffset() {
        let clock = ServerClock(anchor: 1_700_000_090, localNow: localNow)
        XCTAssertEqual(clock.offset, 90, "Torn ahead of the Mac → add to the local clock")
    }

    /// A Mac running *fast* is just as ordinary as one running slow, and the correction
    /// has to go the other way.
    func testAnchorBehindLocalYieldsNegativeOffset() {
        let clock = ServerClock(anchor: 1_699_999_910, localNow: localNow)
        XCTAssertEqual(clock.offset, -90)
        XCTAssertEqual(clock.serverUnix(localNow), 1_699_999_910)
    }

    func testMissingOrZeroAnchorIsSynchronized() {
        XCTAssertEqual(ServerClock(anchor: nil, localNow: localNow), .synchronized)
        XCTAssertEqual(ServerClock(anchor: 0, localNow: localNow), .synchronized)
        XCTAssertEqual(ServerClock(anchor: -5, localNow: localNow), .synchronized,
                       "a negative epoch is nonsense, not skew")
    }

    /// The guard's exact edge, in both directions. Pinned so a later tightening of the
    /// window is a deliberate, visible change rather than a silent regression in which
    /// countdowns quietly stop being corrected.
    func testPlausibilityGuardBoundary() {
        let limit = ServerClock.maxPlausibleSkewSeconds

        XCTAssertEqual(ServerClock(anchor: 1_700_000_000 + limit, localNow: localNow).offset, limit,
                       "skew exactly at the limit is still honoured")
        XCTAssertEqual(ServerClock(anchor: 1_700_000_000 - limit, localNow: localNow).offset, -limit,
                       "and symmetrically in the other direction")
        XCTAssertEqual(ServerClock(anchor: 1_700_000_000 + limit + 1, localNow: localNow).offset, 0,
                       "one second past the limit is a corrupt payload → discard")
        XCTAssertEqual(ServerClock(anchor: 1_700_000_000 - limit - 1, localNow: localNow).offset, 0)
    }

    // MARK: - Converting

    func testServerNowAndServerUnixAgree() {
        let clock = ServerClock(offset: 90)
        XCTAssertEqual(clock.serverNow(localNow), localNow.addingTimeInterval(90))
        XCTAssertEqual(clock.serverUnix(localNow), 1_700_000_090)
    }

    /// Fetch-relative durations become absolute *server* timestamps.
    func testServerTimestampAnchorsARelativeDuration() {
        let clock = ServerClock(offset: 90)
        XCTAssertEqual(clock.serverTimestamp(fetchedAt: localNow, plus: 300), 1_700_000_390)
    }

    /// The direction the travel-notification scheduler needs: a landing 300 s away on
    /// Torn's clock is 300 s away on the Mac's too — the skew must not shorten the wait.
    func testLocalDateForServerTimestampInvertsTheOffset() {
        let clock = ServerClock(offset: 90)
        let landsAt = clock.serverUnix(localNow) + 300      // server-absolute

        let localLanding = clock.localDate(forServerTimestamp: landsAt)

        XCTAssertEqual(localLanding, localNow.addingTimeInterval(300),
                       "a 90 s-slow Mac must not fire the landing alert 90 s early")
        XCTAssertEqual(clock.serverUnix(localLanding), landsAt, "round-trips exactly")
    }

    func testSynchronizedClockIsTheIdentity() {
        let clock = ServerClock.synchronized
        XCTAssertEqual(clock.serverNow(localNow), localNow)
        XCTAssertEqual(clock.localDate(forServerTimestamp: 1_700_000_000), localNow)
    }

    // MARK: - Damping the offset

    /// `merged` is the offset's version of `CooldownEnds.merged`, and exists for the same
    /// reason: whole-second `server_time` minus a whole-second local receipt, plus that
    /// request's latency, makes the derived offset wobble by a second or three between
    /// polls even when neither clock moved. Since every countdown is now measured against
    /// this offset, letting the wobble through walks the menu bar backwards at each poll.
    func testJitterWithinToleranceKeepsThePreviousOffset() {
        let pinned = ServerClock(offset: 90)

        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 92)).offset, 90,
                       "2 s of latency is not a clock correction")
        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 88)).offset, 90,
                       "and symmetrically in the other direction")
        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 90)).offset, 90)
    }

    /// The exact edge, pinned in both directions so a later change to the window is
    /// deliberate rather than a silent regression.
    func testMergeToleranceBoundary() {
        let tolerance = ServerClock.jitterToleranceSeconds
        XCTAssertEqual(tolerance, 3, "the window CooldownEnds.merged has always used")
        let pinned = ServerClock(offset: 90)

        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 90 + tolerance)).offset, 90,
                       "movement exactly at the tolerance is still jitter")
        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 90 - tolerance)).offset, 90)
        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 90 + tolerance + 1)).offset,
                       90 + tolerance + 1,
                       "one second past it is a real correction — adopt it")
        XCTAssertEqual(pinned.merged(with: ServerClock(offset: 90 - tolerance - 1)).offset,
                       90 - tolerance - 1)
    }

    /// One tolerance for the whole clock. `CooldownEnds.merged` damps `endsAt` and
    /// `ServerClock.merged` damps the `now` it is subtracted from — two halves of one
    /// subtraction, so a divergent window would reintroduce the jump on one side.
    func testCooldownPinSharesTheSameToleranceWindow() {
        let tolerance = ServerClock.jitterToleranceSeconds
        let pinned = CooldownEnds(drugEndsAt: 0, boosterEndsAt: 0, medicalEndsAt: 1_000)

        func mergedMedical(_ endsAt: Int) -> Int {
            pinned.merged(with: CooldownEnds(drugEndsAt: 0, boosterEndsAt: 0, medicalEndsAt: endsAt))
                .medicalEndsAt
        }

        XCTAssertEqual(mergedMedical(1_000 + tolerance), 1_000,
                       "cooldowns hold at exactly the same window the offset does")
        XCTAssertEqual(mergedMedical(1_000 + tolerance + 1), 1_000 + tolerance + 1)
    }

    /// Damping must never become latching: a Mac whose clock is corrected mid-session,
    /// or a payload whose anchor was discarded as implausible, has to move the offset.
    func testMergeAdoptsGenuineCorrections() {
        XCTAssertEqual(ServerClock.synchronized.merged(with: ServerClock(offset: 90)).offset, 90,
                       "first real skew must be adopted, not damped away")
        XCTAssertEqual(ServerClock(offset: 90).merged(with: .synchronized).offset, 0,
                       "a discarded anchor degrades to the local clock rather than latching")
        XCTAssertEqual(ServerClock(offset: 90).merged(with: ServerClock(offset: -30)).offset, -30)
    }

    /// Slow one-directional drift still converges: each poll compares against the
    /// *pinned* value, not the previous derivation, so the error is bounded by the
    /// tolerance and a correction always lands.
    func testSlowDriftEventuallyCrossesTheToleranceAndIsAdopted() {
        var pinned = ServerClock(offset: 0)
        for derived in 1...ServerClock.jitterToleranceSeconds {
            pinned = pinned.merged(with: ServerClock(offset: derived))
            XCTAssertEqual(pinned.offset, 0, "still inside the window")
        }
        pinned = pinned.merged(with: ServerClock(offset: ServerClock.jitterToleranceSeconds + 1))
        XCTAssertEqual(pinned.offset, ServerClock.jitterToleranceSeconds + 1,
                       "drift past the window is picked up — bounded error, no latching")
    }
}
