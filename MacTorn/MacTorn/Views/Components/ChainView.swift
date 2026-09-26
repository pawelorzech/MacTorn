import SwiftUI

struct ChainView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let chain: Chain
    var fetchTime: Date? = nil
    /// Mac↔Torn skew (issue #46). `chain.timeout` is an absolute server timestamp, so the
    /// tick has to be compared against Torn's now, not the Mac's.
    var serverClock: ServerClock = .synchronized

    /// Which card the chain gets. Pulled out of `body` so the choice is testable.
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

    var body: some View {
        switch Self.mode(for: chain) {
        case .active:
            activeCard
        case .cooldown:
            cooldownCard
        case .unavailable:
            unavailableCard
        case .hidden:
            EmptyView()
        }
    }

    private var activeCard: some View {
        TimelineView(.periodic(from: fetchTime ?? .now, by: 1.0)) { context in
            let remaining = chain.timeoutRemaining(at: serverClock.serverNow(context.date))
            let urgency = ChainUrgency(remaining: remaining)
            let color = Self.color(for: urgency)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(color)
                        .accessibilityHidden(true)
                    Text("Chain: \(chain.current ?? 0)/\(chain.maximum ?? 0)")
                        .font(.caption.bold())

                    Spacer()

                    Text(TornFormatter.minutesSeconds(remaining))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(color)
                }
            }
            .padding(8)
            .background(color.opacity(reduceTransparency ? 0.4 : 0.1))
            .cornerRadius(8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Chain \(chain.current ?? 0)/\(chain.maximum ?? 0), " +
                "\(urgency.spokenDescription), \(TornFormatter.minutesSeconds(remaining)) remaining"
            )
            .uiTestID("uitest.chain")
        }
    }

    private var cooldownCard: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("Chain Cooldown")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chain on cooldown")
        .uiTestID("uitest.chain.cooldown")
    }

    private var unavailableCard: some View {
        HStack {
            Image(systemName: "link")
                .foregroundColor(.red)
                .accessibilityHidden(true)
            Text("Chain: \(chain.current ?? 0)/\(chain.maximum ?? 0)")
                .font(.caption.bold())

            Spacer()

            Text("Unavailable")
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(8)
        .background(Color.red.opacity(reduceTransparency ? 0.4 : 0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Chain \(chain.current ?? 0)/\(chain.maximum ?? 0), timeout unavailable"
        )
        .uiTestID("uitest.chain.unavailable")
    }

    private static func color(for urgency: ChainUrgency) -> Color {
        switch urgency {
        case .critical: return .red
        case .warning: return .orange
        case .healthy: return .green
        }
    }
}
