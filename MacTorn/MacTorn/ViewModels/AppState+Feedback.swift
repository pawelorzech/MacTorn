import Foundation

extension AppState {
    func checkForAppUpdates() {
        updateCheckTask = Task {
            if let release = await updateManager.checkForUpdates(currentVersion: BuildInfo.appVersion) {
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
                firstLaunchDate: time.now,
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
           time.now.timeIntervalSince(lastDismissed) < 300 {
            return
        }

        let elapsed = time.now.timeIntervalSince(state.firstLaunchDate)
        let requiredTime = Self.feedbackThresholds[state.dismissCount]

        if elapsed >= requiredTime {
            showFeedbackPrompt = true
        }
    }

    func feedbackResponded() {
        feedbackState?.hasResponded = true
        showFeedbackPrompt = false
        saveFeedbackState()
    }

    func feedbackDismissed() {
        feedbackState?.dismissCount += 1
        feedbackState?.lastDismissedDate = time.now
        showFeedbackPrompt = false
        saveFeedbackState()
    }
}
