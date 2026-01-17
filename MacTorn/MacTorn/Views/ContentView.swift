import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.apiKey.isEmpty || showSettings {
                SettingsView()
                    .environmentObject(appState)
            } else {
                // Last updated
                if let lastUpdated = appState.lastUpdated {
                    HStack {
                        Text("Updated: \(lastUpdated, formatter: timeFormatter)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                StatusView()
                    .environmentObject(appState)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Footer buttons
            HStack {
                if !appState.apiKey.isEmpty {
                    Button(showSettings ? "Back" : "Settings") {
                        showSettings.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                
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
        .frame(width: 300)
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}
