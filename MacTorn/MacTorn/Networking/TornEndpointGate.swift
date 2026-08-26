import Foundation

/// Why a request was refused before it ever reached the network.
///
/// Every value here is a *known* reason the call could not have produced data. The gate
/// deliberately never guesses: an unknown key, an unvalidated key, or an endpoint that
/// has simply never failed is always allowed through.
enum TornEndpointDenial: Equatable, Sendable {
    /// The endpoint is in a cool-off after a failure that clears on its own.
    case paused(until: Date, reason: TornErrorClass)
    /// `/key/info` says this key cannot read the selections the endpoint needs.
    case keyLacksSelections([String])
    /// The endpoint only returns faction data and `/key/info` says the owner has no faction.
    case notInFaction
    /// The endpoint's row-based category has used up its client-side daily row budget.
    case rowBudgetExhausted(TornBudgetCategory)
    /// The rolling per-minute request cap would be breached.
    case perMinuteCapReached
    /// No such endpoint in the registry (a programming error, surfaced rather than hidden).
    case unknownEndpoint

    /// A short, non-PII label for logs and the Diagnostics readout.
    var label: String {
        switch self {
        case let .paused(until, reason):
            return "paused(\(reason.rawValue), \(max(0, Int(until.timeIntervalSinceNow)))s)"
        case let .keyLacksSelections(missing):
            return "keyLacksSelections(\(missing.joined(separator: "+")))"
        case .notInFaction: return "notInFaction"
        case let .rowBudgetExhausted(category): return "rowBudgetExhausted(\(category.rawValue))"
        case .perMinuteCapReached: return "perMinuteCapReached"
        case .unknownEndpoint: return "unknownEndpoint"
        }
    }

    /// A sentence a person can act on, for the Diagnostics panel.
    ///
    /// Separate from `label` on purpose. `label` is the machine form that goes into os_log
    /// and the copied report, where a stable closed vocabulary is worth more than prose;
    /// this is what a user reads when they are trying to work out why a tab is empty.
    var userExplanation: String {
        switch self {
        case let .paused(until, reason):
            let seconds = max(0, Int(until.timeIntervalSinceNow))
            let when = seconds >= 90 ? "in \(seconds / 60) min" : "in \(seconds)s"
            switch reason {
            case .dailyRowLimit: return "Daily read limit reached — retrying \(when)"
            case .ipBlocked: return "Torn blocked this network — retrying \(when)"
            case .temporaryKey: return "Torn is refusing the key for now — retrying \(when)"
            case .rateLimit: return "Backing off after too many requests — retrying \(when)"
            default: return "Retrying \(when)"
            }
        case let .keyLacksSelections(missing):
            return "Your key cannot read: \(missing.joined(separator: ", "))"
        case .notInFaction:
            return "You are not in a faction"
        case .rowBudgetExhausted:
            return "This feed used up its daily allowance"
        case .perMinuteCapReached:
            return "Waiting for the per-minute request budget"
        case .unknownEndpoint:
            return "Unknown endpoint"
        }
    }

    /// Whether this denial is expected to lift without the user doing anything. Used to
    /// decide if the reason is worth showing in the UI at all.
    var isSelfHealing: Bool {
        switch self {
        case .paused, .rowBudgetExhausted, .perMinuteCapReached: return true
        case .keyLacksSelections, .notInFaction, .unknownEndpoint: return false
        }
    }
}

/// Decides, per endpoint, whether MacTorn is allowed to spend a request right now.
///
/// This exists because the app already *knew* the answer and asked anyway. `/key/info`
/// reports exactly which selections a key can read and whether its owner is in a faction,
/// and `PollingCoordinator` already measures the row budget — but before this type, every
/// fetch fired regardless, so a Public-Only key or a factionless player spent a request on
/// `faction/basic` every thirty seconds, forever, purely to be told "no". The failures were
/// invisible too: each one logged a warning and moved on.
///
/// The gate is deliberately conservative in one direction only. It refuses a call solely
/// on a fact it has (a validated key that lacks the selection, a live cool-off, an
/// exhausted budget) and always allows a call it cannot rule out — an unvalidated key
/// never blocks anything.
@MainActor
final class TornEndpointGate {
    private let time: TimeSource
    /// Endpoint id → the instant it may be tried again.
    private var pausedUntil: [String: (deadline: Date, reason: TornErrorClass)] = [:]

    init(time: TimeSource = SystemTimeSource()) {
        self.time = time
    }

    // MARK: - Asking

