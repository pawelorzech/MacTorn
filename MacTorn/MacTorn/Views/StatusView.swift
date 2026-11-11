import SwiftUI

/// "You, right now": the four bars, what is ready, what is counting down, and what is
/// waiting. The player's name and state are in the panel header above.
struct StatusView: View {
    @Environment(AppState.self) private var appState
    @State private var quickLinks = QuickLinks.load()

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .status, hasContent: appState.player.data != nil),
                onRetry: appState.refreshNow,
                detail: appState.errorMsg
            )

            if let bars = appState.player.data?.bars {
                MeterGrid(meters: [
                    MeterReading(name: "Energy", current: bars.energy.current, maximum: bars.energy.maximum, color: Board.Meter.energy),
                    MeterReading(name: "Nerve", current: bars.nerve.current, maximum: bars.nerve.maximum, color: Board.Meter.nerve),
                    MeterReading(name: "Happy", current: bars.happy.current, maximum: bars.happy.maximum, color: Board.Meter.happy),
                    MeterReading(name: "Life", current: bars.life.current, maximum: bars.life.maximum, color: Board.Meter.life),
                ])
            }

            // Someone placed a bounty on you: a safety signal, so it sits above the board.
            if !appState.player.bountiesOnMe.isEmpty {
                bountyRow
            }

            if appState.player.data != nil {
                NextUpSection()
            }

            // `notificationCounts` wins outright once it exists. Falling back to
            // `unreadMessages` while it is present would render an empty section, because
            // that value comes from the slower activity poll and can still be non-zero
            // after the counters have gone to zero.
            if appState.player.notificationCounts?.hasAny == true
                || (appState.player.notificationCounts == nil && appState.player.unreadMessages > 0) {
                waitingSection
            }

            CompetitionPanel()

            if !appState.player.activityEvents.isEmpty {
                EventsView(events: appState.player.activityEvents, serverClock: appState.player.serverClock)
            }

            BoardSection("Open in Torn") {
                TornLinks(links: tornLinks)
                    .padding(.top, Board.Space.s)
            }
        }
    }

    // MARK: - Bounty

    private var bountyRow: some View {
        let bounties = appState.player.bountiesOnMe
        let total = NumericSafety.total(bounties.map(\.reward))
        let amount = total.map { TornFormatter.formatMoney($0) } ?? "Unavailable"
        let title = bounties.count == 1 ? "Bounty on you" : "\(bounties.count) bounties on you"
        return Button {
            BrowserManager.shared.open(TornLink.bounties)
        } label: {
            CountdownRow(tone: .alert, title: title, detail: "Opens the bounty list", value: amount)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(amount). Opens Torn.")
    }

    // MARK: - Waiting for you

    /// Torn's own header counters: what is sitting unread. Each opens its page.
    private var waitingSection: some View {
        let counts = appState.player.notificationCounts
        let messages = counts?.messages ?? appState.player.unreadMessages
        let items: [(count: Int, noun: String, url: URL)] = [
            (messages, "message", TornLink.page("messages.php")),
            (counts?.events ?? 0, "event", TornLink.page("events.php")),
            (counts?.awards ?? 0, "award", TornLink.page("awards.php")),
            (counts?.competition ?? 0, "competition", TornLink.page("competition.php")),
        ].filter { $0.count > 0 }

        return BoardSection("Waiting for you") {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.l) {
                ForEach(items, id: \.noun) { item in
                    Button {
                        BrowserManager.shared.open(item.url)
                    } label: {
                        CountLabel(count: item.count, noun: item.noun)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.count) \(item.noun)\(item.count == 1 ? "" : "s") waiting. Opens Torn.")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Board.Space.s)
        }
    }

    // MARK: - Links

    private var tornLinks: [TornLinks.Link] {
        var links = quickLinks.compactMap { shortcut in
            URL(string: shortcut.url).map { TornLinks.Link(title: shortcut.name, url: $0) }
        }
        if let hub = URL(string: "https://hub.tri.ovh") {
            links.append(TornLinks.Link(title: "TRI Hub", url: hub))
        }
        return links
    }
}
