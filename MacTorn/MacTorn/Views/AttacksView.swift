import SwiftUI

/// Where you stand and what happened lately: battle stats led by their total, then the
/// latest fights, each opening the opponent's profile.
struct AttacksView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .attacks, hasContent: appState.player.battleStats != nil || appState.player.recentAttacks != nil),
                onRetry: appState.refreshNow
            )

            battleStatsSection
            recentAttacksSection

            BoardSection("Open in Torn") {
                TornLinks(links: [
                    TornLinks.Link(title: "Attack", url: TornLink.page("loader.php?sid=attack&user2ID=")),
                    TornLinks.Link(title: "Hospital", url: TornLink.hospital),
                    TornLinks.Link(title: "Bounties", url: TornLink.bounties),
                ])
                .padding(.top, Board.Space.s)
            }
        }
    }

    // MARK: - Battle stats

    @ViewBuilder
    private var battleStatsSection: some View {
        BoardSection("Battle stats") {
            if let stats = appState.player.battleStats {
                let total = stats.total.map(formatStat) ?? "Unavailable"
                BoardRow(verticalPadding: Board.Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
                        Text("Total")
                            .font(.boardStrong)
                            .foregroundStyle(Board.inkSecondary)
                        Spacer(minLength: Board.Space.s)
                        Text(total)
                            .font(stats.total == nil ? .boardBody : .figureHero)
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total: \(total)")
                .uiTestID("uitest.battleStats.total")

                statRow("Strength", stats.strength)
                statRow("Defense", stats.defense)
                statRow("Speed", stats.speed)
                statRow("Dexterity", stats.dexterity)
            } else if appState.isLoading {
                BoardEmptyState(title: "Loading stats")
            } else {
                // Battle stats need a key with the right access; a finished
                // refresh without them is a permission answer, not progress.
                BoardEmptyState(
                    title: "No battle stats",
                    detail: "Your API key may not have access. Check its access level in Settings."
                )
            }
        }
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        ValueRow(label: label, value: formatStat(value))
            .uiTestID("uitest.battleStats.\(label)")
    }

    // MARK: - Recent attacks

    @ViewBuilder
    private var recentAttacksSection: some View {
        BoardSection("Recent attacks") {
            if let attacks = appState.player.recentAttacks, !attacks.isEmpty,
               let userId = appState.player.data?.playerId {
                ForEach(attacks.prefix(5)) { attack in
                    AttackRow(attack: attack, userId: userId, now: appState.serverNow)
                }
            } else {
                BoardEmptyState(
                    title: "No recent attacks",
                    detail: "Fights you start or take part in show up here."
                )
            }
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
}

/// One fight: what happened to whom, which way it went, and how long ago. A hit against
/// the player reads in the alert tone, a win in the ready tone; the words and the symbol
/// say the same thing, so colour is never the only carrier.
private struct AttackRow: View {
    let attack: AttackResult
    let userId: Int
    let now: Date

    var body: some View {
        let result = attack.result.flatMap { $0.isEmpty ? nil : $0 } ?? "Result unavailable"
        let userWasAttacker = attack.wasAttacker(userId: userId)
        let opponentName = attack.opponentName(forUserId: userId)
        let tone = attack.resultTone(forUserId: userId)
        let timeAgo = attack.timeAgo(at: now)
        let direction = userWasAttacker ? "outgoing attack against" : "incoming attack from"
        let timeDescription = timeAgo.isEmpty ? ""
            : timeAgo == "now" ? ", just now"
            : ", \(timeAgo) ago"

        Button {
            if let opponentId = attack.opponentId(forUserId: userId) {
                BrowserManager.shared.open(TornLink.profile(opponentId))
            }
        } label: {
            BoardRow {
                HStack(alignment: .center, spacing: Board.Space.m) {
                    Image(systemName: attack.resultIcon(forUserId: userId))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tone.ink)
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(opponentName)
                            .font(.boardStrong)
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                        Text("\(result), \(userWasAttacker ? "you attacked" : "attacked you")")
                            .font(.boardDetail)
                            .foregroundStyle(tone.ink)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Board.Space.s)

                    Text(timeAgo)
                        .font(.figure(14, weight: .medium))
                        .foregroundStyle(Board.inkSecondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result), \(direction) \(opponentName)\(timeDescription)")
        .disabled(attack.opponentId(forUserId: userId) == nil)
        .uiTestID("uitest.attack.\(attack.id)")
    }
}

extension AttackResult {
    func resultIcon(forUserId userId: Int) -> String {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked": return userWasAttacker ? "checkmark.circle.fill" : "xmark.circle.fill"
        case "Mugged": return userWasAttacker ? "dollarsign.circle.fill" : "xmark.circle.fill"
        case "Hospitalized": return userWasAttacker ? "cross.circle.fill" : "xmark.circle.fill"
        case "Lost": return userWasAttacker ? "xmark.circle.fill" : "shield.checkered"
        case "Stalemate": return "equal.circle.fill"
        case "Escape": return userWasAttacker ? "figure.run" : "shield.checkered"
        case "Assist": return "person.2.fill"
        default: return "questionmark.circle"
        }
    }

    /// Ready for a win, alert for a hit against the player, counting for a draw or a
    /// getaway on your side, idle for everything else.
    func resultTone(forUserId userId: Int) -> Board.Tone {
        let userWasAttacker = wasAttacker(userId: userId)
        switch result {
        case "Attacked", "Mugged", "Hospitalized":
            return userWasAttacker ? .ready : .alert
        case "Lost":
            return userWasAttacker ? .alert : .ready
        case "Stalemate":
            return .counting
        case "Escape":
            return userWasAttacker ? .counting : .ready
        default:
            return .idle
        }
    }
}
