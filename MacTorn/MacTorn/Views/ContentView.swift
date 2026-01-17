import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.apiKey.isEmpty {
                SettingsView()
            } else {
                StatusView()
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Footer buttons
            HStack {
                Button("Settings") {
                    appState.apiKey = "" // Go back to settings
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
        .environmentObject(appState)
    }
}
