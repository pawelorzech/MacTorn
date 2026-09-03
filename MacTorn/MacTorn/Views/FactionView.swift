import SwiftUI

struct FactionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["faction.basic", "faction.rankedwars", "faction.news", "user.v2"],
                        hasContent: appState.factionData != nil
                            || appState.organizedCrime != nil
                            || !appState.rankedWars.isEmpty
                            || !appState.factionNews.isEmpty,
                        staleAfter: 360
                    ),
                    onRetry: appState.refreshNow
                )

                // Faction Info
                VStack(alignment: .leading, spacing: 8) {
                    if let faction = appState.factionData {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.blue)
                            Text(faction.name)
                                .font(.caption.bold())
                            Spacer()
                            Text("[\(faction.factionId)]")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Chain Status — `faction.chain.timeout` is an absolute Unix
                        // timestamp by the time it is published (Torn sends seconds
                        // remaining; `fetchFactionData` resolves it against the server
                        // clock), so we tick `now` against it every second and never
                        // extrapolate from a stored duration.
                        if faction.chain.current > 0 {
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                let remaining = max(0, faction.chain.timeout
                                    - appState.serverClock.serverUnix(context.date))
                                let color = chainColor(remaining: remaining)
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundColor(color)
                                    Text("Chain: \(faction.chain.current)/\(faction.chain.max)")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text(formatTime(remaining))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(color)
                                }
                                .padding(8)
                                .background(color.opacity(reduceTransparency ? 0.4 : 0.1))
                                .cornerRadius(6)
                            }
                        }
                        
                        // Respect
                        HStack {
                            Text("Respect:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatNumber(faction.respect))
                                .font(.caption.bold())
                        }
                    } else {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.blue)
                            Text("Faction")
                                .font(.caption.bold())
                        }
                        // "Loading" only while nothing has ever arrived. Once a refresh
                        // has completed, absent faction data is a *state*, not progress
                        // — a player with no faction sat on "Loading…" forever.
                        if appState.lastUpdated == nil {
                            Text("Loading faction data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No faction data. You may not be in a faction, or your API key has no faction access.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

                // Organized Crime 2.0 (your own current OC)
                if let oc = appState.organizedCrime {
                    OC2StatusView(oc: oc, playerId: appState.data?.playerId, serverClock: appState.serverClock)
                }

                // Active ranked war (score vs target)
                if let war = appState.rankedWars.first(where: { $0.isActive }) {
                    RankedWarView(war: war, myFactionId: appState.factionData?.factionId)
                }

                // Faction news feed
                if !appState.factionNews.isEmpty {
                    FactionNewsView(news: appState.factionNews)
                }

                // Armory Quick Actions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.purple)
                        Text("Armory Quick Use")
                            .font(.caption.bold())
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ArmoryButton(title: "Xanax", icon: "pills.fill", color: .blue) {
                            openURL("https://www.torn.com/factions.php?step=your#/tab=armoury&start=0&sub=donate")
                        }
                        
                        ArmoryButton(title: "Refill", icon: "drop.fill", color: .cyan) {
                            openURL("https://www.torn.com/factions.php?step=your#/tab=armoury")
                        }
                        
                        ArmoryButton(title: "SED", icon: "syringe.fill", color: .green) {
                            openURL("https://www.torn.com/factions.php?step=your#/tab=armoury")
                        }
                    }
                }
                .padding()
                .background(Color.purple.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

                // Actions
                HStack(spacing: 8) {
                    ActionButton(title: "Faction", icon: "person.3.fill", color: .blue) {
                        openURL("https://www.torn.com/factions.php?step=your")
                    }
                    
                    ActionButton(title: "Wars", icon: "flame.fill", color: .red) {
                        openURL("https://www.torn.com/factions.php?step=your#/tab=wars")
                    }
                    
                    ActionButton(title: "OC", icon: "briefcase.fill", color: .orange) {
                        openURL("https://www.torn.com/factions.php?step=your#/tab=crimes")
                    }
                }
            }
            .padding()
        }
    }
    
    private func chainColor(remaining: Int) -> Color {
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
    
    private func formatNumber(_ value: Int) -> String {
        TornFormatter.formatNumber(value)
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
    }
}

