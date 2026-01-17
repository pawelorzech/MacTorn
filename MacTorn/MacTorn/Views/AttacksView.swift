import SwiftUI

struct AttacksView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Battle Stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "figure.martial.arts")
                            .foregroundColor(.red)
                        Text("Battle Stats")
                            .font(.caption.bold())
                    }
                    
                    if let stats = appState.battleStats {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            StatItem(label: "Strength", value: formatStat(stats.strength), color: .red)
                            StatItem(label: "Defense", value: formatStat(stats.defense), color: .blue)
                            StatItem(label: "Speed", value: formatStat(stats.speed), color: .green)
                            StatItem(label: "Dexterity", value: formatStat(stats.dexterity), color: .orange)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Total:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatStat(stats.total))
                                .font(.caption.bold())
                        }
                    } else {
                        Text("Loading stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
                
                // Recent Attacks
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.shield.fill")
                            .foregroundColor(.orange)
                        Text("Recent Attacks")
                            .font(.caption.bold())
                    }
                    
                    if let attacks = appState.recentAttacks, !attacks.isEmpty {
                        ForEach(attacks.prefix(5)) { attack in
                            HStack {
                                Image(systemName: attack.resultIcon)
                                    .foregroundColor(attack.resultColor)
                                    .frame(width: 16)
                                
                                Text(attack.opponentName ?? "Unknown")
                                    .font(.caption)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(attack.timeAgo)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No recent attacks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
                
                // Actions
                HStack(spacing: 8) {
                    ActionButton(title: "Attack", icon: "bolt.fill", color: .red) {
                        openURL("https://www.torn.com/loader.php?sid=attack&user2ID=")
                    }
                    
                    ActionButton(title: "Hospital", icon: "cross.case.fill", color: .pink) {
                        openURL("https://www.torn.com/hospitalview.php")
                    }
                    
                    ActionButton(title: "Bounties", icon: "target", color: .purple) {
                        openURL("https://www.torn.com/bounties.php")
                    }
                }
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func formatStat(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}
