import SwiftUI

struct EventsView: View {
    let events: [TornEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.blue)
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
                        Text(event.cleanEvent)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer()
                        Text(timeAgo(event.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func timeAgo(_ timestamp: Int) -> String {
        let now = Int(Date().timeIntervalSince1970)
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
