import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputKey: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("MacTorn")
                .font(.title2.bold())
            
            Text("Enter your Torn API Key")
                .font(.caption)
                .foregroundColor(.secondary)
            
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
        }
        .padding()
        .onAppear {
            inputKey = appState.apiKey
        }
    }
}
