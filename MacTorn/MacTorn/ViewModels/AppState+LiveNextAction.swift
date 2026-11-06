import Foundation
import Combine

extension AppState {
    private static var hiddenNextActionKey: String { "hiddenNextActionCategories" }

    func manageLiveTimer() {
        tick()
        if shouldRunLiveTimer {
            if !liveTimer.isRunning {
                liveTimer.start(every: 1.0, tolerance: 0.1) { [weak self] in self?.tick() }
            }
        }
    }

    private var shouldRunLiveTimer: Bool {
        guard let data = player.data else { return false }
        if let travel = data.travel, travel.isTraveling {
            return travel.remainingSeconds(from: serverFetchTime, now: serverNow) > 0
        }
        if let status = data.status, status.isInHospital || status.isInJail {
            return status.timeRemaining(at: serverNow) > 0
        }
        if let ends = player.cooldownEnds, ends.soonestActive(at: serverNow) != nil { return true }
        return false
    }

    func tick() {
        updateTravelSecondsRemaining()
        let next = computeMenuBarDisplay()
        if next != player.menuBarDisplay {
            player.menuBarDisplay = next
        }
        if !shouldRunLiveTimer {
            liveTimer.stop()
        }
    }

    // Every countdown below reads `serverNow` / `serverFetchTime` (Torn's clock, not the Mac's):
    // `travel.timestamp`, `status.until` and `CooldownEnds.endsAt` are absolute server timestamps, so
    // comparing them against a local `Date()` would leak the machine's skew into the menu bar.
    private func updateTravelSecondsRemaining() {
        let next: Int
        if let travel = player.data?.travel, travel.isTraveling {
            next = travel.remainingSeconds(from: serverFetchTime, now: serverNow)
        } else {
            next = 0
        }
        if next != player.travelSecondsRemaining {
            player.travelSecondsRemaining = next
        }
    }

    private func computeMenuBarDisplay() -> MenuBarDisplay {
        guard let data = player.data else { return .fallbackIcon }
        let now = serverNow

        if let travel = data.travel, travel.isTraveling {
            return .traveling(destination: travel.destination,
                              seconds: travel.remainingSeconds(from: serverFetchTime, now: now))
        }

        if let status = data.status, status.isInHospital {
            let secs = status.timeRemaining(at: now)
            if let travel = data.travel, travel.isAbroad {
                return .hospitalAbroad(destination: travel.destination, seconds: secs)
            }
            return .hospitalAtHome(seconds: secs)
        }

        if let status = data.status, status.isInJail {
            return .jail(seconds: status.timeRemaining(at: now))
        }

        if let ends = player.cooldownEnds,
           let soonest = ends.soonestActive(at: now) {
            return .cooldown(kind: soonest.kind, seconds: soonest.seconds)
        }

        return .fallbackIcon
    }

    func loadHiddenNextActionCategories() {
        guard let raw = defaults.stringArray(forKey: Self.hiddenNextActionKey) else { return }
        hiddenNextActionCategories = Set(raw.compactMap(NextActionCategory.init(rawValue:)))
    }

    func saveHiddenNextActionCategories() {
        defaults.set(hiddenNextActionCategories.map(\.rawValue), forKey: Self.hiddenNextActionKey)
        publishWidgets()
    }

    /// Builds the timeline input. `now` is a *local* instant (the shared clock's); it is converted to
    /// Torn's clock here, and every timestamp in the snapshot is likewise server-absolute, so the whole
    /// timeline runs on one clock.
    func makeNextActionSnapshot(now: Date? = nil) -> NextActionSnapshot {
        let now = now ?? time.now
        let nowUnix = player.serverClock.serverUnix(now)
        var snapshot = NextActionSnapshot(now: nowUnix)

        if let bars = player.data?.bars {
            snapshot.energyFullAt = barFullAt(bars.energy)
            snapshot.nerveFullAt = barFullAt(bars.nerve)
            snapshot.happyFullAt = barFullAt(bars.happy)
            snapshot.lifeFullAt = barFullAt(bars.life)
        }
        if let cd = player.cooldownEnds {
            snapshot.drugReadyAt = cd.drugEndsAt > 0 ? cd.drugEndsAt : nil
            snapshot.medicalReadyAt = cd.medicalEndsAt > 0 ? cd.medicalEndsAt : nil
            snapshot.boosterReadyAt = cd.boosterEndsAt > 0 ? cd.boosterEndsAt : nil
        }
        if let travel = player.data?.travel, travel.isTraveling {
            if let timestamp = travel.timestamp, timestamp > 0 {
                snapshot.travelArrivalAt = timestamp
            } else if let timeLeft = travel.timeLeft, timeLeft > 0 {
                // `time_left` counts from the instant the *server* built the response, so
                // it is anchored on the server's reading of the fetch, not the Mac's.
                snapshot.travelArrivalAt =
                    player.serverClock.serverTimestamp(fetchedAt: player.lastFetchTime, plus: timeLeft)
            }
        }
        if let status = player.data?.status {
            if status.isInHospital { snapshot.hospitalReleaseAt = status.until }
            if status.isInJail { snapshot.jailReleaseAt = status.until }
        }
        if let until = player.education?.current?.until, until > 0 {
            snapshot.educationEndsAt = until
        }
        if let ready = player.organizedCrime?.readyAt, ready > 0 {
            snapshot.ocReadyAt = ready
        }
        if let chain = liveChain, chain.isActive, let timeout = chain.timeout, timeout > 0 {
            snapshot.chainTimeoutAt = timeout
        }
        if companion.enabled.contains(.stocks), companion.errors["user.stocksv2"] == nil,
           let checked = companion.fetchedAt["user.stocksv2"], time.now.timeIntervalSince(checked) < 600 {
            snapshot.stockBonusReady = companion.stocks.contains { $0.bonus.available }
        }
        if let refills = player.refills, !refills.unclaimed.isEmpty {
            snapshot.refillsAvailable = true
        }
        if let virus = player.virus, virus.until > 0 {
            snapshot.virusFinishesAt = virus.until
        }
        return snapshot
    }

    /// `fulltime` is a duration relative to the response, exactly like travel's `time_left`
    /// — so it moves onto the server clock with the fetch anchor. Shifting the timeline's
    /// `now` onto Torn's clock without moving these anchors too would knock the whole skew
    /// off every bar ETA.
    private func barFullAt(_ bar: Bar) -> Int? {
        guard bar.current < bar.maximum, let full = bar.fulltime, full > 0 else { return nil }
        return player.serverClock.serverTimestamp(fetchedAt: player.lastFetchTime, plus: full)
    }

    func nextEvents(now: Date? = nil) -> [NextEvent] {
        NextActionEngine().events(from: makeNextActionSnapshot(now: now), hidden: hiddenNextActionCategories)
    }
}
