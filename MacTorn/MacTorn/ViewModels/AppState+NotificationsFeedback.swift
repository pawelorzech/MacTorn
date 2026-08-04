import Foundation

extension AppState {
    // MARK: - Notifications

    /// Evaluates every per-poll alert against the *persistent* latches in
    /// `notificationCoordinator` rather than against in-memory `previous*` snapshots.
    ///
    /// The in-memory version dropped every alert whose edge fell across a restart: the
    /// `previous*` fields start `nil` on each launch, so the first poll was always
    /// skipped and the second poll compared two already-satisfied states. A cooldown that
    /// ended, a bar that filled or a hospital stay that expired while MacTorn was closed
    /// simply never announced itself — the product's main job, silently unperformed
    /// (#47). The persistent latches also remember the *cleared* state, which is what
    /// lets the first observation of a key seed silently instead of producing a banner
    /// storm on a fresh install.
    func checkNotifications(newData: TornResponse) {
        if let current = newData.bars {
            checkBarNotifications(bar: current.energy, barType: .energy)
            checkBarNotifications(bar: current.nerve, barType: .nerve)
            checkBarNotifications(bar: current.happy, barType: .happy)
            checkBarNotifications(bar: current.life, barType: .life)
        }

        if let currentCD = newData.cooldowns {
            if shouldFireCooldownReady(.drug, seconds: currentCD.drug) {
                NotificationManager.shared.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended", type: .drugReady)
            }
            if shouldFireCooldownReady(.medical, seconds: currentCD.medical) {
                NotificationManager.shared.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended", type: .medicalReady)
            }
            if shouldFireCooldownReady(.booster, seconds: currentCD.booster) {
                NotificationManager.shared.send(title: "Booster Ready! 🚀", body: "Booster cooldown has ended", type: .boosterReady)
            }
        }

        if let prevTravel = previousTravel, let currentTravel = newData.travel {
            // Just landed
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(title: "Landed!", body: "You have arrived in \(currentTravel.destination ?? "destination")", type: .landed)
                NotificationManager.shared.cancelTravelNotifications()
            }
            // Just started traveling
            if !prevTravel.isTraveling && currentTravel.isTraveling {
                scheduleTravelNotifications(for: currentTravel)
            }
        } else if let currentTravel = newData.travel, currentTravel.isTraveling, previousTravel == nil {
            // First data fetch while traveling
            scheduleTravelNotifications(for: currentTravel)
        }

        // The chain check does NOT live here: chain data arrives on the faction
        // endpoint, not in this user snapshot. It fires from `checkChainNotification()`
        // at the point the faction payload lands. See audit finding C-01.

        if shouldFireReleased(newData.status) {
            NotificationManager.shared.send(title: "Released! 🎉", body: "You are now free", type: .released)
        }
    }

    // MARK: - Persistent alert predicates (#47)
    //
    // Each is a pure function of (persisted latch, this poll's value). They are the
    // headlessly-provable seam for notification behaviour, since
    // `NotificationManager.shared.send` is not injectable.

    /// Whether the "<kind> Ready!" alert should fire for a cooldown now at `seconds`.
    /// Rising edge on running→ready, re-armed when the cooldown restarts. The first ever
    /// observation of the kind seeds silently, so launching into three ready cooldowns is
    /// not three banners.
    func shouldFireCooldownReady(_ kind: CooldownKind, seconds: Int) -> Bool {
        notificationCoordinator.shouldFireOnEdge(
            "cooldown.ready.\(kind.displayName)",
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
            "bar.\(rule.barType.rawValue).\(rule.id).\(rule.threshold)",
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
            "status.released",
            active: status.isOkay,
            seedOnFirstSight: true
        )
    }

    /// Decides whether the "Chain Expiring!" alert should fire on this poll.
    ///
    /// The alert must fire exactly once when the chain enters the danger window
    /// (0 < timeout < `chainWarningThreshold`), NOT on every poll while it stays there
    /// (the previous bug). It re-arms once the chain leaves the window — a member hits
    /// (timeout jumps back up), the chain ends, or the chain drops — so a fresh danger
    /// window alerts again. The latch is persisted, so a relaunch mid-window is silent.
    /// `internal` for `@testable` regression coverage.
    /// Fires the chain-expiring alert. Called from the faction fetch, immediately after
    /// a fresh chain payload is published — chain data enters the system there, so that
    /// is where the edge must be evaluated. Safe to call on every faction poll: the
    /// persistent edge latch inside `chainExpiringShouldFire` collapses repeats.
    func checkChainNotification() {
        guard let chain = liveChain, chainExpiringShouldFire(chain) else { return }
        NotificationManager.shared.send(
            title: "Chain Expiring! ⚠️",
            body: "Chain timeout in \(chain.timeoutRemaining) seconds!",
            type: .chainExpiring
        )
    }

    func chainExpiringShouldFire(_ chain: Chain?) -> Bool {
        let inDanger = (chain?.isActive == true)
            && chain!.timeoutRemaining > 0
            && chain!.timeoutRemaining < Self.chainWarningThreshold
        return notificationCoordinator.shouldFireOnEdge("chain.expiring", active: inDanger)
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
            NotificationManager.shared.send(title: title, body: "\(barType.rawValue) is now at \(bar.current)/\(bar.maximum)", type: notificationType)

            if let sound = NotificationSound(rawValue: rule.soundName) {
                SoundManager.shared.play(sound)
            }
        }
    }

    // MARK: - Updates

    func checkForAppUpdates() {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        updateCheckTask = Task {
            if let release = await updateManager.checkForUpdates(currentVersion: currentVersion) {
                await MainActor.run {
                    self.updateAvailable = release
                }
            }
        }
    }

    // MARK: - Feedback Prompt

    func loadFeedbackState() {
        if let data = defaults.data(forKey: "appFeedbackState"),
           let state = try? JSONDecoder().decode(AppFeedbackState.self, from: data) {
            feedbackState = state
        } else {
            feedbackState = AppFeedbackState(
                firstLaunchDate: Date(),
                hasResponded: false,
                dismissCount: 0,
                lastDismissedDate: nil
            )
            saveFeedbackState()
        }
    }

    func saveFeedbackState() {
        guard let state = feedbackState,
              let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: "appFeedbackState")
    }

    func checkFeedbackPrompt() {
        guard let state = feedbackState else { return }
        guard !state.hasResponded else { return }
        guard state.dismissCount < Self.feedbackThresholds.count else { return }

        // 5-minute cooldown after last dismissal
        if let lastDismissed = state.lastDismissedDate,
           Date().timeIntervalSince(lastDismissed) < 300 {
            return
        }

        let elapsed = Date().timeIntervalSince(state.firstLaunchDate)
        let requiredTime = Self.feedbackThresholds[state.dismissCount]

        if elapsed >= requiredTime {
            showFeedbackPrompt = true
        }
    }

    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    func feedbackRespondedPositive() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
        // Guard prevents tests from spamming the user's browser/mail client.
        guard !Self.isRunningUnderXCTest else { return }
        if let url = URL(string: "https://www.torn.com/forums.php#/p=threads&f=67&t=16532308") {
            BrowserManager.shared.open(url)
        }
    }

    func feedbackRespondedNegative() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
        guard !Self.isRunningUnderXCTest else { return }
        if let url = URL(string: "mailto:pawel@orzech.lol?subject=MacTorn%20Feedback") {
            BrowserManager.shared.open(url)
        }
    }

    func feedbackDismissed() {
        feedbackState?.dismissCount += 1
        feedbackState?.lastDismissedDate = Date()
        showFeedbackPrompt = false
        saveFeedbackState()
    }
}
