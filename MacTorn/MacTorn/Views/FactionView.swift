import SwiftUI

/// "How is my faction doing": the faction and its chain, then my own organized crime, the
/// active war, what happened lately, and the armoury.
struct FactionView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(
                    for: .faction,
                    hasContent: appState.factionData != nil
                        || appState.player.organizedCrime != nil
                        || appState.player.organizedCrimeUnavailableReason != nil
                        || !appState.faction.wars.isEmpty
                        || !appState.faction.news.isEmpty
                ),
                onRetry: appState.refreshNow
            )

            factionSection

            // Organized Crime 2.0 (your own current OC)
            if let oc = appState.player.organizedCrime {
                OC2StatusView(oc: oc, playerId: appState.player.data?.playerId, serverClock: appState.player.serverClock)
            } else if let reason = appState.player.organizedCrimeUnavailableReason {
                BoardNotice(tone: .idle, message: "OC 2.0 unavailable", detail: reason)
            }

            // Active ranked war (score vs target)
            if let war = appState.faction.wars.first(where: { $0.isActive }) {
                RankedWarView(war: war, myFactionId: appState.factionData?.factionId)
            }

            if !appState.faction.news.isEmpty {
                FactionNewsView(news: appState.faction.news)
            }

            RecruitingPanel()
            WarfarePanel()

            armourySection

            BoardSection("Open in Torn") {
                TornLinks(links: [
                    TornLinks.Link(title: "Faction", url: TornLink.faction),
                    TornLinks.Link(title: "Wars", url: TornLink.factionWars),
                    TornLinks.Link(title: "OC", url: TornLink.factionCrimes),
                ])
                .padding(.top, Board.Space.s)
            }
        }
    }

    // MARK: - Faction

    @ViewBuilder
    private var factionSection: some View {
        if let faction = appState.factionData {
            VStack(alignment: .leading, spacing: Board.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(faction.name)
                            .font(.boardTitle)
                            .foregroundStyle(Board.ink)
                            .lineLimit(2)
                        Text(verbatim: "Faction ID \(faction.factionId)")
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                    }
                    Spacer(minLength: Board.Space.s)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TornFormatter.formatNumber(faction.respect))
                            .font(.figure(24))
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                        Text("Respect")
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let chain = appState.liveChain, faction.chain.current > 0 {
                    VStack(spacing: 0) {
                        Board.ink.frame(height: 1)
                        ChainView(chain: chain, serverClock: appState.player.serverClock)
                    }
                }
            }
        } else if !appState.isLoading {
            // "Loading" only while nothing has ever arrived. Once a refresh has completed,
            // absent faction data is a state, not progress: a player with no faction sat on
            // "Loading" forever. While loading, the module bar above already says so.
            BoardSection("Faction") {
                BoardEmptyState(
                    title: "No faction data",
                    detail: "You may not be in a faction, or your API key has no faction access."
                )
            }
        }
    }

    // MARK: - Armoury

    private var armourySection: some View {
        BoardSection("Armoury quick use") {
            HStack(spacing: 6) {
                Button("Xanax") {
                    openTorn(TornLink.page("factions.php?step=your#/tab=armoury&start=0&sub=donate"))
                }
                .buttonStyle(.boardFill)
                Button("Refill") { openTorn(TornLink.factionArmoury) }
                    .buttonStyle(.boardFill)
                Button("SED") { openTorn(TornLink.factionArmoury) }
                    .buttonStyle(.boardFill)
            }
            .padding(.top, Board.Space.s)
        }
        .disabled(appState.factionData == nil)
    }
}

// MARK: - Organized Crime 2.0 Status (your own current OC)

struct OC2StatusView: View {
    let oc: OrganizedCrime2
    let playerId: Int?
    /// Mac↔Torn skew (issue #46): `readyAt` is server-absolute.
    var serverClock: ServerClock = .synchronized