    /// The reason `endpointID` may not be called now, or `nil` when it may.
    ///
    /// - Parameters:
    ///   - keyInfo: the validated `/key/info` result, or `nil` when the key has never been
    ///     validated. `nil` disables the key-derived checks rather than blocking.
    ///   - coordinator: supplies the per-minute cap and the per-category row budget.
    func denial(for endpointID: String,
                keyInfo: TornKeyInfo?,
                coordinator: PollingCoordinator) -> TornEndpointDenial? {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID) else {
            return .unknownEndpoint
        }

        if let entry = pausedUntil[endpointID] {
            if time.now < entry.deadline {
                return .paused(until: entry.deadline, reason: entry.reason)
            }
            pausedUntil[endpointID] = nil
        }

        if let keyInfo {
            if endpoint.requiresFaction, keyInfo.user.factionId == nil {
                return .notInFaction
            }
            // Only a *total* miss is a denial. A key that can read some of an endpoint's
            // selections still gets the call — `TornEndpoint.url(granted:)` trims the
            // request down to the readable ones, so a Minimal-access key keeps its bars
            // and cooldowns instead of losing the whole poll to one forbidden selection.
            if !endpoint.selections.isEmpty {
                let granted = Set(keyInfo.selections.names(for: KeyValidator.category(for: endpoint)))
                if endpoint.resolvedSelections(granted: granted).isEmpty {
                    return .keyLacksSelections(endpoint.selections)
                }
            }
        }

        // The row budget is a client-side guard rail set well below Torn's 50,000/day
        // cap. Checking it here is what makes it a limit rather than a readout — it used
        // to be measured and then never consulted, so the only thing that actually
        // stopped a runaway row source was Torn answering with error 14.
        if endpoint.recordsPerCall > 0, !coordinator.isWithinRecordBudget(endpoint.budget) {
            return .rowBudgetExhausted(endpoint.budget)
        }

        if !coordinator.canMakeRequest() {
            return .perMinuteCapReached
        }

        return nil
    }

    // MARK: - Telling

    /// Records a failure so the affected endpoint backs off for as long as that class of
    /// failure warrants. Errors with no `pauseDuration` (transport blips, backend hiccups)
    /// deliberately leave no mark: the next poll tick is already the retry.
    func note(_ error: TornAPIError, for endpointID: String) {
        guard let pause = error.pauseDuration else { return }
        let deadline = time.now.addingTimeInterval(pause)
        // Never shorten an existing cool-off — a rate-limit blip arriving during an
        // hour-long IP block must not hand the block an early release.
        if let existing = pausedUntil[endpointID], existing.deadline > deadline { return }
        pausedUntil[endpointID] = (deadline, error.classification)
    }

    /// Applies a cool-off to *every* registered endpoint.
    ///
    /// Some failures are properties of the key or the network, not of the endpoint that
    /// happened to hit them: an IP block and a suspended key refuse everything equally.
    /// Pausing only the endpoint that noticed would leave the other eight to keep firing
    /// into the same wall — and, for an IP block, to keep earning it.
    func noteAccountWideFailure(_ error: TornAPIError) {
        guard let pause = error.pauseDuration else { return }
        for endpoint in TornEndpointRegistry.all {
            self.pause(endpoint.id, for: pause, reason: error.classification)
        }
    }

    /// Pauses one endpoint for a fixed interval, for callers that decide a cool-off
    /// without an error to hand over.
    func pause(_ endpointID: String, for interval: TimeInterval, reason: TornErrorClass) {
        let deadline = time.now.addingTimeInterval(interval)
        if let existing = pausedUntil[endpointID], existing.deadline > deadline { return }
        pausedUntil[endpointID] = (deadline, reason)
    }

    /// Whether `endpointID` is currently in a cool-off.
    func isPaused(_ endpointID: String) -> Bool {
        guard let entry = pausedUntil[endpointID] else { return false }
        if time.now >= entry.deadline {
            pausedUntil[endpointID] = nil
            return false
        }
        return true
    }

    /// Live cool-offs, for the Diagnostics readout. Expired entries are pruned first.
    func activePauses() -> [String: Date] {
        let now = time.now
        pausedUntil = pausedUntil.filter { $0.value.deadline > now }
        return pausedUntil.mapValues(\.deadline)
    }

    /// Forgets every cool-off. Called when the account changes — the new key deserves a
    /// clean slate, and a pause earned by the previous key says nothing about this one.
    func reset() {
        pausedUntil.removeAll(keepingCapacity: true)
    }
}
