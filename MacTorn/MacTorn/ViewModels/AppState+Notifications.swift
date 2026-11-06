import Foundation

extension AppState {
    /// Evaluates every per-poll alert against the *persistent* latches in `notificationCoordinator`
    /// rather than in-memory `previous*` snapshots. Those start `nil` on each launch, so an edge that
    /// fell across a restart (a cooldown ending, a bar filling or a hospital stay expiring while
    /// MacTorn was closed) would never announce. The persistent latches also remember the *cleared*
    /// state, so the first observation of a key seeds silently instead of producing a banner storm on a
    /// fresh install, and they remember *when* they were written, so a pre-quit state older than the
    /// coordinator's staleness window seeds too.
    func checkNotifications(newData: TornResponse) {
        // ~9 latch predicates are evaluated below; the batch collapses their persistence into one
        // UserDefaults write instead of one per predicate.
        notificationCoordinator.batched {
            evaluateNotifications(newData: newData)
        }
    }

    private func evaluateNotifications(newData: TornResponse) {
        if let current = newData.bars {
            checkBarNotifications(bar: current.energy, barType: .energy)
            checkBarNotifications(bar: current.nerve, barType: .nerve)
            checkBarNotifications(bar: current.happy, barType: .happy)
            checkBarNotifications(bar: current.life, barType: .life)
        }

        if let currentCD = newData.cooldowns {
            if shouldFireCooldownReady(.drug, seconds: currentCD.drug) {
                notifier.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended", type: .drugReady)
            }
            if shouldFireCooldownReady(.medical, seconds: currentCD.medical) {
                notifier.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended", type: .medicalReady)
            }
            if shouldFireCooldownReady(.booster, seconds: currentCD.booster) {
                notifier.send(title: "Booster Ready! 🚀", body: "Booster cooldown has ended", type: .boosterReady)
            }
        }

        if let prevTravel = player.previousTravel, let currentTravel = newData.travel {
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                notifier.send(title: "Landed!", body: "You have arrived in \(currentTravel.destination ?? "destination")", type: .landed)
                cancelLandingAlerts()
            }
            if !prevTravel.isTraveling && currentTravel.isTraveling {
                scheduleTravelNotifications(for: currentTravel)
            }
        } else if let currentTravel = newData.travel, currentTravel.isTraveling, player.previousTravel == nil {
            // First data fetch while traveling
            scheduleTravelNotifications(for: currentTravel)
        }

        // The chain check does NOT live here: chain data arrives on the faction endpoint, not in this
        // user snapshot. It fires from `checkChainNotification()` when the faction payload lands.

        if shouldFireReleased(newData.status) {
            notifier.send(title: "Released! 🎉", body: "You are now free", type: .released)
        }
    }

    // MARK: - Persistent alert predicates
    //
    // Each is a pure function of (persisted latch, this poll's value), which keeps notification
    // behaviour provable without delivering anything.

    /// Whether the "<kind> Ready!" alert should fire for a cooldown now at `seconds`.
    /// Rising edge on running→ready, re-armed when the cooldown restarts. The first ever
    /// observation of the kind seeds silently, so launching into three ready cooldowns is
    /// not three banners.
    func shouldFireCooldownReady(_ kind: CooldownKind, seconds: Int) -> Bool {
        notificationCoordinator.shouldFireOnEdge(
            AlertKey.cooldownReady(kind),
            active: seconds <= 0,
            seedOnFirstSight: true
        )
    }

    /// Whether `rule` should fire for a bar now at `percentage`. Rising edge on crossing
    /// the rule's threshold, re-armed when the bar drops back below it. Latched per rule,
    /// so two rules on the same bar (80% and 100%) announce independently, and a rule
    /// added while its threshold is already met seeds instead of firing at once.
    func shouldFireBarThreshold(_ rule: NotificationRule, percentage: Double) -> Bool {
        guard rule.enabled else { return false }
        return notificationCoordinator.shouldFireOnEdge(
            AlertKey.bar(rule),
            active: percentage >= Double(rule.threshold),
            seedOnFirstSight: true
        )
    }

    /// Whether the "Released!" alert should fire for this status. Rising edge on
    /// confinement→okay. A `nil` status is a gap in the data, not a release: it neither
    /// fires nor touches the latch, so a poll that fails mid-hospital-stay does not
    /// destroy the pending edge. States that are neither okay nor confinement (travelling,
    /// abroad) are likewise inert — landing back home is not a jail release.
    func shouldFireReleased(_ status: Status?) -> Bool {
        guard let status else { return false }
        let confined = status.isInHospital || status.isInJail
        guard status.isOkay || confined else { return false }
        return notificationCoordinator.shouldFireOnEdge(
            AlertKey.released,
            active: status.isOkay,
            seedOnFirstSight: true
        )
    }

    /// Fires the chain-expiring alert. Called from the faction fetch right after a fresh chain payload
    /// is published, since chain data enters the system there. Safe to call on every faction poll: the
    /// persistent edge latch inside `chainExpiringShouldFire` collapses repeats.
    func checkChainNotification() {
        guard let chain = liveChain, chainExpiringShouldFire(chain) else { return }
        notifier.send(
            title: "Chain Expiring! ⚠️",
            body: "Chain timeout in \(chain.timeoutRemaining(at: serverNow)) seconds!",
            type: .chainExpiring
        )
    }

    /// Decides whether the "Chain Expiring!" alert should fire on this poll. It fires exactly once when
    /// the chain enters the danger window (0 < timeout < `chainWarningThreshold`) and re-arms once the
    /// chain leaves it (a hit raises the timeout, or the chain ends or drops), so a fresh window alerts
    /// again. The latch is persisted, so a relaunch mid-window is silent. `timeout` is an absolute
    /// server timestamp, so the window is measured on Torn's clock. `internal` for `@testable` coverage.
    func chainExpiringShouldFire(_ chain: Chain?) -> Bool {
        let remaining = chain?.timeoutRemaining(at: serverNow) ?? 0
        let inDanger = (chain?.isActive == true)
            && remaining > 0
            && remaining < Self.chainWarningThreshold
        return notificationCoordinator.shouldFireOnEdge(AlertKey.chainExpiring, active: inDanger)
    }

    private func checkBarNotifications(bar: Bar, barType: NotificationRule.BarType) {
        for rule in notificationRules where rule.barType == barType {
            guard shouldFireBarThreshold(rule, percentage: bar.percentage) else { continue }

            let title: String
            let notificationType: NotificationType
            switch barType {
            case .energy:
                title = "Energy \(rule.threshold)%! ⚡️"
                notificationType = .energy
            case .nerve:
                title = "Nerve \(rule.threshold)%! 💪"
                notificationType = .nerve
            case .happy:
                title = "Happy \(rule.threshold)%! 😊"
                notificationType = .happy
            case .life:
                title = "Life \(rule.threshold)%! ❤️"
                notificationType = .life
            }
            notifier.send(title: title, body: "\(barType.rawValue) is now at \(bar.current)/\(bar.maximum)", type: notificationType)

            if let sound = NotificationSound(rawValue: rule.soundName) {
                notifier.play(sound)
            }
        }
    }
}

