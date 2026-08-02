import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case account
    case refresh
    case notifications
    case privacy
    case startup
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .refresh: return "Refresh"
        case .notifications: return "Notifications"
        case .privacy: return "Privacy"
        case .startup: return "Startup"
        case .diagnostics: return "Diagnostics & About"
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .refresh: return "arrow.clockwise"
        case .notifications: return "bell"
        case .privacy: return "lock.shield"
        case .startup: return "power"
        case .diagnostics: return "stethoscope"
        }
    }

    var anchorID: String {
        "settings.section.\(rawValue)"
    }

    var compactTitle: String {
        switch self {
        case .account: return "Account"
        case .refresh: return "Refresh"
        case .notifications: return "Alerts"
        case .privacy: return "Privacy"
        case .startup: return "Startup"
        case .diagnostics: return "About"
        }
    }
}

private enum SettingsFocus: Hashable {
    case apiKey
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @AppStorage("preferredBrowser") private var preferredBrowser: String = PreferredBrowser.system.rawValue
    @AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"
    @AppStorage("privateIsland") private var privateIsland: Bool = false
    @AppStorage(SentryManager.enabledKey) private var sentryEnabled: Bool = false
    @State private var inputKey: String = ""
    @State private var showCredits = false
    @State private var showDiagnostics = false
    @State private var selectedSection: SettingsSection = .account
    @State private var availableBrowsers: [PreferredBrowser] = PreferredBrowser.availableBrowsers()
    @FocusState private var settingsFocus: SettingsFocus?

    private let onDismiss: () -> Void
    private let developerID = TornConstants.developerID

