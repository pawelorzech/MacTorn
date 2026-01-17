import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputKey: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("MacTorn")
                .font(.title2.bold())
            
            Text("Enter your Torn API Key")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // API Key input
            SecureField("API Key", text: $inputKey)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            Button("Save & Connect") {
                appState.apiKey = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.refreshNow()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputKey.isEmpty)
            
            Link("Get API Key from Torn",
                 destination: URL(string: "https://www.torn.com/preferences.php#tab=api")!)
                .font(.caption)
            
            Divider()
                .padding(.vertical, 8)
            
            // Launch at Login
            Toggle(isOn: Binding(
                get: { appState.launchAtLogin.isEnabled },
                set: { _ in appState.launchAtLogin.toggle() }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            inputKey = appState.apiKey
        }
    }
}
