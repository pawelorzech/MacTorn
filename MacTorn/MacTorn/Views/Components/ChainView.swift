import SwiftUI

struct ChainView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let chain: Chain
    let fetchTime: Date
    /// Mac↔Torn skew (issue #46). `chain.timeout` is an absolute server timestamp, so the
    /// tick has to be compared against Torn's now, not the Mac's.
    var serverClock: ServerClock = .synchronized

    var body: some View {
        if chain.isActive {
            TimelineView(.periodic(from: fetchTime, by: 1.0)) { context in
                let remaining = chain.timeoutRemaining(at: serverClock.serverNow(context.date))
                let color = timeoutColor(for: remaining)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(color)
                            .accessibilityHidden(true)
                        Text("Chain: \(chain.current ?? 0)/\(chain.maximum ?? 0)")
                            .font(.caption.bold())

                        Spacer()

                        Text(formatTime(remaining))
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
                    "\(urgencyDescription(for: remaining)), \(formatTime(remaining)) remaining"
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

    private func timeoutColor(for remaining: Int) -> Color {
        if remaining < 60 {
            return .red
        } else if remaining < 180 {
            return .orange
        }
        return .green
    }

    /// Puts the colour-only urgency bucket (red/orange/green) into words so
    /// VoiceOver users get the same "how worried should I be" signal sighted
    /// users read from the badge colour alone.
    private func urgencyDescription(for remaining: Int) -> String {
        if remaining < 60 {
            return "critical"
        } else if remaining < 180 {
            return "warning"
        }
        return "healthy"
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