    init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            if showCredits {
                CreditsView(showCredits: $showCredits)
            } else {
                settingsContent
            }
        }
        .onExitCommand(perform: handleEscape)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsHeader
            sectionPicker

            ScrollView {
                settingsSection(selectedSection) {
                    selectedSectionContent
                }
                .id(selectedSection)
            }
            .scrollIndicators(.automatic)
        }
        .padding(12)
        .frame(width: 320)
        .frame(height: 500, alignment: .top)
        .onAppear {
            inputKey = appState.apiKey
            refreshAvailableBrowsers()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(appState: appState)
                .onExitCommand {
                    showDiagnostics = false
                }
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

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.title)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("MacTorn")
                    .font(.title2.bold())
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !appState.apiKey.isEmpty {
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sectionPicker: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
            spacing: 6
        ) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.caption)
                        Text(section.compactTitle)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selectedSection == section
                            ? Color.accentColor.opacity(reduceTransparency ? 0.28 : 0.14)
                            : Color.secondary.opacity(reduceTransparency ? 0.12 : 0.06)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.65)
                                    : Color.clear
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .uiTestID(section.anchorID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .account:
            accountSection
        case .refresh:
            refreshSection
        case .notifications:
            notificationsSection
        case .privacy:
            privacySection
        case .startup:
            startupSection
        case .diagnostics:
            diagnosticsSection
        }
    }

    private func settingsSection<Content: View>(
        _ section: SettingsSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: section.icon)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(reduceTransparency ? 0.14 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .id(section.anchorID)
        .uiTestID("uitest.settingsContent.\(section.rawValue)")
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Torn API Key", text: $inputKey)
                .textFieldStyle(.roundedBorder)
                .focused($settingsFocus, equals: .apiKey)
                .accessibilityLabel("Torn API Key")
                .uiTestID("uitest.apiKeyField")
                // A validation result belongs to the key it was run against. Editing the
                // field invalidates it — otherwise a green "✓ Full Access · ID 123456"
                // from key A stays on screen under a freshly-typed key B, and the user
                // saves B believing it was verified.
                .onChange(of: inputKey) { _, _ in
                    if appState.keyValidation != .idle {
                        appState.keyValidation = .idle
                    }
                }

            HStack(spacing: 8) {
                Button("Save & Connect") {
                    appState.apiKey = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.refreshNow()
                }
                .buttonStyle(.borderedProminent)
                // Block repeated refreshes for the current key, but still allow an
                // account switch while its old request is in flight. Updating the key
                // advances the account generation and cancels those stale tasks.
                .disabled(trimmedInputKey.isEmpty
                          || (appState.isLoading && trimmedInputKey == appState.apiKey))
                .uiTestID("uitest.saveKey")

                Button {
                    let typed = trimmedInputKey
                    Task { await appState.validateKey(typed.isEmpty ? nil : typed) }
                } label: {
                    if appState.keyValidation == .validating {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Text("Test Connection")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(appState.keyValidation == .validating
                          || (trimmedInputKey.isEmpty && appState.apiKey.isEmpty))
                .uiTestID("uitest.testConnection")
            }
            .controlSize(.small)

            keyValidationResult

            Link(
                "Get API Key from Torn",
                destination: URL(string: "https://www.torn.com/preferences.php#tab=api")!
            )
            .font(.caption)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Main refresh", selection: refreshIntervalBinding) {
                Text("15s ⚡︎").tag(15)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("2m").tag(120)
            }
            .pickerStyle(.segmented)

            if appState.refreshInterval == 15 {
                Text("Torn may cache data for about 30 seconds. A 15-second interval can spend API budget without returning fresher data; 30 seconds is recommended.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Forum check", selection: forumPollingBinding) {
                Text("2m").tag(120)
                Text("3m").tag(180)
                Text("5m").tag(300)
            }
            .pickerStyle(.segmented)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            nextActionConfigSection

            Picker("Booster cooldown link", selection: $boosterCooldownTarget) {
                Text("Boosters").tag("boosters")
                Text("Alcohol").tag("alcohol")
            }
            .pickerStyle(.segmented)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            apiUsageDisclosure

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Toggle("Send crash reports", isOn: $sentryEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: sentryEnabled) { _, _ in
                        SentryManager.applyState()
                    }
                Text("Anonymous crash and error reports help fix bugs. API keys and player data are never sent.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at Login", isOn: Binding(
                get: { appState.launchAtLogin.isEnabled },
                set: { _ in appState.launchAtLogin.toggle() }
            ))
            .toggleStyle(.switch)

            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Picker("Preferred Browser", selection: $preferredBrowser) {
                ForEach(availableBrowsers) { browser in
                    Text(browser.rawValue).tag(browser.rawValue)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 3) {
                Toggle("Private Island return icon", isOn: $privateIsland)
                    .toggleStyle(.switch)
                Text("Shows the Private Island shortcut for the return trip. Quick Travel time is selected separately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle("Always reduce transparency", isOn: $reduceTransparency)
                .toggleStyle(.switch)
                .help("MacTorn already follows System Settings → Accessibility → "
                      + "Display → Reduce transparency. Turn this on to use solid "
                      + "backgrounds even when that system setting is off.")
                .accessibilityHint("Forces solid backgrounds regardless of the system "
                                   + "Reduce transparency setting")
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let update = appState.updateAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "New version available: \(update.tagName)",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                    Button("Download Update") {
                        if let url = URL(string: update.htmlUrl) {
                            BrowserManager.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button("Diagnostics") {
                    showDiagnostics = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("settings.diagnostics")

                Button("Credits") {
                    showCredits = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(
                    "GitHub",
                    destination: URL(string: "https://github.com/pawelorzech/MacTorn")!
                )
                .font(.caption)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Support the Developer")
                        .font(.caption.bold())
                    Text("Send me some Xanax or cash :)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Send to bombel") {
                    openTornProfile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("MacTorn v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { appState.refreshInterval },
            set: { newValue in
                appState.refreshInterval = newValue
                appState.startPolling()
            }
        )
    }

    private var forumPollingBinding: Binding<Int> {
        Binding(
            get: { appState.forumWatchConfig.pollingIntervalSeconds },
            set: { newValue in
                appState.forumWatchConfig.pollingIntervalSeconds = newValue
                appState.saveForumWatch()
                appState.startForumPolling()
            }
        )
    }

    private var trimmedInputKey: String {
        inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleEscape() {
        if settingsFocus != nil {
            settingsFocus = nil
        } else if showDiagnostics {
            showDiagnostics = false
        } else if showCredits {
            showCredits = false
        } else if !appState.apiKey.isEmpty {
            onDismiss()
        }
    }

    private func refreshAvailableBrowsers() {
        let browsers = PreferredBrowser.availableBrowsers()
        availableBrowsers = browsers
        if !browsers.contains(where: { $0.rawValue == preferredBrowser }) {
            preferredBrowser = PreferredBrowser.system.rawValue
        }
    }

    private var nextActionConfigSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose which events appear in the Next Action timeline.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(NextActionCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { !appState.hiddenNextActionCategories.contains(category) },
                        set: { show in
                            if show {
                                appState.hiddenNextActionCategories.remove(category)
                            } else {
                                appState.hiddenNextActionCategories.insert(category)
                            }
                        }
                    )) {
                        Label(category.label, systemImage: category.systemImage)
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Next Action timeline", systemImage: "flag.checkered")
                .font(.caption.bold())
        }
    }

    @ViewBuilder
    private var keyValidationResult: some View {
        switch appState.keyValidation {
        case .idle, .validating:
            EmptyView()
        case .success(let result):
            let blocked = result.availability.filter { !$0.available }
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(result.accessType) · ID \(result.playerID)",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.green)

                if blocked.isEmpty {
                    Text("All MacTorn features are available with this key.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Limited by your key — these features won't load:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(blocked) { item in
                        Text("• \(item.name)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .uiTestID("uitest.keyValidationSuccess")
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .uiTestID("uitest.keyValidationFailure")
        }
    }

    private var apiUsageDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                disclosureLine(
                    "key.fill",
                    "Requires a Torn key with at least **\(TornEndpointRegistry.requiredAccessLevel.label)** for every feature. Lower access still works — unavailable modules are shown after Test Connection."
                )
                disclosureLine(
                    "lock.fill",
                    "Your key is stored in the macOS **Keychain**, never in plaintext preferences."
                )
                disclosureLine(
                    "desktopcomputer",
                    "All Torn data stays **on this Mac**. MacTorn is read-only — it never takes action on your account."
                )
                disclosureLine(
                    "exclamationmark.shield",
                    "Crash reporting is **opt-in** and off by default; no Torn data is sent."
                )

                Divider()

                Text("Selections requested:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(TornEndpointRegistry.allSelections.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)

                Link(
                    "View Torn API Terms of Service",
                    destination: URL(string: "https://www.torn.com/api.html")!
                )
                .font(.caption)
            }
            .padding(.top, 4)
        } label: {
            Label("API Data Usage", systemImage: "doc.text")
                .font(.caption.bold())
        }
    }

    private func disclosureLine(_ icon: String, _ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(.init(markdown))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openTornProfile() {
        let url = "https://www.torn.com/profiles.php?XID=\(developerID)"
        if let url = URL(string: url) {
            BrowserManager.shared.open(url)
        }
    }
}
