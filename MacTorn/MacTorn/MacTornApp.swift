import SwiftUI

@main
struct MacTornApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label
struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // Show airplane + flag + countdown when traveling
        if let travel = appState.data?.travel,
           travel.isTraveling {
            let destination = travel.destination ?? "?"
            let flag = flagForDestination(destination)
            let time = formatShortTime(appState.travelSecondsRemaining)
            Text("✈️\(flag)\(time)")
        } else {
            Image(systemName: menuBarIcon)
        }
    }

    private var menuBarIcon: String {
        // Error state
        if appState.errorMsg != nil {
            return "exclamationmark.triangle.fill"
        }

        // Abroad state
        if let travel = appState.data?.travel, travel.isAbroad {
            return "globe"
        }

        // Energy full state
        if let bars = appState.data?.bars {
            if bars.energy.current >= bars.energy.maximum {
                return "bolt.fill"
            }
        }

        // Default
        return "bolt"
    }

    private func flagForDestination(_ destination: String) -> String {
        switch destination.lowercased() {
        case "mexico": return "🇲🇽"
        case "cayman islands": return "🇰🇾"
        case "canada": return "🇨🇦"
        case "hawaii": return "🇺🇸"
        case "united kingdom": return "🇬🇧"
        case "argentina": return "🇦🇷"
        case "switzerland": return "🇨🇭"
        case "japan": return "🇯🇵"
        case "china": return "🇨🇳"
        case "uae": return "🇦🇪"
        case "south africa": return "🇿🇦"
        case "torn": return "🇺🇸"
        default: return "🌍"
        }
    }

    private func formatShortTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "0:00" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
