import SwiftUI

@main
struct MacTornApp: App {
    @State private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
                .environment(\.reduceTransparency, reduceTransparency)
                .onAppear {
                    updateAppearance()
                }
                .onChange(of: appearanceModeRaw) { _, _ in
                    updateAppearance()
                }
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    private func updateAppearance() {
        let mode = AppearanceMode(rawValue: appearanceModeRaw) ?? .system
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Menu Bar Label
struct MenuBarLabel: View {
    // @Bindable is the @Observable equivalent of @ObservedObject for views that
    // are passed an instance (vs. reading it from the environment). Plain `var`
    // would also work since SwiftUI tracks property reads in body for @Observable
    // types, but @Bindable keeps the call-site identical to before.
    @Bindable var appState: AppState

    var body: some View {
        Group {
            switch appState.menuBarDisplay {
            case .traveling(let flag, let seconds):
                Text("✈️\(flag)\(formatShortTime(seconds))")
            case .hospitalAbroad(let flag, let seconds):
                Text("🏥\(flag)\(formatShortTime(seconds))")
            case .hospitalAtHome(let seconds):
                Text("🏥\(formatShortTime(seconds))")
            case .jail(let seconds):
                Text("🚓\(formatShortTime(seconds))")
            case .cooldown(let emoji, let seconds):
                Text("\(emoji)\(formatShortTime(seconds))")
            case .fallbackIcon:
                Image(systemName: menuBarIcon)
            }
        }
        .transaction { $0.animation = nil }
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
        TornDestination.flag(for: destination)
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
