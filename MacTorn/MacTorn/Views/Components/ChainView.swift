import SwiftUI

struct ChainView: View {
    let chain: Chain
    
    var body: some View {
        if chain.isActive {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(timeoutColor)
                    Text("Chain: \(chain.current)/\(chain.maximum)")
                        .font(.caption.bold())
                    
                    Spacer()
                    
                    Text(formatTime(chain.timeoutRemaining))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(timeoutColor)
                }
            }
            .padding(8)
            .background(timeoutColor.opacity(0.1))
            .cornerRadius(8)
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
    
    private var timeoutColor: Color {
        if chain.timeoutRemaining < 60 {
            return .red
        } else if chain.timeoutRemaining < 180 {
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
