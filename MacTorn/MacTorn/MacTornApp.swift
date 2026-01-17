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
        // Error state
        if appState.errorMsg != nil {
            return "exclamationmark.triangle.fill"
        }
        
        // Traveling state
        if let travel = appState.data?.travel, travel.isTraveling {
            return "airplane"
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
}
