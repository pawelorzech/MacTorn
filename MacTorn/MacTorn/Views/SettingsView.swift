import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case account
    case refresh
    case notifications
    case modules
    case privacy
    case general
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .refresh: return "Refresh"
        case .notifications: return "Notifications"
        case .modules: return "Modules"
        case .privacy: return "Privacy"
        case .general: return "General"
        case .diagnostics: return "Diagnostics & About"
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .refresh: return "arrow.clockwise"
        case .notifications: return "bell"
        case .modules: return "square.grid.2x2"
        case .privacy: return "lock.shield"
        case .general: return "gearshape"
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
        case .modules: return "Modules"
        case .privacy: return "Privacy"
        case .general: return "General"
        case .diagnostics: return "About"
        }
    }
}

private enum SettingsFocus: Hashable {
    case apiKey
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppNavigationState.self) private var navigation
    @AppStorage(StoredPreference.appearanceMode) private var appearanceMode: AppearanceMode = .system
    @AppStorage(StoredPreference.reduceTransparency) private var reduceTransparencyOverride: Bool = false
    @AppStorage(StoredPreference.preferredBrowser) private var preferredBrowser: String = PreferredBrowser.system.rawValue
    @AppStorage(StoredPreference.boosterCooldownTarget) private var boosterCooldownTarget: BoosterCooldownTarget = .boosters
    @AppStorage(StoredPreference.privateIsland) private var privateIsland: Bool = false
    @AppStorage(SentryManager.enabledKey) private var sentryEnabled: Bool = false
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @State private var inputKey: String = ""
    @State private var showCredits = false
    @State private var showDiagnostics = false
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

    private var isFirstRun: Bool { appState.apiKey.isEmpty }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            // First run: explain what the key is for instead of seven chips and a bare field.
            if isFirstRun {
                welcomeIntro
            } else {
                sectionPicker
            }

            BoardPage {
                BoardSection(visibleSection.title) {
                    selectedSectionContent
                }
                .accessibilityElement(children: .contain)
                .id(visibleSection.anchorID)
                .uiTestID("uitest.settingsContent.\(visibleSection.rawValue)")
            }
            .id(visibleSection)
            .scrollIndicators(.automatic)

            if isFirstRun {
                // No rail on first run, so this is the only way to quit.
                Button("Quit MacTorn") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.boardInline)
                .padding(.horizontal, Board.gutter)
                .padding(.vertical, Board.Space.m)
            }
        }
        // Fill whatever width and height the host gives, rather than a number tuned against
        // an older one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Board.surface)
        .onAppear {
            inputKey = appState.apiKey
            refreshAvailableBrowsers()
            // First run: put the cursor in the key field so setup needs no pointer.
            // Deferred one runloop turn, because focus set during onAppear is otherwise dropped.
            if isFirstRun && navigation.settingsSection == .account {
                DispatchQueue.main.async { settingsFocus = .apiKey }
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(appState: appState)
                .onExitCommand {
                    showDiagnostics = false
                }
        }
        .alert("Launch at login error", isPresented: Binding(
            get: { launchAtLogin.errorMessage != nil },
            set: { if !$0 { launchAtLogin.errorMessage = nil } }
        )) {
            Button("OK") {
                launchAtLogin.errorMessage = nil
            }
        } message: {
            Text(launchAtLogin.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: Board.Space.s) {
            Text(isFirstRun ? "Welcome to MacTorn" : "Settings")
                .font(.boardTitle)
                .foregroundStyle(Board.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Board.Space.s)

            if !isFirstRun {
                Button("Done", action: onDismiss)
                    .buttonStyle(.board)
            }
        }
        .padding(.horizontal, Board.gutter)
        .padding(.top, Board.Space.m)
        .padding(.bottom, Board.Space.m)
        .accessibilityElement(children: .contain)
    }

    private var sectionPicker: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(SettingsSection.allCases) { section in
                let isSelected = navigation.settingsSection == section
                Button {
                    navigation.settingsSection = section
                } label: {
                    Text(section.compactTitle)
                        .font(.boardCaption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Board.onAccent : Board.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            isSelected ? Board.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Board.Radius.control)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Board.Radius.control)
                                .strokeBorder(isSelected ? Board.accent : Board.outline, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: Board.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .uiTestID(section.anchorID)
            }
        }
        .padding(.horizontal, Board.gutter)
        .padding(.bottom, Board.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    /// Without a key only the Account section is reachable; the chips are hidden.
    private var visibleSection: SettingsSection {
        isFirstRun ? .account : navigation.settingsSection
    }

    private var welcomeIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Torn bars, cooldowns, travel and faction in the menu bar, refreshed in the background.")
                .font(.boardCaption)
                .foregroundStyle(Board.ink)
                .fixedSize(horizontal: false, vertical: true)
            disclosureLine(
                "key.fill",
                "Paste a Torn API key with **\(TornEndpointRegistry.requiredAccessLevel.label)** or higher for every feature."
            )
            disclosureLine(
                "lock.fill",
                "The key is stored in the macOS **Keychain** and Torn data stays **on this Mac**. MacTorn never acts on your account."
            )
        }
        .padding(.horizontal, Board.gutter)
        .padding(.bottom, Board.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .uiTestID("uitest.welcomeIntro")
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch visibleSection {
        case .account:
            accountSection
        case .refresh:
            refreshSection
        case .notifications:
            notificationsSection
        case .modules:
            modulesSection
        case .privacy:
            privacySection
        case .general:
            generalSection
        case .diagnostics:
            diagnosticsSection
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirstRun, let player = appState.player.data, let name = player.name {
                ValueRow(label: "Connected as", value: name, isFigure: false)
                if let id = player.playerId {
                    ValueRow(label: "Player ID", value: String(id))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SecureField("Torn API Key", text: $inputKey)
                    .textFieldStyle(.plain)
                    .font(.boardBody)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 28)
                    .background(Board.well, in: RoundedRectangle(cornerRadius: Board.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Board.Radius.control)
                            .strokeBorder(Board.outline, lineWidth: 1)
                    }
                    .focused($settingsFocus, equals: .apiKey)
                    .accessibilityLabel("Torn API Key")
                    .uiTestID("uitest.apiKeyField")
                    // Return in the key field does what "Save & Connect" does, so first-run
                    // setup completes from the keyboard alone.
                    .onSubmit {
                        if canSaveKey { saveAndConnect() }
                    }
                    // A validation result belongs to the key it was run against. Editing the
                    // field invalidates it; otherwise a green result for key A stays on screen
                    // under a freshly-typed key B, and the user saves B believing it was verified.
                    .onChange(of: inputKey) { _, _ in
                        if appState.keyValidation != .idle {
                            appState.keyValidation = .idle
                        }
                    }

                HStack(spacing: 8) {
                    Button("Save & Connect", action: saveAndConnect)
                        .buttonStyle(.boardPrimary)
                        .disabled(!canSaveKey)
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
                    .buttonStyle(.board)
                    .disabled(appState.keyValidation == .validating
                              || (trimmedInputKey.isEmpty && appState.apiKey.isEmpty))
                    .uiTestID("uitest.testConnection")
                }

                keyValidationResult

                if let error = appState.accountSession.persistenceError {
                    BoardNotice(tone: .alert, message: error)
                        .uiTestID("uitest.keyPersistenceError")
                }

                // Button + BrowserManager rather than `Link`, so the Preferred Browser setting
                // is honoured.
                Button("Get API Key from Torn") {
                    BrowserManager.shared.open(TornLink.apiKeyPreferences)
                }
                .buttonStyle(.boardInline)
            }
            .padding(.top, Board.Space.m)
        }
    }

    // MARK: - Refresh

    private static func intervalLabel(_ seconds: Int) -> String {
        seconds < 120 ? "\(seconds)s" : "\(seconds / 60)m"
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingChoiceRow(
                title: "Main refresh",
                detail: appState.refreshInterval == AppState.refreshIntervals.first
                    ? "Torn may cache data for about 30 seconds. A 15-second interval can spend API budget without returning fresher data; 30 seconds is recommended."
                    : nil
            ) {
                Picker("Main refresh", selection: refreshIntervalBinding) {
                    ForEach(AppState.refreshIntervals, id: \.self) { seconds in
                        if seconds == AppState.refreshIntervals.first {
                            Text(Self.intervalLabel(seconds))
                                .accessibilityLabel("\(seconds) seconds, fastest")
                                .tag(seconds)
                        } else {
                            Text(Self.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            SettingChoiceRow(title: "Forum check") {
                Picker("Forum check", selection: forumPollingBinding) {
                    ForEach(ForumWatchConfig.pollingIntervals, id: \.self) { seconds in
                        Text(Self.intervalLabel(seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            SwitchRow(title: "Alert on new threads in a forum category", isOn: forumCategoryMonitorBinding)

            if appState.forumWatch.config.factionForumAutoMonitor {
                BoardRow {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: Board.Space.s) {
                            Text("Category ID")
                                .font(.boardBody)
                                .foregroundStyle(Board.ink)
                            Spacer(minLength: Board.Space.s)
                            TextField("e.g. 4", text: forumCategoryIDBinding)
                                .textFieldStyle(.board)
                                .accessibilityLabel("Forum category ID")
                                .frame(width: 80)
                        }
                        // Without a category id the watch fetches nothing and reports nothing,
                        // so the switch reads as armed while being permanently inert. Say so.
                        if appState.forumWatch.config.factionForumCategoryId == nil {
                            BoardNotice(
                                tone: .counting,
                                message: "Enter a category ID, nothing is being watched yet."
                            )
                        }
                        Text("Find the ID in the forum URL: torn.com/forums.php#/p=forums&f=4 is category 4. The first check only learns which threads are already there, so alerts start from the next one.")
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Notifications, modules, privacy

    private var notificationsSection: some View {
        nextActionConfigSection
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: Board.Space.s) {
            Text("Optional extras that use more of your Torn API budget. Once switched on, each one appears inside its tab.")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Board.Space.s)

            ModuleSwitchList()
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            apiUsageDisclosure

            SwitchRow(
                title: "Send crash reports",
                detail: "Anonymous crash and error reports help fix bugs. API keys and player data are never sent.",
                isOn: $sentryEnabled
            )
            .onChange(of: sentryEnabled) { _, _ in
                SentryManager.applyState()
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SwitchRow(title: "Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { _ in launchAtLogin.toggle() }
            ))

            SettingChoiceRow(title: "Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            BoardRow {
                HStack(spacing: Board.Space.s) {
                    Text("Preferred browser")
                        .font(.boardBody)
                        .foregroundStyle(Board.ink)
                    Spacer(minLength: Board.Space.s)
                    Picker("Preferred browser", selection: $preferredBrowser) {
                        ForEach(availableBrowsers) { browser in
                            Text(browser.rawValue).tag(browser.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingChoiceRow(title: "Booster cooldown link") {
                Picker("Booster cooldown link", selection: $boosterCooldownTarget) {
                    ForEach(BoosterCooldownTarget.allCases, id: \.self) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            SwitchRow(
                title: "Private Island return icon",
                detail: "Shows the Private Island shortcut for the return trip. Quick Travel time is selected separately.",
                isOn: $privateIsland
            )

            SwitchRow(
                title: "Always reduce transparency",
                detail: "MacTorn already follows the Reduce transparency setting in System Settings, under Accessibility and Display. Turn this on to use solid backgrounds even when that setting is off.",
                isOn: $reduceTransparencyOverride
            )
            .help("MacTorn already follows System Settings, Accessibility, Display, Reduce transparency. "
                  + "Turn this on to use solid backgrounds even when that system setting is off.")
            .accessibilityHint("Forces solid backgrounds regardless of the system "
                               + "Reduce transparency setting")
        }
    }

    // MARK: - Diagnostics & About

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let update = appState.updateAvailable {
                BoardNotice(tone: .ready, message: "New version available: \(update.tagName)") {
                    Button("Download update") {
                        // Only a github.com link, whatever the API answered with. See
                        // `UpdateManager.allowedReleaseHosts`.
                        guard UpdateManager.isTrustedReleaseURL(update.htmlUrl),
                              let url = URL(string: update.htmlUrl) else { return }
                        BrowserManager.shared.open(url)
                    }
                    .buttonStyle(.board(.ready, fillsWidth: false))
                }
                .padding(.top, Board.Space.m)
                .padding(.bottom, Board.Space.s)
            }

            HStack(spacing: 6) {
                Button("Diagnostics") {
                    showDiagnostics = true
                }
                .buttonStyle(.boardFill)
                .accessibilityIdentifier("settings.diagnostics")

                Button("Credits") {
                    showCredits = true
                }
                .buttonStyle(.boardFill)

                Button("GitHub") {
                    BrowserManager.shared.open(URL(string: "https://github.com/pawelorzech/MacTorn")!)
                }
                .buttonStyle(.boardFill)
            }
            .padding(.vertical, Board.Space.m)

            Board.hairline.frame(height: 1)

            BoardRow {
                HStack(spacing: Board.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support the developer")
                            .font(.boardBody)
                            .foregroundStyle(Board.ink)
                        Text("Send Xanax or cash in Torn to help keep MacTorn going.")
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Board.Space.s)

                    Button("Send to bombel") {
                        openTornProfile()
                    }
                    .buttonStyle(.board)
                }
            }

            ValueRow(label: "MacTorn version", value: BuildInfo.appVersion, isFigure: false)
        }
    }

    // MARK: - Bindings

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
            get: { appState.forumWatch.config.pollingIntervalSeconds },
            set: { newValue in
                appState.forumWatch.setPollingInterval(newValue)
            }
        )
    }

    private var forumCategoryMonitorBinding: Binding<Bool> {
        Binding(
            get: { appState.forumWatch.config.factionForumAutoMonitor },
            set: { newValue in
                appState.forumWatch.setCategoryMonitoring(newValue)
            }
        )
    }

    private var forumCategoryIDBinding: Binding<String> {
        Binding(
            get: { appState.forumWatch.config.factionForumCategoryId.map(String.init) ?? "" },
            set: { newValue in
                appState.forumWatch.setCategory(PositiveIntegerInput.value(from: newValue))
            }
        )
    }

    private var trimmedInputKey: String {
        inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Block repeated refreshes for the current key, but still allow an account switch
    /// while its old request is in flight. Updating the key advances the account
    /// generation and cancels those stale tasks.
    private var canSaveKey: Bool {
        !trimmedInputKey.isEmpty
            && !(appState.isLoading && trimmedInputKey == appState.apiKey)
    }

    private func saveAndConnect() {
        appState.apiKey = trimmedInputKey
        guard appState.accountSession.persistenceError == nil else { return }
        appState.refreshNow()
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

    // MARK: - Pieces

    private var nextActionConfigSection: some View {
        BoardRow {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose which events appear in the Next up list.")
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)

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
                                .font(.boardBody)
                                .foregroundStyle(Board.ink)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.top, Board.Space.s)
            } label: {
                Text("Next up categories")
                    .font(.boardStrong)
                    .foregroundStyle(Board.ink)
            }
        }
    }

    @ViewBuilder
    private var keyValidationResult: some View {
        switch appState.keyValidation {
        case .idle, .validating:
            EmptyView()
        case .success(let result):
            let blocked = result.availability.filter { !$0.available }
            BoardNotice(
                tone: .ready,
                message: "\(result.accessType), player ID \(result.playerID)",
                detail: blocked.isEmpty
                    ? "All MacTorn features are available with this key."
                    : "Limited by your key. These features won't load: \(blocked.map(\.name).joined(separator: ", ")). Use a key with higher access to get them."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .uiTestID("uitest.keyValidationSuccess")
        case .failure(let message):
            BoardNotice(tone: .alert, message: message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .uiTestID("uitest.keyValidationFailure")
        }
    }

    private var apiUsageDisclosure: some View {
        BoardRow {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    disclosureLine(
                        "key.fill",
                        "Requires a Torn key with at least **\(TornEndpointRegistry.requiredAccessLevel.label)** for every feature. Lower access still works, and unavailable modules are shown after Test Connection."
                    )
                    disclosureLine(
                        "lock.fill",
                        "Your key is stored in the macOS **Keychain**, never in plaintext preferences."
                    )
                    disclosureLine(
                        "desktopcomputer",
                        "All Torn data stays **on this Mac**. MacTorn is read-only and never takes action on your account."
                    )
                    disclosureLine(
                        "exclamationmark.shield",
                        "Crash reporting is **opt-in** and off by default; no Torn data is sent."
                    )

                    Text("Selections requested")
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                    Text(TornEndpointRegistry.allSelections.joined(separator: ", "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Board.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("View Torn API terms of service") {
                        BrowserManager.shared.open(TornLink.page("api.html"))
                    }
                    .buttonStyle(.boardInline)
                }
                .padding(.top, Board.Space.s)
            } label: {
                Text("API data usage")
                    .font(.boardStrong)
                    .foregroundStyle(Board.ink)
            }
        }
    }

    private func disclosureLine(_ icon: String, _ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(.init(markdown))
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openTornProfile() {
        BrowserManager.shared.open(TornLink.profile(developerID))
    }
}

/// A setting that is a choice rather than a switch: its name, an optional explanation, and
/// the control under them on its own line.
private struct SettingChoiceRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        BoardRow {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.boardBody)
                    .foregroundStyle(Board.ink)
                control()
                if let detail {
                    Text(detail)
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
