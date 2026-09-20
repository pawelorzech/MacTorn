import SwiftUI

/// A compact "what now" strip. Status already shows bars and cooldowns in detail, so this
/// surface deliberately avoids repeating the full timeline.
struct NextActionView: View {
    @Environment(AppState.self) private var appState
    var reduceTransparency: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let nearest = appState.nextEvents(now: context.date).first {
                nearestRow(nearest)
            }
        }
    }

    private func nearestRow(_ event: NextEvent) -> some View {
        HStack(spacing: 9) {
            Image(systemName: event.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            Text(event.isReady ? "now" : TornFormatter.compactETA(event.eta))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(event.isReady ? Color.green : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(reduceTransparency ? 0.14 : 0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(event.title), \(event.isReady ? "ready now" : "in \(TornFormatter.compactETA(event.eta))")")
        .uiTestID("uitest.nextAction")
    }

    /// Compact human countdown: "45s", "4:32", "2h 05m", "1d 3h".
    static func formatETA(_ seconds: Int) -> String {
        TornFormatter.compactETA(seconds)
    }
}
