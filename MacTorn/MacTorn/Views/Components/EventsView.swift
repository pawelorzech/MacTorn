import SwiftUI

/// The latest things Torn told the player, newest first: what happened and how long ago.
struct EventsView: View {
    let events: [TornEvent]
    /// Mac↔Torn skew (issue #46) — event timestamps are Torn's, so "how long ago" is
    /// measured from Torn's now like every other clock in the panel.
    var serverClock: ServerClock = .synchronized

    var body: some View {
        BoardSection("Recent events") {
            if events.isEmpty {
                BoardEmptyState(title: "No recent events")
            } else {
                ForEach(events.prefix(5)) { event in
                    BoardRow(verticalPadding: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                            Text(event.cleanEvent)
                                .font(.boardCaption)
                                .foregroundStyle(Board.ink)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Board.Space.s)
                            Text(timeAgo(event.timestamp))
                                .font(.figure(13, weight: .regular))
                                .foregroundStyle(Board.inkSecondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(event.cleanEvent), \(timeAgo(event.timestamp)) ago")
                    .uiTestID("uitest.event.\(event.id)")
                }
            }
        }
    }

    private func timeAgo(_ timestamp: Int) -> String {
        TornFormatter.timeAgo(since: timestamp, now: serverClock.serverUnix(Date())) ?? "Unknown"
    }
}
