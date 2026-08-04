import SwiftUI

struct EventsView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let events: [TornEvent]
    /// Mac↔Torn skew (issue #46) — event timestamps are Torn's, so "how long ago" is
    /// measured from Torn's now like every other clock in the window.
    var serverClock: ServerClock = .synchronized

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                Text("Recent Events")
                    .font(.caption.bold())
            }

            if events.isEmpty {
                Text("No recent events")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.prefix(5)) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(.blue)
                            .accessibilityHidden(true)
                        Text(event.cleanEvent)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer()
                        Text(timeAgo(event.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(event.cleanEvent), \(timeAgo(event.timestamp)) ago")
                    .uiTestID("uitest.event.\(event.id)")
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.05))
        .cornerRadius(8)
    }
    
    private func timeAgo(_ timestamp: Int) -> String {
        let now = serverClock.serverUnix(Date())
        let diff = now - timestamp
        
        if diff < 60 {
            return "now"
        } else if diff < 3600 {
            return "\(diff / 60)m"
        } else if diff < 86400 {
            return "\(diff / 3600)h"
        }
        return "\(diff / 86400)d"
    }
}
