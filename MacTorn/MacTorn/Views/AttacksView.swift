import SwiftUI

struct AttacksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
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
                .background(Color.red.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

                // Recent Attacks
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.shield.fill")
                            .foregroundColor(.orange)
                        Text("Recent Attacks")
                            .font(.caption.bold())
                    }
                    
                    if let attacks = appState.recentAttacks, !attacks.isEmpty,
                       let userId = appState.data?.playerId {
                        ForEach(attacks.prefix(5)) { attack in
                            Button {
                                if let opponentId = attack.opponentId(forUserId: userId),
                                   let url = URL(string: "https://www.torn.com/profiles.php?XID=\(opponentId)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: attack.resultIcon(forUserId: userId))
                                        .foregroundColor(attack.resultColor(forUserId: userId))
                                        .frame(width: 14)

                                    Image(systemName: attack.wasAttacker(userId: userId) ? "arrow.right" : "arrow.left")
                                        .font(.caption2)
                                        .foregroundColor(attack.wasAttacker(userId: userId) ? .blue : .orange)
                                        .frame(width: 12)

                                    Text(attack.opponentName(forUserId: userId))
                                        .font(.caption)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(attack.timeAgo)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("No recent attacks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(reduceTransparency ? 0.25 : 0.05))
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
    @Environment(\.reduceTransparency) private var reduceTransparency
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
        .background(color.opacity(reduceTransparency ? 0.4 : 0.1))
        .cornerRadius(4)
    }
}
