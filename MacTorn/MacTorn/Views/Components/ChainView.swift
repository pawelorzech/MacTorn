import SwiftUI

/// The faction chain as one line of the board: hits so far, and how long before it breaks.
struct ChainView: View {
    let chain: Chain
    var fetchTime: Date? = nil
    /// Mac↔Torn skew (issue #46). `chain.timeout` is an absolute server timestamp, so the
    /// tick has to be compared against Torn's now, not the Mac's.
    var serverClock: ServerClock = .synchronized

    /// Which row the chain gets. Pulled out of `body` so the choice is testable.
    enum Mode: Equatable {
        case active
        case cooldown
        /// Hits on the chain but no usable timeout. Shown rather than hidden: a chain in
        /// progress vanishing from the Faction tab reads as "no chain".
        case unavailable
        case hidden
    }

    static func mode(for chain: Chain) -> Mode {
        if chain.isActive { return .active }
        if chain.isOnCooldown { return .cooldown }
        if (chain.current ?? 0) > 0 { return .unavailable }
        return .hidden
    }

    private var hits: String { "\(chain.current ?? 0)/\(chain.maximum ?? 0)" }

    var body: some View {
        switch Self.mode(for: chain) {
        case .active:
            activeRow
        case .cooldown:
            CountdownRow(tone: .idle, title: "Chain", detail: "The faction can't start a new one yet", value: "Cooldown")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chain on cooldown")
                .uiTestID("uitest.chain.cooldown")
        case .unavailable:
            CountdownRow(tone: .alert, title: "Chain", detail: "\(hits) hits", value: "No timer")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chain \(hits), timeout unavailable")
                .uiTestID("uitest.chain.unavailable")
        case .hidden:
            EmptyView()
        }
    }

    private var activeRow: some View {
        TimelineView(.periodic(from: fetchTime ?? .now, by: 1.0)) { context in
            let remaining = chain.timeoutRemaining(at: serverClock.serverNow(context.date))
            let urgency = ChainUrgency(remaining: remaining)

            CountdownRow(
                tone: Self.tone(for: urgency),
                title: "Chain",
                detail: "\(hits) hits, breaks at zero",
                value: TornFormatter.minutesSeconds(remaining)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Chain \(hits), \(urgency.spokenDescription), \(TornFormatter.minutesSeconds(remaining)) remaining"
            )
            .uiTestID("uitest.chain")
        }
    }

    private static func tone(for urgency: ChainUrgency) -> Board.Tone {
        switch urgency {
        case .critical: return .alert
        case .warning: return .counting
        case .healthy: return .ready
        }
    }
}
