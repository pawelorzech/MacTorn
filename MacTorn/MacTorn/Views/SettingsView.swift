import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputKey: String = ""
    @State private var showNotificationSettings = false
    
    // Developer ID for tip feature (bombel)
    private let developerID = 2362436
    
    var body: some View {
        ScrollView {
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
                
                // Refresh Interval
                refreshIntervalSection
                
                // Launch at Login
                Toggle(isOn: Binding(
                    get: { appState.launchAtLogin.isEnabled },
                    set: { _ in appState.launchAtLogin.toggle() }
                )) {
                    Label("Launch at Login", systemImage: "power")
                }
                .toggleStyle(.switch)
                .padding(.horizontal)
                
                // Notification Settings
                Button {
                    showNotificationSettings.toggle()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Notification Rules")
                        Spacer()
                        Image(systemName: showNotificationSettings ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                
                if showNotificationSettings {
                    notificationRulesSection
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // Tip Me section
                tipMeSection
                
                // GitHub link
                githubSection
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            inputKey = appState.apiKey
        }
    }
    
    // MARK: - Refresh Interval
    private var refreshIntervalSection: some View {
        HStack {
            Label("Refresh Interval", systemImage: "clock")
                .font(.caption)
            
            Spacer()
            
            Picker("", selection: Binding(
                get: { appState.refreshInterval },
                set: { newValue in
                    appState.refreshInterval = newValue
                    appState.startPolling()
                }
            )) {
                Text("15s").tag(15)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Notification Rules
    private var notificationRulesSection: some View {
        VStack(spacing: 8) {
            ForEach(appState.notificationRules) { rule in
                NotificationRuleRow(rule: rule) { updatedRule in
                    appState.updateRule(updatedRule)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // MARK: - Tip Me Section
    private var tipMeSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundColor(.purple)
                Text("Support the Developer")
                    .font(.caption.bold())
            }
            
            Text("Send me some Xanax or cash :)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                openTornProfile()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Send Xanax to bombel")
                }
                .font(.caption)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - GitHub Section
    private var githubSection: some View {
        HStack {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .foregroundColor(.gray)
            Link("View Source on GitHub",
                 destination: URL(string: "https://github.com/pawelorzech/MacTorn")!)
                .font(.caption)
        }
    }
    
    // MARK: - Helpers
    private func openTornProfile() {
        let url = "https://www.torn.com/profiles.php?XID=\(developerID)"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Notification Rule Row
struct NotificationRuleRow: View {
    let rule: NotificationRule
    let onUpdate: (NotificationRule) -> Void
    
    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    var updated = rule
                    updated.enabled = newValue
                    onUpdate(updated)
                }
            )) {
                HStack {
                    Text(rule.barType.rawValue)
                        .font(.caption)
                    Text("@ \(rule.threshold)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            
            Picker("", selection: Binding(
                get: { rule.soundName },
                set: { newValue in
                    var updated = rule
                    updated.soundName = newValue
                    onUpdate(updated)
                }
            )) {
                ForEach(NotificationSound.allCases, id: \.rawValue) { sound in
                    Text(sound.displayName).tag(sound.rawValue)
                }
            }
            .frame(width: 80)
        }
    }
}
