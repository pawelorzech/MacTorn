import SwiftUI

struct StatusView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Torn Status")
                    .font(.headline)
                
                Spacer()
                
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        appState.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            
            // Last updated
            if let lastUpdated = appState.lastUpdated {
                Text("Updated: \(lastUpdated, formatter: timeFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Error state
            if let error = appState.errorMsg {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Bars
            if let bars = appState.data?.bars {
                VStack(spacing: 8) {
                    ProgressBarView(
                        label: "Energy",
                        current: bars.energy.current,
                        maximum: bars.energy.maximum,
                        color: .green,
                        icon: "bolt.fill"
                    )
                    
                    ProgressBarView(
                        label: "Nerve",
                        current: bars.nerve.current,
                        maximum: bars.nerve.maximum,
                        color: .red,
                        icon: "flame.fill"
                    )
                    
                    ProgressBarView(
                        label: "Happy",
                        current: bars.happy.current,
                        maximum: bars.happy.maximum,
                        color: .yellow,
                        icon: "face.smiling.fill"
                    )
                    
                    ProgressBarView(
                        label: "Life",
                        current: bars.life.current,
                        maximum: bars.life.maximum,
                        color: .pink,
                        icon: "heart.fill"
                    )
                }
            }
            
            // Cooldowns
            if let cooldowns = appState.data?.cooldowns {
                Divider()
                    .padding(.vertical, 4)
                
                Text("Cooldowns")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    CooldownItem(label: "Drug", seconds: cooldowns.drug, icon: "pills.fill")
                    CooldownItem(label: "Medical", seconds: cooldowns.medical, icon: "cross.case.fill")
                    CooldownItem(label: "Booster", seconds: cooldowns.booster, icon: "arrow.up.circle.fill")
                }
            }
        }
        .padding()
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Cooldown Item
struct CooldownItem: View {
    let label: String
    let seconds: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(seconds > 0 ? .orange : .green)
            
            Text(formattedTime)
                .font(.caption2.monospacedDigit())
                .foregroundColor(seconds > 0 ? .primary : .green)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var formattedTime: String {
        if seconds <= 0 {
            return "Ready"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
