import SwiftUI

struct StatusView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                headerSection
                
                // Error state
                if let error = appState.errorMsg {
                    errorSection(error)
                }
                
                // Travel status
                if let travel = appState.data?.travel, travel.isTraveling || travel.isAbroad {
                    travelSection(travel)
                }
                
                // Bars
                if let bars = appState.data?.bars {
                    barsSection(bars)
                }
                
                // Cooldowns
                if let cooldowns = appState.data?.cooldowns {
                    cooldownsSection(cooldowns)
                }
                
                // Quick Links
                quickLinksSection
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let name = appState.data?.name, let id = appState.data?.playerId {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                        Text("[\(String(id))]")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Torn Status")
                        .font(.headline)
                }
                
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
        }
    }
    
    // MARK: - Error
    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Travel
    private func travelSection(_ travel: Travel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundColor(.blue)
                Text(travel.isTraveling ? "Traveling to \(travel.destination)" : "In \(travel.destination)")
                    .font(.caption.bold())
            }
            
            if travel.isTraveling {
                HStack {
                    Text("Arriving in:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatTime(travel.timeLeft))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Bars
    private func barsSection(_ bars: Bars) -> some View {
        VStack(spacing: 10) {
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
    
    // MARK: - Cooldowns
    private func cooldownsSection(_ cooldowns: Cooldowns) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
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
    
    // MARK: - Quick Links
    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Quick Links")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(appState.shortcutsManager.shortcuts) { shortcut in
                    Button {
                        appState.shortcutsManager.openURL(shortcut.url)
                    } label: {
                        Text(shortcut.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func formatTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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
                .font(.caption)
                .foregroundColor(seconds > 0 ? .orange : .green)
            
            Text(formattedTime)
                .font(.caption2.monospacedDigit())
                .foregroundColor(seconds > 0 ? .primary : .green)
                .fontWeight(seconds <= 0 ? .bold : .regular)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var formattedTime: String {
        if seconds <= 0 {
            return "Ready"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
