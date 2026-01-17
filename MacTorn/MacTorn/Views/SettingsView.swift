import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputKey: String = ""
    
    // Developer ID for tip feature (bombel)
    private let developerID = 2362436
    
    var body: some View {
        VStack(spacing: 20) {
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
            
            // API Key section
            VStack(spacing: 8) {
                SecureField("Torn API Key", text: $inputKey)
                    .textFieldStyle(.roundedBorder)
                
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
            .padding(.horizontal)
            
            Divider()
            
            // Settings
            VStack(spacing: 12) {
                // Refresh Interval
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Picker("Refresh", selection: Binding(
                        get: { appState.refreshInterval },
                        set: { newValue in
                            appState.refreshInterval = newValue
                            appState.startPolling()
                        }
                    )) {
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("2m").tag(120)
                    }
                    .pickerStyle(.segmented)
                }
                
                // Launch at Login
                HStack {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Toggle("Launch at Login", isOn: Binding(
                        get: { appState.launchAtLogin.isEnabled },
                        set: { _ in appState.launchAtLogin.toggle() }
                    ))
                    .toggleStyle(.switch)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Support section
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .foregroundColor(.purple)
                    Text("Support the Developer")
                        .font(.caption.bold())
                }
                
                Text("Send me some Xanax or cash :)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Button {
                    openTornProfile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Send to bombel")
                    }
                    .font(.caption)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(8)
            
            // GitHub
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Link("View on GitHub",
                     destination: URL(string: "https://github.com/pawelorzech/MacTorn")!)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            inputKey = appState.apiKey
        }
    }
    
    private func openTornProfile() {
        let url = "https://www.torn.com/profiles.php?XID=\(developerID)"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}
