import SwiftUI

/// The Next Action timeline card (Etap J): the single soonest event, prominently, plus a
/// list of what follows. Counts down live via `TimelineView` off a shared clock — no
/// extra timers or API calls. Hidden categories are filtered by AppState.
struct NextActionView: View {
    @Environment(AppState.self) private var appState
    var reduceTransparency: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let events = appState.nextEvents(now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Next Action")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if let nearest = events.first {
                    nearestRow(nearest)
                    if events.count > 1 {
                        Divider().opacity(0.5)
                        VStack(spacing: 4) {
                            ForEach(events.dropFirst().prefix(6)) { event in
                                upcomingRow(event)
                            }
                        }
                    }
                } else {
                    Text("Nothing pending — you're all caught up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(reduceTransparency ? 0.14 : 0.08))
            )
        }
    }

    private func nearestRow(_ event: NextEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.subheadline.weight(.semibold))
                Text(event.isReady ? "ready now" : "in \(Self.formatETA(event.eta))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.isReady ? "now" : Self.formatETA(event.eta))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(event.isReady ? Color.green : Color.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(event.title), \(event.isReady ? "ready now" : "in \(Self.formatETA(event.eta))")")
    }

    private func upcomingRow(_ event: NextEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(event.title).font(.caption)
            Spacer()
            Text(event.isReady ? "now" : Self.formatETA(event.eta))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.isReady ? "ready now" : "in \(Self.formatETA(event.eta))")")
    }

    /// Compact human countdown: "45s", "4:32", "2h 05m", "1d 3h".
    static func formatETA(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        if s < 86_400 {
            return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
        }
        return String(format: "%dd %dh", s / 86_400, (s % 86_400) / 3600)
    }
}
