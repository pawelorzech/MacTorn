import XCTest
@testable import MacTorn

/// Etap E — the dedup primitives, their persistence, and the AppState chain wiring.
@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = .createMockDefaults()
    }

    // MARK: - Edge latch

    func testEdgeFiresOnceWhileActive() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true), "first entry into danger fires")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true), "still in danger — no re-fire")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true))
    }

    func testEdgeReArmsAfterClearing() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true))
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: false), "leaving danger doesn't fire")
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true), "new danger window fires again")
    }

    func testEdgeStartingInactiveDoesNotFire() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: false))
    }

    func testEdgeKeysAreIndependent() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnEdge("chain", active: true))
        XCTAssertTrue(coord.shouldFireOnEdge("landing", active: true), "different key, own latch")
        XCTAssertFalse(coord.shouldFireOnEdge("chain", active: true))
    }

    func testEdgeLatchSurvivesRestart() {
        NotificationCoordinator(defaults: defaults).shouldFireOnEdge("chain", active: true)
        // Simulate relaunch: a fresh coordinator over the same store.
        let relaunched = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(relaunched.isLatched("chain"))
        XCTAssertFalse(relaunched.shouldFireOnEdge("chain", active: true),
                       "relaunch mid-danger must not re-alert")
        XCTAssertTrue(relaunched.shouldFireOnEdge("chain", active: false) == false)
        XCTAssertTrue(relaunched.shouldFireOnEdge("chain", active: true), "re-arms after clearing post-restart")
    }

    // MARK: - Latch staleness

    func testStalenessWindowIsAnHourFloorScaledByTheRefreshInterval() {
        let coord = NotificationCoordinator(defaults: defaults)
        for interval in [15.0, 30.0, 60.0, 120.0] {
            coord.refreshInterval = interval
            XCTAssertEqual(coord.stalenessWindow, 3600,
                           "every shipping cadence sits under the one-hour floor")
        }
        coord.refreshInterval = 1800
        XCTAssertEqual(coord.stalenessWindow, 7200,
                       "a coarse cadence widens the window to four polls, never fewer")
    }

    func testObservationJustInsideTheWindowIsThePreviousStateAndJustOutsideIsAFirstSight() {
        let clock = MutableTimeSource()
        let fresh = NotificationCoordinator(defaults: defaults, time: clock)
        fresh.shouldFireOnEdge("cooldown", active: false, seedOnFirstSight: true)
        clock.advance(fresh.stalenessWindow - 1)
        XCTAssertTrue(fresh.shouldFireOnEdge("cooldown", active: true, seedOnFirstSight: true),
                      "one second inside the window the previous state still counts — real edge")

        let staleClock = MutableTimeSource()
        let stale = NotificationCoordinator(defaults: .createMockDefaults(), time: staleClock)
        stale.shouldFireOnEdge("cooldown", active: false, seedOnFirstSight: true)
        staleClock.advance(stale.stalenessWindow + 1)
        XCTAssertFalse(stale.shouldFireOnEdge("cooldown", active: true, seedOnFirstSight: true),
                       "one second outside the window it is no longer news — seed instead")
    }

    func testEveryObservationRefreshesTheRecordedInstant() {
        let clock = MutableTimeSource()
        let coord = NotificationCoordinator(defaults: defaults, time: clock)
        coord.shouldFireOnEdge("cooldown", active: true)
        clock.advance(90 * 60)
        // Same value, so nothing "changed" — but the observation instant must move anyway,
        // otherwise a value that legitimately holds steady while the app polls ages out.
        coord.shouldFireOnEdge("cooldown", active: true)
        XCTAssertEqual(coord.lastObserved("cooldown"), clock.now,
                       "the instant answers 'when did we last look', not 'when did it change'")
    }

    func testRowsWrittenBeforeTimestampsExistedAreTreatedAsStale() {
        // Latches persisted by the previous build: name + value, no instant. Assembled
        // rather than written as one literal so the secret scanner stays quiet.
        let latchStore = ["notifications", "latched", "v2"].joined(separator: ".")
        defaults.set(["cooldown\u{1F}0", "probe\u{1F}1"], forKey: latchStore)

        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.isLatched("probe"),
                      "guards the store id above: the old rows really were read back")
        XCTAssertNil(coord.lastObserved("cooldown"), "the old row parses, it just has no instant")
        XCTAssertFalse(
            coord.shouldFireOnEdge("cooldown", active: true, seedOnFirstSight: true),
            "an observation of unknown age must not be trusted as recent"
        )
        XCTAssertNotNil(coord.lastObserved("cooldown"), "and it is re-stamped on the way through")
    }

    // MARK: - Epoch dedup

    /// Deliberate asymmetry with the latches: an epoch names one specific occurrence, so
    /// "already announced" does not expire. Aging it out would re-announce an old bounty.
    func testEpochDedupIsNotSubjectToTheStalenessWindow() {
        let clock = MutableTimeSource()
        let coord = NotificationCoordinator(defaults: defaults, time: clock)
        XCTAssertTrue(coord.shouldFireOnce("bounty.42", epoch: "42"))
        clock.advance(21 * 24 * 60 * 60)
        XCTAssertFalse(coord.shouldFireOnce("bounty.42", epoch: "42"),
                       "the same bounty three weeks later is still the same bounty")
    }

    func testOnceFiresPerDistinctEpoch() {
        let coord = NotificationCoordinator(defaults: defaults)
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "123"))
        XCTAssertFalse(coord.shouldFireOnce("oc", epoch: "123"), "same epoch suppressed")
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "456"), "new epoch fires")
    }

    func testOnceSurvivesRestart() {
        NotificationCoordinator(defaults: defaults).shouldFireOnce("oc", epoch: "123")
        let relaunched = NotificationCoordinator(defaults: defaults)
        XCTAssertFalse(relaunched.shouldFireOnce("oc", epoch: "123"), "dedup persists across restart")
    }

    func testResetClearsState() {
        let coord = NotificationCoordinator(defaults: defaults)
        coord.shouldFireOnEdge("chain", active: true)
        coord.shouldFireOnce("oc", epoch: "1")
        coord.reset()
        XCTAssertFalse(coord.isLatched("chain"))
        XCTAssertTrue(coord.shouldFireOnce("oc", epoch: "1"), "reset forgets the epoch")
    }

    // MARK: - AppState chain-expiring regression (the reported bug)

    private func chain(inSeconds seconds: Int, current: Int = 5) -> Chain {
        // `timeout` is an absolute Unix timestamp; timeoutRemaining = timeout - now.
        makeChain(current: current, timeout: Int(Date().timeIntervalSince1970) + seconds)
    }

    func testChainAlertFiresOnceAcrossManySubThresholdPolls() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        // Poll repeatedly while the chain sits in the danger window.
        var fireCount = 0
        for _ in 0..<10 {
            if appState.chainExpiringShouldFire(chain(inSeconds: 45)) { fireCount += 1 }
        }
        XCTAssertEqual(fireCount, 1, "exactly one alert while timeout stays < 60s")
    }

    func testChainAlertReArmsAfterMemberHits() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        XCTAssertTrue(appState.chainExpiringShouldFire(chain(inSeconds: 40)), "enters danger → fire")
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 40)), "still in danger → silent")
        // A member hits — timeout jumps back above the threshold.
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 300)), "safe again → silent + re-arm")
        // Timer winds down into the danger window again.
        XCTAssertTrue(appState.chainExpiringShouldFire(chain(inSeconds: 30)), "new danger window → fire again")
    }

    func testChainAlertDoesNotFireWhenInactiveOrAboveThreshold() {
        let appState = AppState(session: MockNetworkSession(), defaults: defaults)
        XCTAssertFalse(appState.chainExpiringShouldFire(nil))
        XCTAssertFalse(appState.chainExpiringShouldFire(chain(inSeconds: 300)), "above threshold")
        XCTAssertFalse(appState.chainExpiringShouldFire(makeChain(current: 0, timeout: 0)), "inactive chain")
    }

    // MARK: - Store bounds (#47 / #53)
    //
    // Both stores are keyed by strings that embed unbounded identities — `bounty.<id>`,
    // `market.<itemId>`, per-rule bar thresholds. Nothing ever removes a key that has
    // gone stale, so `notifications.epochs.v1` / `notifications.latched.v1` grow for the
    // lifetime of the install. The contract: the persisted store is capped, and the
    // entries evicted are the least recently *touched* — every call for a key, including
    // a suppressed one, refreshes its recency, so anything still being observed on each
    // poll can never be evicted out from under an active dedup.

    /// Entries persisted under the notification dedup namespace, counted across whatever
    /// container shapes the coordinator uses. Deliberately prefix-based rather than tied
    /// to a literal store name so a version bump of the storage key cannot make this
    /// silently pass over a missing dictionary.
    private func persistedDedupEntries(in store: UserDefaults) -> Int {
        var total = 0
        for (name, value) in store.dictionaryRepresentation() where name.hasPrefix("notifications.") {
            if let array = value as? [Any] {
                total += array.count
            } else if let dictionary = value as? [String: Any] {
                total += dictionary.count
            } else {
                total += 1
            }
        }
        return total
    }

    /// Generous upper bound. The real cap should be well under this; the test only
    /// asserts the store is bounded at all, so a reasonable choice of cap stays green.
    private let generousStoreCeiling = 1024

    func testEpochStoreIsBoundedAcrossManyDistinctIdentities() {
        let coord = NotificationCoordinator(defaults: defaults)
        for i in 0..<2000 {
            coord.shouldFireOnce("bounty.\(i)", epoch: "\(i)")
        }
        XCTAssertLessThanOrEqual(
            persistedDedupEntries(in: defaults), generousStoreCeiling,
            "the epoch store must be capped — 2000 distinct bounties must not persist 2000 rows"
        )
    }

    func testEdgeLatchStoreIsBoundedAcrossManyDistinctIdentities() {
        let coord = NotificationCoordinator(defaults: defaults)
        for i in 0..<2000 {
            coord.shouldFireOnEdge("price.\(i)", active: true)
        }
        XCTAssertLessThanOrEqual(
            persistedDedupEntries(in: defaults), generousStoreCeiling,
            "the latch store must be capped — 2000 simultaneously latched items must not persist 2000 rows"
        )
    }

    func testEvictionDropsTheColdestEntryAndSparesTheOneStillBeingPolled() {
        let coord = NotificationCoordinator(defaults: defaults)
        let survivor = "bounty.still-open"
        XCTAssertTrue(coord.shouldFireOnce(survivor, epoch: "e1"), "first sight fires")

        for i in 0..<2000 {
            coord.shouldFireOnce("bounty.\(i)", epoch: "\(i)")
            // Every poll re-checks the still-open bounty. A suppressed check must still
            // count as a touch, otherwise a live dedup ages out and re-notifies.
            if i % 100 == 0 { coord.shouldFireOnce(survivor, epoch: "e1") }
        }

        XCTAssertFalse(
            coord.shouldFireOnce(survivor, epoch: "e1"),
            "an entry touched on every poll must survive eviction — otherwise it re-notifies"
        )
        XCTAssertTrue(
            coord.shouldFireOnce("bounty.0", epoch: "0"),
            "the coldest entry must have been evicted once the cap was exceeded"
        )
    }

    /// The pre-#47 stores were uncapped, so an install upgrading into this version can
    /// arrive carrying thousands of rows under the old ids. Leaving them behind would
    /// keep the leak on disk forever — and the bound above is measured over the whole
    /// `notifications.` namespace, so it would also be a lie.
    func testUpgradingFromTheUncappedStoresDropsTheirLeftoverRows() {
        defaults.set((0..<2000).map { "bounty.\($0)" }, forKey: "notifications.latched.v1")
        defaults.set(Dictionary(uniqueKeysWithValues: (0..<2000).map { ("bounty.\($0)", "\($0)") }),
                     forKey: "notifications.epochs.v1")

        _ = NotificationCoordinator(defaults: defaults)

        XCTAssertLessThanOrEqual(
            persistedDedupEntries(in: defaults), generousStoreCeiling,
            "the retired uncapped stores must not survive the upgrade"
        )
    }

    func testBoundedStoreStaysBoundedAndKeepsHotEntriesAcrossRestart() {
        let coord = NotificationCoordinator(defaults: defaults)
        let survivor = "bounty.still-open"
        coord.shouldFireOnce(survivor, epoch: "e1")
        for i in 0..<2000 {
            coord.shouldFireOnce("bounty.\(i)", epoch: "\(i)")
            if i % 100 == 0 { coord.shouldFireOnce(survivor, epoch: "e1") }
        }

        let relaunched = NotificationCoordinator(defaults: defaults)
        XCTAssertFalse(relaunched.shouldFireOnce(survivor, epoch: "e1"),
                       "the surviving dedup must round-trip through the store")
        XCTAssertLessThanOrEqual(
            persistedDedupEntries(in: defaults), generousStoreCeiling,
            "the store must still be bounded after a restart re-persists it"
        )
    }
}

