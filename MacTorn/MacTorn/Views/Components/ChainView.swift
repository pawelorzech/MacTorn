import SwiftUI

struct ChainView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let chain: Chain
    var fetchTime: Date? = nil
    /// Mac↔Torn skew (issue #46). `chain.timeout` is an absolute server timestamp, so the
    /// tick has to be compared against Torn's now, not the Mac's.
    var serverClock: ServerClock = .synchronized

    var body: some View {
        if chain.isActive {
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
        } else if chain.isOnCooldown {
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
    }

    private static func color(for urgency: ChainUrgency) -> Color {
        switch urgency {
        case .critical: return .red
        case .warning: return .orange
        case .healthy: return .green
        }
    }
}
