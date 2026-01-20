import SwiftUI

struct FactionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                        
                        // Chain Status
                        if faction.chain.current > 0 {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(chainColor(faction.chain))
                                Text("Chain: \(faction.chain.current)/\(faction.chain.max)")
                                    .font(.caption.bold())
                                Spacer()
                                Text(formatTime(faction.chain.timeout))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(chainColor(faction.chain))
                            }
                            .padding(8)
                            .background(chainColor(faction.chain).opacity(reduceTransparency ? 0.4 : 0.1))
                            .cornerRadius(6)
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
                        Text("Loading faction data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

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
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func chainColor(_ chain: FactionChain) -> Color {
        if chain.timeout < 60 {
            return .red
        } else if chain.timeout < 180 {
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
                    .font(.system(size: 14))
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
