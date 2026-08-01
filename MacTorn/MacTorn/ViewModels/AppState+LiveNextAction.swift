import Foundation
import Combine

extension AppState {
    private static var hiddenNextActionKey: String { "hiddenNextActionCategories" }

    // MARK: - Live Timer

    func manageLiveTimer() {
        tick()
        if shouldRunLiveTimer {
            if liveTimerCancellable == nil {
                startLiveTimer()
            }
        } else {
            stopLiveTimer()
        }
    }

    private var shouldRunLiveTimer: Bool {
        guard let data = data else { return false }
        if let travel = data.travel, travel.isTraveling { return true }
        if let status = data.status, status.isInHospital || status.isInJail { return true }
        if let ends = cooldownEnds, ends.soonestActive() != nil { return true }
        return false
    }

    private func startLiveTimer() {
        liveTimerCancellable?.cancel()

        liveTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopLiveTimer() {
        liveTimerCancellable?.cancel()
        liveTimerCancellable = nil
        travelSecondsRemaining = 0
        menuBarDisplay = computeMenuBarDisplay()
    }

    private func tick() {
        updateTravelSecondsRemaining()
        let next = computeMenuBarDisplay()
        if next != menuBarDisplay {
            menuBarDisplay = next
        }
    }

    private func updateTravelSecondsRemaining() {
        let next: Int
        if let travel = data?.travel, travel.isTraveling {
            next = travel.remainingSeconds(from: lastFetchTime)
        } else {
            next = 0
        }
        if next != travelSecondsRemaining {
            travelSecondsRemaining = next
        }
    }

    private func computeMenuBarDisplay() -> MenuBarDisplay {
        guard let data = data else { return .fallbackIcon }

        if let travel = data.travel, travel.isTraveling {
            let flag = TornDestination.flag(for: travel.destination ?? "?")
            return .traveling(flag: flag, seconds: travel.remainingSeconds(from: lastFetchTime))
        }

        if let status = data.status, status.isInHospital {
            let secs = status.timeRemaining
            if let travel = data.travel, travel.isAbroad {
                let flag = TornDestination.flag(for: travel.destination ?? "?")
                return .hospitalAbroad(flag: flag, seconds: secs)
            }
            return .hospitalAtHome(seconds: secs)
        }

        if let status = data.status, status.isInJail {
            return .jail(seconds: status.timeRemaining)
        }

        if let ends = cooldownEnds,
           let soonest = ends.soonestActive() {
            return .cooldown(emoji: soonest.kind.emoji, seconds: soonest.seconds)
        }

        return .fallbackIcon
    }

    // MARK: - Next Action

    func loadHiddenNextActionCategories() {
        guard let raw = defaults.stringArray(forKey: Self.hiddenNextActionKey) else { return }
        hiddenNextActionCategories = Set(raw.compactMap(NextActionCategory.init(rawValue:)))
    }

    func saveHiddenNextActionCategories() {
        defaults.set(hiddenNextActionCategories.map(\.rawValue), forKey: Self.hiddenNextActionKey)
    }

    func makeNextActionSnapshot(now: Date = Date()) -> NextActionSnapshot {
        let nowUnix = Int(now.timeIntervalSince1970)
        var snapshot = NextActionSnapshot(now: nowUnix)

        if let bars = data?.bars {
            snapshot.energyFullAt = barFullAt(bars.energy)
            snapshot.nerveFullAt = barFullAt(bars.nerve)
            snapshot.happyFullAt = barFullAt(bars.happy)
            snapshot.lifeFullAt = barFullAt(bars.life)
        }
        if let cd = cooldownEnds {
            snapshot.drugReadyAt = cd.drugEndsAt > 0 ? cd.drugEndsAt : nil
            snapshot.medicalReadyAt = cd.medicalEndsAt > 0 ? cd.medicalEndsAt : nil
            snapshot.boosterReadyAt = cd.boosterEndsAt > 0 ? cd.boosterEndsAt : nil
        }
        if let travel = data?.travel, travel.isTraveling {
            if let timestamp = travel.timestamp, timestamp > 0 {
                snapshot.travelArrivalAt = timestamp
            } else if let timeLeft = travel.timeLeft, timeLeft > 0 {
                snapshot.travelArrivalAt = Int(lastFetchTime.timeIntervalSince1970) + timeLeft
            }
        }
        if let status = data?.status {
            if status.isInHospital { snapshot.hospitalReleaseAt = status.until }
            if status.isInJail { snapshot.jailReleaseAt = status.until }
        }
        if let until = education?.current?.until, until > 0 {
            snapshot.educationEndsAt = until
        }
        if let ready = organizedCrime?.readyAt, ready > 0 {
            snapshot.ocReadyAt = ready
        }
        if let chain = data?.chain, chain.isActive, let timeout = chain.timeout, timeout > 0 {
            snapshot.chainTimeoutAt = timeout
        }
        if let refills, !refills.unclaimed.isEmpty {
            snapshot.refillsAvailable = true
        }
        return snapshot
    }

    private func barFullAt(_ bar: Bar) -> Int? {
        guard bar.current < bar.maximum, let full = bar.fulltime, full > 0 else { return nil }
        return Int(lastFetchTime.timeIntervalSince1970) + full
    }

    func nextEvents(now: Date = Date()) -> [NextEvent] {
        NextActionEngine().events(from: makeNextActionSnapshot(now: now), hidden: hiddenNextActionCategories)
    }

    func makeDiagnosticsReport() async -> DiagnosticsReport {
        let notif = await NotificationManager.shared.authorizationStatusDescription()
        var recordsByCategory: [String: Int] = [:]
        for (category, count) in pollingCoordinator.recordsPerDayByCategory() {
            recordsByCategory[category.rawValue] = count
        }
        return DiagnosticsReport(
            appVersion: DiagnosticsEnvironment.appVersion,
            build: DiagnosticsEnvironment.build,
            osVersion: DiagnosticsEnvironment.osVersion,
            architecture: DiagnosticsEnvironment.architecture,
            isOnline: connectivity.isConnected,
            notificationPermission: notif,
            lastSuccessfulRefresh: lastUpdated,
            lastErrorSummary: errorMsg,
            keyPresent: !apiKey.isEmpty,
            requiredAccessLevel: TornEndpointRegistry.requiredAccessLevel.label,
            requestsLastMinute: pollingCoordinator.requestsInLastMinute,
            requestsLastDay: pollingCoordinator.requestsInLastDay,
            recordsPerDayByCategory: recordsByCategory,
            endpoints: endpointHealth.all
        )
    }
}