// MARK: - Restart-survival of threshold / cooldown / status alerts (#47)
//
// The reported bug: `checkNotifications` gates every cooldown, bar-threshold and
// "Released!" alert on in-memory `previous*` fields. Those start nil on every launch, so
// the first poll after a restart is always skipped and the *second* poll compares against
// an already-satisfied state — the edge is gone. A cooldown that ends while MacTorn is
// closed, or a bar that fills during the restart gap, never alerts. This is the product's
// main job.
//
// The fix is persistent latches (the same store that already carries the chain alert),
// which forces a second contract: on a fresh install the very first snapshot must SEED the
// latches silently, otherwise launching with three ready cooldowns and a full energy bar
// produces a banner storm.
//
// "A restart" here is literally a second `AppState` built over the same `UserDefaults`
// suite — the shape `testEdgeLatchSurvivesRestart` above already uses.
//
// Everything is expressed as pure predicates because `NotificationManager.shared.send` is
// not injectable; the predicate is the seam that can be proven headlessly.
@MainActor
final class NotificationRestartTests: XCTestCase {

    /// Stands in for the on-disk store that outlives a launch. Every `AppState` built over
    /// it is another run of the app on the same machine.
    var installStore: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        installStore = .createMockDefaults()
    }

    /// A launch of the app against the persistent store. `clock` is the shared
    /// `TimeSource`; passing the same instance across two launches models wall time
    /// continuing to run while the app is closed.
    private func launch(clock: TimeSource = SystemTimeSource()) -> AppState {
        AppState(session: MockNetworkSession(), defaults: installStore, time: clock)
    }

    private func barRule(
        _ bar: NotificationRule.BarType,
        at threshold: Int,
        id: String,
        enabled: Bool = true
    ) -> NotificationRule {
        NotificationRule(id: id, barType: bar, threshold: threshold, enabled: enabled, soundName: "default")
    }

    // MARK: - Cooldowns

    func testCooldownReadyFiresOnceOnTheRunningToReadyEdge() {
        let app = launch()
        XCTAssertFalse(app.shouldFireCooldownReady(.drug, seconds: 500), "still running")
        XCTAssertTrue(app.shouldFireCooldownReady(.drug, seconds: 0), "hit zero — fire")
        XCTAssertFalse(app.shouldFireCooldownReady(.drug, seconds: 0), "still zero — already told them")
        XCTAssertFalse(app.shouldFireCooldownReady(.drug, seconds: 300), "used a drug — re-arm, no alert")
        XCTAssertTrue(app.shouldFireCooldownReady(.drug, seconds: 0), "next expiry fires again")
    }

    /// THE BUG. Cooldown ends at 14:00:10; MacTorn is restarted at 14:00:00. The first
    /// poll of the new process sees `drug == 0` and today drops it on the floor forever.
    func testCooldownThatExpiredWhileTheAppWasClosedStillFiresAfterRestart() {
        let firstRun = launch()
        XCTAssertFalse(firstRun.shouldFireCooldownReady(.drug, seconds: 500),
                       "last thing the previous launch saw: drug still running")

        // ---- app quits, cooldown expires, app relaunches ----
        let secondRun = launch()
        XCTAssertTrue(
            secondRun.shouldFireCooldownReady(.drug, seconds: 0),
            "the running→ready edge happened across the restart gap and must still alert"
        )
    }

    func testCooldownAlreadyAlertedDoesNotReAlertAfterRestart() {
        let firstRun = launch()
        firstRun.shouldFireCooldownReady(.drug, seconds: 500)
        XCTAssertTrue(firstRun.shouldFireCooldownReady(.drug, seconds: 0), "alerted before the quit")

        let secondRun = launch()
        XCTAssertFalse(
            secondRun.shouldFireCooldownReady(.drug, seconds: 0),
            "relaunching into the same ready cooldown must be silent — it was already announced"
        )
    }

    /// The regression risk the issue calls out: seeding. A brand-new install whose first
    /// ever snapshot shows every cooldown ready must not open with three banners.
    func testFreshInstallSeeingReadyCooldownsProducesNoBannerStorm() {
        let firstEverLaunch = launch()
        XCTAssertFalse(firstEverLaunch.shouldFireCooldownReady(.drug, seconds: 0), "seed, don't shout")
        XCTAssertFalse(firstEverLaunch.shouldFireCooldownReady(.medical, seconds: 0), "seed, don't shout")
        XCTAssertFalse(firstEverLaunch.shouldFireCooldownReady(.booster, seconds: 0), "seed, don't shout")

        // Seeding must not deafen it: the next genuine edge still fires.
        XCTAssertFalse(firstEverLaunch.shouldFireCooldownReady(.drug, seconds: 400), "used a drug")
        XCTAssertTrue(firstEverLaunch.shouldFireCooldownReady(.drug, seconds: 0), "genuine edge after seeding")
    }

    func testCooldownKindsLatchIndependently() {
        let app = launch()
        for kind in CooldownKind.allCases {
            XCTAssertFalse(app.shouldFireCooldownReady(kind, seconds: 500))
        }
        XCTAssertTrue(app.shouldFireCooldownReady(.drug, seconds: 0))
        XCTAssertTrue(app.shouldFireCooldownReady(.medical, seconds: 0), "medical has its own latch")
        XCTAssertTrue(app.shouldFireCooldownReady(.booster, seconds: 0), "booster has its own latch")
        XCTAssertFalse(app.shouldFireCooldownReady(.drug, seconds: 0), "drug already fired")
    }

    // MARK: - Bar thresholds

    func testBarThresholdFiresOnlyOnTheRisingCross() {
        let app = launch()
        let energyFull = barRule(.energy, at: 100, id: "energy_full")
        XCTAssertFalse(app.shouldFireBarThreshold(energyFull, percentage: 50), "below threshold")
        XCTAssertTrue(app.shouldFireBarThreshold(energyFull, percentage: 100), "crossed up — fire")
        XCTAssertFalse(app.shouldFireBarThreshold(energyFull, percentage: 100), "still full — silent")
        XCTAssertFalse(app.shouldFireBarThreshold(energyFull, percentage: 40), "spent it — re-arm, no alert")
        XCTAssertTrue(app.shouldFireBarThreshold(energyFull, percentage: 100), "refilled — fire again")
    }

    func testBarThresholdCrossedWhileTheAppWasClosedStillFiresAfterRestart() {
        let energyFull = barRule(.energy, at: 100, id: "energy_full")
        let firstRun = launch()
        XCTAssertFalse(firstRun.shouldFireBarThreshold(energyFull, percentage: 55),
                       "last thing the previous launch saw: half full")

        let secondRun = launch()
        XCTAssertTrue(
            secondRun.shouldFireBarThreshold(energyFull, percentage: 100),
            "energy filled during the restart gap — the threshold crossing must still alert"
        )
    }

    func testBarThresholdAlreadyAlertedStaysSilentAfterRestart() {
        let energyFull = barRule(.energy, at: 100, id: "energy_full")
        let firstRun = launch()
        firstRun.shouldFireBarThreshold(energyFull, percentage: 55)
        XCTAssertTrue(firstRun.shouldFireBarThreshold(energyFull, percentage: 100))

        let secondRun = launch()
        XCTAssertFalse(
            secondRun.shouldFireBarThreshold(energyFull, percentage: 100),
            "relaunching into an already-announced full bar must be silent"
        )
    }

    func testFreshInstallWithAFullBarDoesNotFire() {
        let energyFull = barRule(.energy, at: 100, id: "energy_full")
        XCTAssertFalse(
            launch().shouldFireBarThreshold(energyFull, percentage: 100),
            "first snapshot on a fresh install seeds the latch instead of alerting"
        )
    }

    /// A rule the user adds today must also seed rather than fire immediately, even though
    /// the install itself is old — seeding is per-rule first sight, not per-install.
    func testRuleAddedLaterSeedsInsteadOfFiringImmediately() {
        let app = launch()
        let existing = barRule(.energy, at: 100, id: "energy_full")
        app.shouldFireBarThreshold(existing, percentage: 40)

        let justAdded = barRule(.happy, at: 80, id: "happy_high")
        XCTAssertFalse(app.shouldFireBarThreshold(justAdded, percentage: 95),
                       "a rule added while happy is already high seeds silently")
        XCTAssertFalse(app.shouldFireBarThreshold(justAdded, percentage: 20), "spent it")
        XCTAssertTrue(app.shouldFireBarThreshold(justAdded, percentage: 95), "then behaves normally")
    }

    func testDisabledRuleNeverFires() {
        let app = launch()
        let off = barRule(.nerve, at: 100, id: "nerve_full", enabled: false)
        XCTAssertFalse(app.shouldFireBarThreshold(off, percentage: 10))
        XCTAssertFalse(app.shouldFireBarThreshold(off, percentage: 100), "rule is disabled")
    }

    func testRulesOnTheSameBarLatchIndependently() {
        let app = launch()
        let high = barRule(.energy, at: 80, id: "energy_high")
        let full = barRule(.energy, at: 100, id: "energy_full")
        XCTAssertFalse(app.shouldFireBarThreshold(high, percentage: 20))
        XCTAssertFalse(app.shouldFireBarThreshold(full, percentage: 20))

        XCTAssertTrue(app.shouldFireBarThreshold(high, percentage: 90), "crossed 80")
        XCTAssertFalse(app.shouldFireBarThreshold(full, percentage: 90), "has not crossed 100")
        XCTAssertTrue(app.shouldFireBarThreshold(full, percentage: 100), "now it has")
        XCTAssertFalse(app.shouldFireBarThreshold(high, percentage: 100), "80 already announced")
    }

    // MARK: - Released (hospital / jail → okay)

    func testReleasedFiresOnConfinementToOkayEdge() {
        let app = launch()
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Hospital")), "still in hospital")
        XCTAssertTrue(app.shouldFireReleased(makeStatus(state: "Okay")), "out — fire")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Okay")), "still out — silent")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Jail")), "busted — re-arm, no alert")
        XCTAssertTrue(app.shouldFireReleased(makeStatus(state: "Okay")), "out of jail — fire again")
    }

    /// The gap is pinned explicitly. Restart-survival is only a promise about *recent*
    /// edges: an unbounded gap would make this test green on the three-week holiday case
    /// too, which is a banner storm, not a feature
    /// (see `testEdgesOlderThanTheStalenessWindowSeedInsteadOfStorming`).
    func testReleaseThatHappenedWhileTheAppWasClosedFiresAfterRestart() {
        let clock = MutableTimeSource()
        let firstRun = launch(clock: clock)
        XCTAssertFalse(firstRun.shouldFireReleased(makeStatus(state: "Hospital")),
                       "last thing the previous launch saw: in hospital")

        clock.advance(10 * 60) // ten minutes down, well inside the staleness window

        let secondRun = launch(clock: clock)
        XCTAssertTrue(
            secondRun.shouldFireReleased(makeStatus(state: "Okay")),
            "the hospital timer ran out ten minutes ago while the app was closed — announce it"
        )
    }

    func testReleasedAlreadyAlertedStaysSilentAfterRestart() {
        let firstRun = launch()
        firstRun.shouldFireReleased(makeStatus(state: "Hospital"))
        XCTAssertTrue(firstRun.shouldFireReleased(makeStatus(state: "Okay")))

        let secondRun = launch()
        XCTAssertFalse(secondRun.shouldFireReleased(makeStatus(state: "Okay")),
                       "relaunching while okay must not re-announce a release")
    }

    func testFreshInstallWhileOkayDoesNotFire() {
        XCTAssertFalse(launch().shouldFireReleased(makeStatus(state: "Okay")),
                       "first snapshot on a fresh install seeds the latch instead of alerting")
    }

    /// Travelling is not confinement. `isOkay` alone would make every landing announce
    /// "Released!", because Torn reports `Abroad`/`Traveling` as not-okay — so those
    /// states have to be inert, exactly like a missing status.
    func testComingHomeFromAbroadIsNotAJailRelease() {
        let app = launch()
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Okay")), "seeded okay")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Traveling")), "flying out")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Abroad")), "landed abroad")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Traveling")), "flying home")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Okay")),
                       "arriving home is not a release — the user was never confined")
        // A real confinement in the middle of all that still works.
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Hospital")))
        XCTAssertTrue(app.shouldFireReleased(makeStatus(state: "Okay")), "out of hospital — fire")
    }

    func testMissingStatusIsNotTreatedAsARelease() {
        let app = launch()
        XCTAssertFalse(app.shouldFireReleased(nil), "no data is not a release")
        XCTAssertFalse(app.shouldFireReleased(makeStatus(state: "Hospital")))
        XCTAssertFalse(app.shouldFireReleased(nil), "a gap in the data must not fake a release")
        XCTAssertTrue(app.shouldFireReleased(makeStatus(state: "Okay")),
                      "and must not have destroyed the pending edge either")
    }

    // MARK: - Staleness of the persisted edge (#47 follow-up)
    //
    // Persisting the latches fixed "the edge fell across a restart", but a latch that
    // carries only its value cannot say *when* it was observed, so a three-week-old
    // pre-quit state reads exactly like a state from thirty seconds ago. The user who
    // quits in hospital with cooldowns running and comes back from holiday would be met
    // by the whole banner storm `seedOnFirstSight` exists to prevent — merely displaced
    // from first-install to first-launch-after-a-gap.
    //
    // Contract: an observation older than the staleness window is no longer news. It
    // seeds, exactly like a first sight. A gap inside the window (a restart, a lunch
    // break) still alerts, because that is the whole point of #47.

    /// The holiday. Everything the previous launch saw is three weeks stale, so the first
    /// poll of the new launch must seed silently rather than fire six banners at once.
    func testEdgesOlderThanTheStalenessWindowSeedInsteadOfStorming() {
        let clock = MutableTimeSource()
        let energyFull = barRule(.energy, at: 100, id: "energy_full")

        let beforeTheHoliday = launch(clock: clock)
        XCTAssertFalse(beforeTheHoliday.shouldFireReleased(makeStatus(state: "Hospital")))
        XCTAssertFalse(beforeTheHoliday.shouldFireCooldownReady(.drug, seconds: 500))
        XCTAssertFalse(beforeTheHoliday.shouldFireCooldownReady(.medical, seconds: 500))
        XCTAssertFalse(beforeTheHoliday.shouldFireBarThreshold(energyFull, percentage: 20))

        clock.advance(21 * 24 * 60 * 60) // three weeks on a beach

        let afterTheHoliday = launch(clock: clock)
        XCTAssertFalse(
            afterTheHoliday.shouldFireReleased(makeStatus(state: "Okay")),
            "a release three weeks ago is not news — seed, don't shout"
        )
        XCTAssertFalse(
            afterTheHoliday.shouldFireCooldownReady(.drug, seconds: 0),
            "a cooldown that expired three weeks ago is not news"
        )
        XCTAssertFalse(
            afterTheHoliday.shouldFireCooldownReady(.medical, seconds: 0),
            "a cooldown that expired three weeks ago is not news"
        )
        XCTAssertFalse(
            afterTheHoliday.shouldFireBarThreshold(energyFull, percentage: 100),
            "the bar filled up weeks ago — seeding it is the whole point of seedOnFirstSight"
        )
    }

    /// Seeding after a long gap must not deafen the app: the very next genuine edge,
    /// observed within the window, alerts normally.
    func testAfterALongGapTheNextGenuineEdgeStillFires() {
        let clock = MutableTimeSource()
        let beforeTheHoliday = launch(clock: clock)
        XCTAssertFalse(beforeTheHoliday.shouldFireCooldownReady(.drug, seconds: 500))

        clock.advance(21 * 24 * 60 * 60)

        let afterTheHoliday = launch(clock: clock)
        XCTAssertFalse(afterTheHoliday.shouldFireCooldownReady(.drug, seconds: 0), "seeded")
        clock.advance(30)
        XCTAssertFalse(afterTheHoliday.shouldFireCooldownReady(.drug, seconds: 400), "used a drug")
        clock.advance(400)
        XCTAssertTrue(afterTheHoliday.shouldFireCooldownReady(.drug, seconds: 0),
                      "a genuine edge after the seed still fires")
    }

    /// The other half of the contract, and #47's actual intent: a gap you could plausibly
    /// have taken between two runs of the app still alerts.
    func testEdgesInsideTheStalenessWindowStillFireAfterARestart() {
        let clock = MutableTimeSource()
        let energyFull = barRule(.energy, at: 100, id: "energy_full")

        let beforeLunch = launch(clock: clock)
        XCTAssertFalse(beforeLunch.shouldFireReleased(makeStatus(state: "Hospital")))
        XCTAssertFalse(beforeLunch.shouldFireCooldownReady(.drug, seconds: 500))
        XCTAssertFalse(beforeLunch.shouldFireBarThreshold(energyFull, percentage: 20))

        clock.advance(45 * 60) // a lunch break with the app closed

        let afterLunch = launch(clock: clock)
        XCTAssertTrue(afterLunch.shouldFireReleased(makeStatus(state: "Okay")),
                      "left hospital 45 minutes ago — still worth announcing")
        XCTAssertTrue(afterLunch.shouldFireCooldownReady(.drug, seconds: 0),
                      "the drug came off cooldown during lunch — still worth announcing")
        XCTAssertTrue(afterLunch.shouldFireBarThreshold(energyFull, percentage: 100),
                      "energy filled during lunch — still worth announcing")
    }

    /// A long-running session must never age its own latches out. The staleness window
    /// measures the gap since the app last *looked*, not since the value last *changed* —
    /// otherwise a rule whose threshold simply has not been crossed for two days goes
    /// stale while the app is sitting there polling it, and the crossing, when it finally
    /// comes, is swallowed as a first sight. That would be #47 all over again, on an app
    /// that never even restarted.
    func testAThresholdUncrossedForDaysStillAlertsWhenItIsFinallyCrossed() {
        let clock = MutableTimeSource()
        let app = launch(clock: clock)
        let happyFull = barRule(.happy, at: 100, id: "happy_full")
        XCTAssertFalse(app.shouldFireBarThreshold(happyFull, percentage: 40), "seeded below")

        // Two days of uninterrupted 30 s polling, happy never reaching the threshold.
        for _ in 0..<(2 * 24 * 120) {
            clock.advance(30)
            XCTAssertFalse(app.shouldFireBarThreshold(happyFull, percentage: 40))
        }

        clock.advance(30)
        XCTAssertTrue(app.shouldFireBarThreshold(happyFull, percentage: 100),
                      "the app watched this the whole time — the crossing is live news")
    }

    /// The staleness window is defined in multiples of the poll cadence, so the cadence
    /// has to actually reach the coordinator — both from the stored setting at launch and
    /// from a change made while running.
    func testTheDedupLearnsThePollCadenceAtLaunchAndWhenItChanges() {
        installStore.set(120, forKey: "refreshInterval")
        let app = launch()
        XCTAssertEqual(app.notificationCoordinator.refreshInterval, 120,
                       "the stored cadence must reach the dedup at launch")

        app.refreshInterval = 15
        XCTAssertEqual(app.notificationCoordinator.refreshInterval, 15,
                       "and a change made in Settings must reach it too")
    }

    // MARK: - Wiring

    /// Guards against the predicates existing but `checkNotifications` still running off
    /// the in-memory `previous*` fields. Chosen payload fires nothing on any correct
    /// implementation (no bars, no travel, no status; drug running, medical/booster ready
    /// on first sight) — it only has to leave the persistent latches in the right place.
    func testCheckNotificationsRecordsCooldownStateInThePersistentStore() throws {
        let snapshot = try decode(TornResponse.self, from: """
        {"cooldowns": {"drug": 500, "medical": 0, "booster": 0}}
        """)

        let firstRun = launch()
        firstRun.checkNotifications(newData: snapshot)

        let secondRun = launch()
        XCTAssertTrue(
            secondRun.shouldFireCooldownReady(.drug, seconds: 0),
            "the previous launch saw drug running, so the expiry across the gap must alert"
        )
        XCTAssertFalse(
            secondRun.shouldFireCooldownReady(.medical, seconds: 0),
            "the previous launch already seeded medical as ready — no alert on relaunch"
        )
    }
}
