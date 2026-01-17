import SwiftUI

struct StatusBadgesView: View {
    let status: Status
    
    var body: some View {
        if !status.isOkay {
            HStack(spacing: 8) {
                if status.isInHospital {
                    HStack(spacing: 4) {
                        Image(systemName: "cross.circle.fill")
                            .foregroundColor(.red)
                        Text("Hospital")
                            .font(.caption.bold())
                        Text(formatTime(status.timeRemaining))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
                
                if status.isInJail {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        Text("Jail")
                            .font(.caption.bold())
                        Text(formatTime(status.timeRemaining))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "0:00" }
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