extension AppState {
    private static var notificationRulesKey: String { "notificationRules" }
    private static var travelSettingsKey: String { "travelNotificationSettings" }

    func loadNotificationRules() {
        if let rules = defaults.decoded([NotificationRule].self, forKey: Self.notificationRulesKey) {
            notificationRules = rules
        } else {
            notificationRules = NotificationRule.defaults
            saveNotificationRules()
        }
    }

    func saveNotificationRules() {
        defaults.setEncoded(notificationRules, forKey: Self.notificationRulesKey)
    }

    func loadTravelNotificationSettings() {
        if let settings = defaults.decoded([TravelNotificationSetting].self, forKey: Self.travelSettingsKey) {
            travelNotificationSettings = settings
        } else {
            travelNotificationSettings = TravelNotificationSetting.defaults
            saveTravelNotificationSettings()
        }
    }

    func saveTravelNotificationSettings() {
        defaults.setEncoded(travelNotificationSettings, forKey: Self.travelSettingsKey)
    }

    func updateTravelNotificationSetting(_ setting: TravelNotificationSetting) {
        if let index = travelNotificationSettings.firstIndex(where: { $0.id == setting.id }) {
            travelNotificationSettings[index] = setting
            saveTravelNotificationSettings()
            if let travel = player.data?.travel, travel.isTraveling {
                scheduleTravelNotifications(for: travel)
            }
        }
    }

    func cancelLandingAlerts() {
        notifier.cancelPending(identifiers: TravelNotificationSetting.defaults.map(\.notificationIdentifier))
    }

    func scheduleTravelNotifications(for travel: Travel) {
        cancelLandingAlerts()

        // `travel.timestamp` is an absolute *server* timestamp, but a scheduled local notification fires
        // on the *Mac's* clock, so convert back through the skew.
        guard travel.isTraveling, let arrival = travel.timestamp, arrival > 0 else { return }
        let arrivalDate = player.serverClock.localDate(forServerTimestamp: arrival)

        for setting in travelNotificationSettings where setting.enabled {
            let notificationDate = arrivalDate.addingTimeInterval(-Double(setting.secondsBefore))

            if notificationDate > time.now {
                let identifier = setting.notificationIdentifier
                let timeText: String
                if setting.secondsBefore >= 60 {
                    timeText = "\(setting.secondsBefore / 60) minute\(setting.secondsBefore >= 120 ? "s" : "")"
                } else {
                    timeText = "\(setting.secondsBefore) seconds"
                }

                notifier.schedule(
                    title: "Landing Soon!",
                    body: "You will arrive in \(travel.destination ?? "your destination") in \(timeText)",
                    type: .travelApproaching,
                    at: notificationDate,
                    identifier: identifier
                )
            }
        }
    }
}
