import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @AppStorage("preferredBrowser") private var preferredBrowser: String = PreferredBrowser.system.rawValue
    @AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"
    @AppStorage("privateIsland") private var privateIsland: Bool = false
    @AppStorage(SentryManager.enabledKey) private var sentryEnabled: Bool = false
    @State private var inputKey: String = ""
    @State private var showCredits: Bool = false
    @State private var availableBrowsers: [PreferredBrowser] = PreferredBrowser.availableBrowsers()

    private let developerID = TornConstants.developerID

    var body: some View {
        if showCredits {
            CreditsView(showCredits: $showCredits)
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        // @Bindable creates write-back bindings on @Observable model fields. Shadowing
        // the existing `appState` lets us use `$appState.refreshInterval` inline below
        // without changing the SwiftUI binding syntax at call sites.
        @Bindable var appState = appState
        return VStack(spacing: 20) {
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

            // API ToS Compliance
            apiUsageDisclosure

            Divider()
            
            // Settings
            VStack(spacing: 12) {
                // Refresh Interval
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Picker("Refresh", selection: $appState.refreshInterval) {
                        Text("15s ⚡︎").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("2m").tag(120)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appState.refreshInterval) { _, _ in
                        Task { @MainActor in
                            appState.startPolling()
                        }
                    }
                }
                if appState.refreshInterval == 15 {
                    Text("⚡︎ Aggressive: Torn may return cached data for up to ~30s, so 15s can spend API budget without fresher data. 30s is recommended.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                // Appearance Mode
                HStack {
                    Image(systemName: "moon.circle")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Preferred Browser
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Picker("Preferred Browser", selection: $preferredBrowser) {
                        ForEach(availableBrowsers) { browser in
                            Text(browser.rawValue).tag(browser.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Reduce Transparency (Accessibility)
                HStack {
                    Image(systemName: "eye")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Toggle("Reduce Transparency", isOn: $reduceTransparency)
                        .toggleStyle(.switch)
                }

                // Booster Cooldown Target
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Picker("Booster cooldown link", selection: $boosterCooldownTarget) {
                        Text("Boosters").tag("boosters")
                        Text("Alcohol").tag("alcohol")
                    }
                    .pickerStyle(.segmented)
                }

                // Private Island
                HStack {
                    Text("🏝️")
                        .frame(width: 20)
                    Toggle("Private Island (return icon)", isOn: $privateIsland)
                        .toggleStyle(.switch)
                }

                // Forum Polling Interval
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Picker("Forum check", selection: Binding(
                        get: { appState.forumWatchConfig.pollingIntervalSeconds },
                        set: { newValue in
                            appState.forumWatchConfig.pollingIntervalSeconds = newValue
                            appState.saveForumWatch()
                            appState.startForumPolling()
                        }
                    )) {
                        Text("2m").tag(120)
                        Text("3m").tag(180)
                        Text("5m").tag(300)
                    }
                    .pickerStyle(.segmented)
                }

                // Crash reporting (opt-in)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "ladybug")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Toggle("Send crash reports", isOn: $sentryEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: sentryEnabled) { _, _ in
                                SentryManager.applyState()
                            }
                    }
                    Text("Anonymous crash + error reports help fix bugs. API keys and player data are never sent.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
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
                    .background(Color.purple.opacity(reduceTransparency ? 0.4 : 0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.purple.opacity(reduceTransparency ? 0.25 : 0.05))
            .cornerRadius(8)

            // Update Section
            if let update = appState.updateAvailable {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.green)
                        Text("New version available: \(update.tagName)")
                            .font(.caption.bold())
                    }
                    
                    Button("Download Update") {
                        if let url = URL(string: update.htmlUrl) {
                            BrowserManager.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(reduceTransparency ? 0.4 : 0.1))
                .cornerRadius(8)
            }

            // GitHub & Version
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Link("View on GitHub",
                             destination: URL(string: "https://github.com/pawelorzech/MacTorn")!)
                            .font(.caption)
                    }

                    Button {
                        showCredits = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.pink)
                            Text("Credits")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                }
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            inputKey = appState.apiKey
            refreshAvailableBrowsers()
        }
        .alert("Launch at Login Error", isPresented: Binding(
            get: { appState.launchAtLogin.errorMessage != nil },
            set: { if !$0 { appState.launchAtLogin.errorMessage = nil } }
        )) {
            Button("OK") {
                appState.launchAtLogin.errorMessage = nil
            }
        } message: {
            Text(appState.launchAtLogin.errorMessage ?? "An unknown error occurred.")
        }
    }

    private func refreshAvailableBrowsers() {
        let browsers = PreferredBrowser.availableBrowsers()
        availableBrowsers = browsers
        if !browsers.contains(where: { $0.rawValue == preferredBrowser }) {
            preferredBrowser = PreferredBrowser.system.rawValue
        }
    }
    
    // MARK: - API Usage Disclosure
    private var apiUsageDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(apiSelections, id: \.selection) { item in
                    HStack(alignment: .top) {
                        Text(item.selection)
                            .font(.caption.monospaced())
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.accentColor)
                        Text(item.purpose)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Link("View Torn API Terms of Service",
                     destination: URL(string: "https://www.torn.com/api.html")!)
                    .font(.caption)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text("API Data Usage")
                    .font(.caption.bold())
            }
        }
        .padding(.horizontal)
    }

    private var apiSelections: [(selection: String, purpose: String)] {
        [
            ("basic", "Player name, ID, basic info"),
            ("bars", "Energy, Nerve, Happy, Life bars"),
            ("cooldowns", "Drug, Medical, Booster cooldowns"),
            ("travel", "Travel status and destination"),
            ("profile", "Battle stats, faction info"),
            ("events", "Recent events feed"),
            ("messages", "Unread message count"),
            ("market", "Item watchlist prices"),
            ("forum", "Forum thread monitoring")
        ]
    }

    private func openTornProfile() {
        let url = "https://www.torn.com/profiles.php?XID=\(developerID)"
        if let url = URL(string: url) {
            BrowserManager.shared.open(url)
        }
    }
}
