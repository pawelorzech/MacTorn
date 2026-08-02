import SwiftUI

struct AttacksView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast", "user.activity"],
                        hasContent: appState.battleStats != nil || appState.recentAttacks != nil,
                        staleAfter: 360
                    ),
                    onRetry: appState.refreshNow
                )

                // Battle Stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "figure.martial.arts")
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Total: \(formatStat(stats.total))")
                        .uiTestID("uitest.battleStats.total")
                    } else if appState.lastUpdated == nil {
                        Text("Loading stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // Battle stats need a key with the right access; a finished
                        // refresh without them is a permission answer, not progress.
                        Text("No battle stats. Your API key may not have access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                            .accessibilityHidden(true)
                        Text("Recent Attacks")
                            .font(.caption.bold())
                    }
                    
                    if let attacks = appState.recentAttacks, !attacks.isEmpty,
                       let userId = appState.data?.playerId {
                        ForEach(attacks.prefix(5)) { attack in
                            let result = attack.result.flatMap { $0.isEmpty ? nil : $0 }
                                ?? "Result unavailable"
                            let userWasAttacker = attack.wasAttacker(userId: userId)
                            let opponentName = attack.opponentName(forUserId: userId)
                            let direction = userWasAttacker
                                ? "outgoing attack against"
                                : "incoming attack from"
                            let timeDescription = attack.timeAgo.isEmpty
                                ? ""
                                : ", \(attack.timeAgo) ago"

                            Button {
                                if let opponentId = attack.opponentId(forUserId: userId),
                                   let url = URL(string: "https://www.torn.com/profiles.php?XID=\(opponentId)") {
                                    BrowserManager.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: attack.resultIcon(forUserId: userId))
                                        .foregroundColor(attack.resultColor(forUserId: userId))
                                        .frame(width: 14)
                                        .accessibilityHidden(true)

                                    Image(systemName: userWasAttacker ? "arrow.right" : "arrow.left")
                                        .font(.caption2)
                                        .foregroundColor(userWasAttacker ? .blue : .orange)
                                        .frame(width: 12)
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(opponentName)
                                            .font(.caption)
                                            .lineLimit(1)

                                        Text(result)
                                            .font(.caption2.weight(.medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(attack.timeAgo)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(result), \(direction) \(opponentName)\(timeDescription)")
                            .uiTestID("uitest.attack.\(attack.id)")
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
            BrowserManager.shared.open(url)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .uiTestID("uitest.battleStats.\(label)")
    }
}