    private var detail: String? {
        var parts: [String] = []
        if let status = oc.status { parts.append(status) }
        if oc.totalSlots > 0 { parts.append("\(oc.filledSlots)/\(oc.totalSlots) filled") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        BoardSection("Organized crime", note: oc.difficulty.map { "Level \($0)" } ?? "") {
            // Name + ready countdown. `readyAt` is an absolute Unix timestamp, so we tick
            // `now` against it every second: no drift against the in-game OC panel.
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let now = serverClock.serverUnix(context.date)
                let remaining = NumericSafety.remaining(until: oc.readyAt, now: now)

                if remaining == 0 {
                    CountdownRow(tone: .ready, title: oc.name, detail: detail, value: "Ready")
                } else if let remaining, remaining > 0 {
                    CountdownRow(tone: .counting, title: oc.name, detail: detail, value: TornFormatter.clock(remaining))
                } else {
                    CountdownRow(tone: .idle, title: oc.name, detail: detail, value: "Unavailable")
                }
            }

            // Your own progress in your slot, if you hold one.
            if let pid = playerId, let progress = oc.myProgress(playerId: pid) {
                let clamped = min(max(progress, 0), 100)
                BoardRow {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Your progress")
                                .font(.boardBody)
                                .foregroundStyle(Board.ink)
                            Spacer()
                            Text("\(Int(clamped))%")
                                .font(.figureValue)
                                .foregroundStyle(Board.ink)
                        }
                        ProgressLine(progress: clamped / 100, color: Board.Tone.counting.fill)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Organized Crime progress")
                .accessibilityValue("\(Int(clamped)) percent")
                .uiTestID("uitest.faction.ocProgress")
            }
        }
    }
}

// MARK: - Ranked War

struct RankedWarView: View {
    let war: RankedWar
    let myFactionId: Int?

    var body: some View {
        let mine = myFactionId.flatMap { war.faction(id: $0) }
        let opp = myFactionId.flatMap { war.opponent(of: $0) }

        BoardSection("Ranked war", note: "Target \(TornFormatter.formatNumber(war.target))") {
            if let mine, let opp,
               let lead = NumericSafety.scoreLead(mine: mine.score, opponent: opp.score) {
                let progressValue = min(max(lead, 0), max(0, war.target))
                let progressTotal = max(war.target, 1)
                let tone: Board.Tone = lead >= 0 ? .ready : .alert

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
                        Text(verbatim: "\(TornFormatter.formatNumber(mine.score)) to \(TornFormatter.formatNumber(opp.score))")
                            .font(.figureRow)
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: Board.Space.s)
                        Text(lead >= 0 ? "Leading by \(TornFormatter.formatNumber(lead))" : "Behind by \(TornFormatter.formatNumber(-lead))")
                            .font(.boardCaption.weight(.medium))
                            .foregroundStyle(tone.ink)
                            .lineLimit(1)
                    }
                    Text(verbatim: "\(mine.name) against \(opp.name)")
                        .font(.boardCaption)
                        .foregroundStyle(Board.inkSecondary)
                        .lineLimit(2)

                    // War is won when a faction's *lead* reaches `target`.
                    ProgressLine(progress: Double(progressValue) / Double(progressTotal), color: tone.fill)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Ranked War lead progress")
                        .accessibilityValue("\(TornFormatter.formatNumber(progressValue)) of \(TornFormatter.formatNumber(progressTotal))")
                        .uiTestID("uitest.faction.warProgress")
                }
                .padding(.vertical, 8)
            } else {
                BoardNotice(tone: .idle, message: "Lead unavailable")
                    .padding(.vertical, 8)
                ForEach(war.factions) { f in
                    BoardRow {
                        HStack(alignment: .firstTextBaseline) {
                            Text(f.name)
                                .font(.boardBody)
                                .foregroundStyle(Board.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(TornFormatter.formatNumber(f.score))
                                .font(.figureValue)
                                .foregroundStyle(Board.ink)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Faction News

struct FactionNewsView: View {
    let news: [FactionNews]

    var body: some View {
        BoardSection("Faction news") {
            ForEach(news.prefix(5)) { item in
                BoardRow {
                    Text(item.plainText)
                        .font(.boardCaption)
                        .foregroundStyle(Board.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
