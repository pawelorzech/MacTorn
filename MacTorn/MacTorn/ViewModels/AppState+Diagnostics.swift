import Foundation

extension AppState {
    func makeDiagnosticsReport() async -> DiagnosticsReport {
        let notif = await notifier.authorizationStatusDescription()
        var recordsByCategory: [String: Int] = [:]
        for (category, count) in requester.budget.recordsPerDayByCategory() {
            recordsByCategory[category.rawValue] = count
        }
        let suppressions = currentEndpointSuppressions()
        return DiagnosticsReport(
            appVersion: BuildInfo.appVersion,
            build: BuildInfo.build,
            osVersion: BuildInfo.osVersion,
            architecture: BuildInfo.architecture,
            isOnline: connectivity.isConnected,
            notificationPermission: notif,
            lastSuccessfulRefresh: player.lastUpdated,
            lastErrorSummary: lastErrorClassificationSummary(),
            keyPresent: !apiKey.isEmpty,
            requiredAccessLevel: TornEndpointRegistry.requiredAccessLevel.label,
            requestsLastMinute: requester.budget.requestsInLastMinute,
            requestsLastDay: requester.budget.requestsInLastDay,
            recordsPerDayByCategory: recordsByCategory,
            endpoints: requester.health.all,
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
            guard let denial = requester.denial(endpoint.id),
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

        return requester.health.all
            .filter { $0.outcome == .error }
            .max { $0.at < $1.at }?
            .errorClass?.rawValue
    }
}

extension AppState {
    /// Resolves a module's visible status from the same PII-safe endpoint health that
    /// powers Diagnostics. `staleAfter` is module-specific because activity/faction
    /// endpoints intentionally poll more slowly than live bars.
    func presentationState(endpointIDs: [String],
                           hasContent: Bool,
                           staleAfter: TimeInterval,
                           requiredUserSelections: [String] = [],
                           rowHealth: [EndpointHealth]? = nil) -> ModulePresentationState {
        let health = rowHealth ?? endpointIDs.compactMap { requester.health.latest(for: $0) }

        // A permanent key failure is account-wide. The failing request may be
        // `key.info`, while a feature screen observes only its own endpoint (for
        // example `user.fast`). Keep every module's recovery action honest: retrying
        // cannot help until the key is changed, so route the user to Settings.
        if keyHalted {
            return ModulePresentationState(
                kind: .permission,
                hasContent: hasContent,
                updatedAt: health.compactMap(\.dataUpdatedAt).max(),
                recovery: .settings
            )
        }

        if let keyInfo = requester.keyInfo,
           !Set(requiredUserSelections).isSubset(of: Set(keyInfo.selections.user)) {
            return ModulePresentationState(kind: .permission, hasContent: hasContent,
                                           updatedAt: health.compactMap(\.dataUpdatedAt).max(), recovery: .settings)
        }

        // A suppressed endpoint has no failed response to put in health. Show known
        // permission denials on the module itself rather than an endless "No data yet".
        if !hasContent {
            for id in endpointIDs {
                switch requester.denial(id) {
                case .keyLacksSelections, .keyAccessLevelTooLow, .factionAPIAccessDisabled:
                    return ModulePresentationState(kind: .permission, hasContent: false,
                                                   updatedAt: nil, recovery: .settings)
                default: break
                }
            }
        }

        return ModulePresentationState.resolve(
            health: health,
            hasContent: hasContent,
            isLoading: isLoading || awaitingFirstKeyInfo,
            isOffline: !connectivity.isConnected,
            fallbackError: errorMsg,
            now: time.now,
            staleAfter: staleAfter
        )
    }

    var watchlistPresentationState: ModulePresentationState {
        presentationState(endpointIDs: ["market.item"],
                          hasContent: watchlistItems.contains { $0.lastUpdated != nil }, staleAfter: 360,
                          rowHealth: watchlistItems.map {
            EndpointHealth(endpointID: "market.item", outcome: $0.error != nil ? .error : $0.lastUpdated == nil ? .pending : .ok,
                           latencyMs: 0, responseBytes: 0, at: $0.lastUpdated ?? time.now,
                           errorClass: nil, lastSuccessfulAt: $0.lastUpdated)
        })
    }

    var forumPresentationState: ModulePresentationState {
        presentationState(endpointIDs: ["forum.thread"],
                          hasContent: watchedThreads.contains { $0.lastChecked != nil },
                          staleAfter: TimeInterval(max(forumWatchConfig.pollingIntervalSeconds, ForumWatchConfig.defaultPollingInterval)) + 30,
                          rowHealth: watchedThreads.map {
            EndpointHealth(endpointID: "forum.thread", outcome: $0.error != nil ? .error : $0.lastChecked == nil ? .pending : .ok,
                           latencyMs: 0, responseBytes: 0, at: $0.lastChecked ?? time.now,
                           errorClass: nil, lastSuccessfulAt: $0.lastChecked)
        })
    }
}

/// Which endpoints feed each tab, how old their data may get before the tab reads as
/// stale, and which key selections the tab needs. Activity/faction endpoints poll more
/// slowly than the live bars, hence the longer windows.
private struct ModuleFacts {
    let endpointIDs: [String]
    let staleAfter: TimeInterval
    var requiredUserSelections: [String] = []

    static let status = ModuleFacts(endpointIDs: ["user.fast", "user.v2", "user.activity"], staleAfter: 120)
    static let travel = ModuleFacts(endpointIDs: ["user.fast"], staleAfter: 120)
    static let money = ModuleFacts(endpointIDs: ["user.fast"], staleAfter: 120, requiredUserSelections: ["money"])
    static let properties = ModuleFacts(endpointIDs: ["user.fast"], staleAfter: 120, requiredUserSelections: ["properties"])
    static let stocks = ModuleFacts(endpointIDs: ["user.fast"], staleAfter: 120, requiredUserSelections: ["stocks"])
    static let attacks = ModuleFacts(endpointIDs: ["user.fast", "user.activity"], staleAfter: 360)
    static let faction = ModuleFacts(
        endpointIDs: ["faction.basic", "faction.rankedwars", "faction.news", "user.v2"], staleAfter: 360)
}

extension AppState {
    /// Presentation state for a tab whose facts are fixed. The Watchlist and Forums tabs
    /// derive theirs from per-row health instead (`watchlistPresentationState`,
    /// `forumPresentationState`) and ignore `hasContent`.
    func presentationState(for tab: AppTab, hasContent: Bool) -> ModulePresentationState {
        let facts: ModuleFacts
        switch tab {
        case .status: facts = .status
        case .travel: facts = .travel
        case .money: facts = .money
        case .properties: facts = .properties
        case .stocks: facts = .stocks
        case .attacks: facts = .attacks
        case .faction: facts = .faction
        case .watchlist: return watchlistPresentationState
        case .forums: return forumPresentationState
        }
        return presentationState(endpointIDs: facts.endpointIDs,
                                 hasContent: hasContent,
                                 staleAfter: facts.staleAfter,
                                 requiredUserSelections: facts.requiredUserSelections)
    }
}
