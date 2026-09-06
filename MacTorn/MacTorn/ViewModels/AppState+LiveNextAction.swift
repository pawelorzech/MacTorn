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
        if let ends = cooldownEnds, ends.soonestActive(at: serverNow) != nil { return true }
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

    // Every countdown below reads `serverNow` / `serverFetchTime` — Torn's clock, not the
    // Mac's (issue #46). All of `travel.timestamp`, `status.until` and `CooldownEnds.endsAt`
    // are absolute server timestamps, so comparing them against a local `Date()` leaked the
    // machine's skew straight into the menu bar.
    private func updateTravelSecondsRemaining() {
        let next: Int
        if let travel = data?.travel, travel.isTraveling {
            next = travel.remainingSeconds(from: serverFetchTime, now: serverNow)
        } else {
            next = 0
        }
        if next != travelSecondsRemaining {
            travelSecondsRemaining = next
        }
    }

    private func computeMenuBarDisplay() -> MenuBarDisplay {
        guard let data = data else { return .fallbackIcon }
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

        if let ends = cooldownEnds,
           let soonest = ends.soonestActive(at: now) {
            return .cooldown(kind: soonest.kind, seconds: soonest.seconds)
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
        publishWidgets()
    }

    /// Builds the timeline input. `now` is a *local* instant (the shared clock's); it is
    /// converted to Torn's clock here, and every timestamp in the snapshot is likewise
    /// server-absolute — so the whole timeline is one consistent clock (issue #46).
    func makeNextActionSnapshot(now: Date = Date()) -> NextActionSnapshot {
        let nowUnix = serverClock.serverUnix(now)
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
                // `time_left` counts from the instant the *server* built the response, so
                // it is anchored on the server's reading of the fetch, not the Mac's.
                snapshot.travelArrivalAt =
                    serverClock.serverTimestamp(fetchedAt: lastFetchTime, plus: timeLeft)
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
        if let chain = liveChain, chain.isActive, let timeout = chain.timeout, timeout > 0 {
            snapshot.chainTimeoutAt = timeout
        }
        if let refills, !refills.unclaimed.isEmpty {
            snapshot.refillsAvailable = true
        }
        if let virus, virus.until > 0 {
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
        return serverClock.serverTimestamp(fetchedAt: lastFetchTime, plus: full)
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
        let suppressions = currentEndpointSuppressions()
        return DiagnosticsReport(
            appVersion: DiagnosticsEnvironment.appVersion,
            build: DiagnosticsEnvironment.build,
            osVersion: DiagnosticsEnvironment.osVersion,
            architecture: DiagnosticsEnvironment.architecture,
            isOnline: connectivity.isConnected,
            notificationPermission: notif,
            lastSuccessfulRefresh: lastUpdated,
            lastErrorSummary: lastErrorClassificationSummary(),
            keyPresent: !apiKey.isEmpty,
            requiredAccessLevel: TornEndpointRegistry.requiredAccessLevel.label,
            requestsLastMinute: pollingCoordinator.requestsInLastMinute,
            requestsLastDay: pollingCoordinator.requestsInLastDay,
            recordsPerDayByCategory: recordsByCategory,
            endpoints: endpointHealth.all,
            suppressedEndpoints: suppressions.labels,
            suppressionExplanations: suppressions.explanations
        )
    }

    /// Every endpoint the gate would refuse right now, with the reason.
    ///
    /// Asked of the gate rather than remembered, so the answer is current: a cool-off that
    /// has already lapsed does not linger in the report as though it were still in force.
    /// The per-minute cap is excluded — it is a momentary condition that says nothing about
    /// an endpoint, and reporting it would make a healthy burst look like a fault.
    func currentEndpointSuppressions() -> (labels: [String: String], explanations: [String: String]) {
        var result: [String: String] = [:]
        var explanations: [String: String] = [:]
        for endpoint in TornEndpointRegistry.all {
            guard let denial = endpointGate.denial(for: endpoint.id,
                                                   keyInfo: keyInfo,
                                                   coordinator: pollingCoordinator),
                  denial != .perMinuteCapReached else { continue }
            result[endpoint.id] = denial.label
            explanations[endpoint.id] = denial.userExplanation
        }
        return (result, explanations)
    }

    /// Coarse, closed-vocabulary summary of the most recent failure — a `TornErrorClass`
    /// raw value, or `nil` — never `errorMsg`'s free text (issue #58: `errorMsg` can be
    /// the raw Torn server message verbatim for `.permanentKey` / `.insufficientPermissions`
    /// / `.temporaryBackend`, and this report is copied to the clipboard and pasted into
    /// public GitHub issues).
    ///
    /// Derived from `endpointHealth`, which already records a classification string per
    /// endpoint on every failure (see `AppState+*Fetch.swift`), rather than from the
    /// user-facing `errorMsg` string. If the most recent failure's `errorClass` isn't one
    /// of the app's own `TornErrorClass` cases (e.g. an ad-hoc `"http404"`), it is mapped
    /// to `.transport` instead of being echoed verbatim, so the result is always a member
    /// of the closed set or `nil`.
    private func lastErrorClassificationSummary() -> String? {
        guard errorMsg != nil else { return nil }
        guard connectivity.isConnected else { return TornErrorClass.offline.rawValue }

        guard let mostRecentFailure = endpointHealth.all
            .filter({ $0.outcome == .error })
            .max(by: { $0.at < $1.at }),
            let errorClass = mostRecentFailure.errorClass
        else {
            return nil
        }

        return TornErrorClass(rawValue: errorClass)?.rawValue ?? TornErrorClass.transport.rawValue
    }
}
