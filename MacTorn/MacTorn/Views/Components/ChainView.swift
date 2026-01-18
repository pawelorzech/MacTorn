import SwiftUI

struct ChainView: View {
    let chain: Chain
    let fetchTime: Date

    var body: some View {
        if chain.isActive {
            TimelineView(.periodic(from: fetchTime, by: 1.0)) { context in
                let remaining = max(0, (chain.timeout ?? 0) - Int(context.date.timeIntervalSince1970))
                let color = timeoutColor(for: remaining)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(color)
                        Text("Chain: \(chain.current ?? 0)/\(chain.maximum ?? 0)")
                            .font(.caption.bold())

                        Spacer()

                        Text(formatTime(remaining))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(color)
                    }
                }
                .padding(8)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            }
        } else if chain.isOnCooldown {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.gray)
                Text("Chain Cooldown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
