import Foundation

extension AppState {
    // MARK: - Notifications

    func checkNotifications(newData: TornResponse) {
        if let prev = previousBars, let current = newData.bars {
            checkBarNotification(prevBar: prev.energy, currentBar: current.energy, barType: .energy)
            checkBarNotification(prevBar: prev.nerve, currentBar: current.nerve, barType: .nerve)
            checkBarNotification(prevBar: prev.happy, currentBar: current.happy, barType: .happy)
            checkBarNotification(prevBar: prev.life, currentBar: current.life, barType: .life)
        }

        if let prevCD = previousCooldowns, let currentCD = newData.cooldowns {
            if prevCD.drug > 0 && currentCD.drug == 0 {
                NotificationManager.shared.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended", type: .drugReady)
            }
            if prevCD.medical > 0 && currentCD.medical == 0 {
                NotificationManager.shared.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended", type: .medicalReady)
            }
            if prevCD.booster > 0 && currentCD.booster == 0 {
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

        if let prevStatus = previousStatus, let currentStatus = newData.status {
            if (prevStatus.isInHospital || prevStatus.isInJail) && currentStatus.isOkay {
                NotificationManager.shared.send(title: "Released! 🎉", body: "You are now free", type: .released)
            }
        }
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

    private func checkBarNotification(prevBar: Bar, currentBar: Bar, barType: NotificationRule.BarType) {
        let prevPct = prevBar.percentage
        let currentPct = currentBar.percentage

        for rule in notificationRules where rule.enabled && rule.barType == barType {
            let threshold = Double(rule.threshold)

            if prevPct < threshold && currentPct >= threshold {
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
                NotificationManager.shared.send(title: title, body: "\(barType.rawValue) is now at \(currentBar.current)/\(currentBar.maximum)", type: notificationType)

                if let sound = NotificationSound(rawValue: rule.soundName) {
                    SoundManager.shared.play(sound)
                }
            }
        }
    }

    // MARK: - Updates

    func checkForAppUpdates() {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        Task {
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