// MARK: - Organized Crime 2.0 Status (your own current OC)
struct OC2StatusView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let oc: OrganizedCrime2
    let playerId: Int?
    /// Mac↔Torn skew (issue #46) — `readyAt` is server-absolute.
    var serverClock: ServerClock = .synchronized

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "briefcase.fill")
                    .foregroundColor(.orange)
                Text("Organized Crime")
                    .font(.caption.bold())
                Spacer()
                if let difficulty = oc.difficulty {
                    Text("Lvl \(difficulty)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            }

            // Name + ready countdown. `readyAt` is an absolute Unix timestamp, so we
            // tick `now` against it every second — no drift vs the in-game OC panel.
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let now = serverClock.serverUnix(context.date)
                let ready = oc.readyAt.map { $0 <= now } ?? false
                let remaining = max(0, (oc.readyAt ?? 0) - now)

                HStack {
                    Text(oc.name)
                        .font(.caption.bold())
                    Spacer()
                    if ready {
                        Text("READY")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if remaining > 0 {
                        Text(formatTime(remaining))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.orange)
                    }
                }
            }

            // Status + slots filled
            HStack {
                if let status = oc.status {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if oc.totalSlots > 0 {
                    Text("\(oc.filledSlots)/\(oc.totalSlots) filled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Your own progress in your slot, if you hold one
            if let pid = playerId, let progress = oc.myProgress(playerId: pid) {
                let clampedProgress = min(max(progress, 0), 100)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Your progress")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(clampedProgress))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: clampedProgress, total: 100)
                        .tint(.orange)
                        .accessibilityLabel("Organized Crime progress")
                        .accessibilityValue("\(Int(clampedProgress)) percent")
                        .uiTestID("uitest.faction.ocProgress")
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(reduceTransparency ? 0.25 : 0.05))
        .cornerRadius(8)
    }

    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Ranked War
struct RankedWarView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let war: RankedWar
    let myFactionId: Int?

    var body: some View {
        let mine = myFactionId.flatMap { war.faction(id: $0) }
        let opp = myFactionId.flatMap { war.opponent(of: $0) }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.red)
                Text("Ranked War")
                    .font(.caption.bold())
                Spacer()
                Text("Target \(formatNumber(war.target))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let mine, let opp {
                let lead = mine.score - opp.score
                let progressValue = min(max(lead, 0), war.target)
                let progressTotal = max(war.target, 1)
                HStack {
                    Text(mine.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    Text("\(formatNumber(mine.score)) – \(formatNumber(opp.score))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(lead >= 0 ? .green : .red)
                    Spacer()
                    Text(opp.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                // War is won when a faction's *lead* reaches `target`.
                ProgressView(value: Double(progressValue),
                             total: Double(progressTotal))
                    .tint(lead >= 0 ? .green : .red)
                    .accessibilityLabel("Ranked War lead progress")
                    .accessibilityValue("\(formatNumber(progressValue)) of \(formatNumber(progressTotal))")
                    .uiTestID("uitest.faction.warProgress")
                Text(lead >= 0 ? "Leading by \(formatNumber(lead))" : "Behind by \(formatNumber(-lead))")
                    .font(.caption2)
                    .foregroundColor(lead >= 0 ? .green : .red)
            } else {
                ForEach(war.factions) { f in
                    HStack {
                        Text(f.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(formatNumber(f.score)).font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .background(Color.red.opacity(reduceTransparency ? 0.25 : 0.06))
        .cornerRadius(8)
    }

    private func formatNumber(_ v: Int) -> String {
        AppState.decimalFormatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

// MARK: - Faction News
struct FactionNewsView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let news: [FactionNews]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundColor(.blue)
                Text("Faction News")
                    .font(.caption.bold())
            }
            ForEach(news.prefix(5)) { item in
                HStack(alignment: .top, spacing: 4) {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.plainText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.05))
        .cornerRadius(8)
    }
}

// MARK: - Armory Button
struct ArmoryButton: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(reduceTransparency ? 0.4 : 0.15))
            .foregroundColor(color)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
