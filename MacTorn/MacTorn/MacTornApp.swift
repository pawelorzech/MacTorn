import SwiftUI

@main
struct MacTornApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: menuBarIcon)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
    
    private var menuBarIcon: String {
        if appState.errorMsg != nil {
            return "exclamationmark.triangle.fill"
        }
        if let bars = appState.data?.bars {
            if bars.energy.current >= bars.energy.maximum {
                return "bolt.fill"
            }
        }
        return "bolt"
    }
}
