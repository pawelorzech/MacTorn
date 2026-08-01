import SwiftUI

enum AppGroup: String, CaseIterable {
    case now = "Now"
    case account = "Account"
    case watch = "Watch"

    var icon: String {
        switch self {
        case .now: return "bolt.fill"
        case .account: return "person.crop.circle"
        case .watch: return "eye.fill"
        }
    }

    var tabs: [AppTab] {
        switch self {
        case .now: return [.status, .travel, .attacks]
        case .account: return [.money, .properties, .stocks, .faction]
        case .watch: return [.watchlist, .forums]
        }
    }

    var defaultTab: AppTab {
        tabs[0]
    }
}

enum AppTab: String, CaseIterable {
    case status = "Status"
    case travel = "Travel"
    case money = "Money"
    case properties = "Properties"
    case stocks = "Stocks"
    case attacks = "Attacks"
    case faction = "Faction"
    case watchlist = "Watchlist"
    case forums = "Forums"

    var icon: String {
        switch self {
        case .status: return "chart.bar.fill"
        case .travel: return "airplane"
        case .money: return "dollarsign.circle.fill"
        case .properties: return "house.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .attacks: return "bolt.shield.fill"
        case .faction: return "person.3.fill"
        case .watchlist: return "chart.line.uptrend.xyaxis"
        case .forums: return "bubble.left.and.bubble.right.fill"
        }
    }

    var group: AppGroup {
        switch self {
        case .status, .travel, .attacks: return .now
        case .money, .properties, .stocks, .faction: return .account
        case .watchlist, .forums: return .watch
        }
    }
}

private enum NavigationFocus: Hashable {
    case group(AppGroup)
    case tab(AppTab)
    case settings
    case commands
    case quit
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.reduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var navigationFocus: NavigationFocus?
    @State private var showSentryOptIn = false

    /// The very first fetch, before any data has ever arrived. Only during this window
    /// is the module content made inert; every later refresh keeps the UI live because
    /// the previous snapshot is still on screen.
    private var isBlockingInitialLoad: Bool {
        appState.isLoading && appState.lastUpdated == nil
    }

    var body: some View {

        ZStack {
            VStack(spacing: 0) {
                Group {
                    if appState.apiKey.isEmpty || navigation.isShowingSettings {
                        SettingsView {
                            _ = navigation.dismissSettings(hasConfiguredAccount: !appState.apiKey.isEmpty)
                        }
                            .environment(appState)
                    } else {
                        // Header with last updated
                        headerView

                        // Two-level navigation: three stable groups and only the active
                        // group's modules. Every destination is at most two actions away.
                        groupBar
                        modulePicker

                        Divider()

                        // Content based on selected tab
                        tabContent
                    }
                }
                // Only the *content* is inert while the first load runs. The footer sits
                // outside this modifier on purpose: it holds Settings and Quit, and
                // disabling those left the user with no way out of a slow or hung first
                // fetch (URLSession's default timeout is 60 s) short of force-quitting.
                .disabled(isBlockingInitialLoad)

                Divider()
                    .padding(.vertical, 4)

                // Footer buttons — always interactive, see above.
                footerView
            }
            
            // Loading Overlay
            if isBlockingInitialLoad {
                (reduceTransparency ? Color(.windowBackgroundColor) : Color.black.opacity(0.4))
                    .background(reduceTransparency ? AnyShapeStyle(Color(.windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading Torn Data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .allowsHitTesting(false)
            }

            // Feedback Prompt Overlay
            if appState.showFeedbackPrompt {
                (reduceTransparency ? Color(.windowBackgroundColor) : Color.black.opacity(0.3))
                    .background(reduceTransparency ? AnyShapeStyle(Color(.windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))

                FeedbackPromptView()
                    .environment(appState)
            }

            // Sentry Opt-In Prompt Overlay
            if showSentryOptIn {
                (reduceTransparency ? Color(.windowBackgroundColor) : Color.black.opacity(0.3))
                    .background(reduceTransparency ? AnyShapeStyle(Color(.windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))

                SentryOptInPromptView(isPresented: $showSentryOptIn)
            }
        }
        .frame(width: 320, height: 640, alignment: .top)
        .environment(\.openMacTornSettings, OpenMacTornSettingsAction {
            navigation.showSettings()
        })
        .onExitCommand(perform: handleEscape)
        .onAppear {
            appState.startPolling()
            appState.startForumPolling()
            checkSentryOptInPrompt()
        }
        .task {
            // Skip system-permission prompts and the update-check network call under the
            // UI-test harness so runs stay hermetic and no modal steals focus.
            guard !UITestConfiguration.isActive else { return }
            await NotificationManager.shared.requestPermission()
            appState.checkForAppUpdates()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            if let lastUpdated = appState.lastUpdated {
                Text("Updated: \(lastUpdated, formatter: Self.timeFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Navigation
    private var currentGroup: AppGroup {
        currentTab.group
    }

    private var selectedBackgroundOpacity: Double {
        reduceTransparency || colorSchemeContrast == .increased ? 0.35 : 0.16
    }

    private var groupBar: some View {
        HStack(spacing: 6) {
            ForEach(AppGroup.allCases, id: \.self) { group in
                Button {
                    guard currentGroup != group else { return }
                    navigation.select(group.defaultTab)
                } label: {
                    Label {
                        Text(group.rawValue)
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: group.icon)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(currentGroup == group
                                ? Color.accentColor.opacity(selectedBackgroundOpacity)
                                : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(navigationFocus == .group(group)
                                    ? Color.accentColor
                                    : Color.clear,
                                    lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .focused($navigationFocus, equals: .group(group))
                .foregroundColor(currentGroup == group ? .accentColor : .secondary)
                .accessibilityLabel("\(group.rawValue) group")
                .accessibilityAddTraits(currentGroup == group ? .isSelected : [])
                .uiTestID("uitest.group.\(group.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }

    private var modulePicker: some View {
        HStack(spacing: 6) {
            ForEach(currentGroup.tabs, id: \.self) { tab in
                Button {
                    navigation.select(tab)
                } label: {
                    Text(tab.rawValue)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(currentTab == tab
                                    ? Color.accentColor.opacity(selectedBackgroundOpacity)
                                    : Color.secondary.opacity(reduceTransparency ? 0.12 : 0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(moduleBorderColor(for: tab),
                                        lineWidth: navigationFocus == .tab(tab) ? 2 : 1)
                        }
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($navigationFocus, equals: .tab(tab))
                .foregroundColor(currentTab == tab ? .accentColor : .secondary)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(currentTab == tab ? .isSelected : [])
                .uiTestID("uitest.tab.\(tab.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(currentGroup.rawValue) modules")
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }
    
    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        tabContentBody
            // A single element whose identifier tracks the active tab, so a UI test can
            // assert navigation actually switched content (Etap G).
            .uiTestID("uitest.tabContent.\(currentTab.rawValue)")
    }

    @ViewBuilder
    private var tabContentBody: some View {
        switch currentTab {
        case .status:
            StatusView()
                .environment(appState)
        case .travel:
            TravelView()
                .environment(appState)
        case .money:
            MoneyView()
                .environment(appState)
        case .properties:
            PropertiesView()
                .environment(appState)
        case .stocks:
            StocksView()
                .environment(appState)
        case .attacks:
            AttacksView()
                .environment(appState)
        case .faction:
            FactionView()
                .environment(appState)
        case .watchlist:
            WatchlistView()
                .environment(appState)
        case .forums:
            ForumWatchView()
                .environment(appState)
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            if !appState.apiKey.isEmpty {
                Button(navigation.isShowingSettings ? "Back" : "Settings") {
                    navigation.toggleSettings()
                }
                .buttonStyle(.plain)
                .focused($navigationFocus, equals: .settings)
                .foregroundColor(.secondary)
                .uiTestID("uitest.openSettings")
            }
            
            Spacer()

            commandMenu

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .focused($navigationFocus, equals: .quit)
            .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var commandMenu: some View {
        Menu {
            commandButton(.refresh)

            Divider()

            ForEach(MacTornCommand.navigation) { command in
                commandButton(command)
            }

            Divider()

            commandButton(.settings)
        } label: {
            Label("Commands", systemImage: "command")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focused($navigationFocus, equals: .commands)
        .accessibilityLabel("Commands")
        .accessibilityHint("Refresh, open Settings, or go directly to a module")
    }

    private func commandButton(_ command: MacTornCommand) -> some View {
        Button(command.title) {
            perform(command)
        }
        .keyboardShortcut(KeyEquivalent(command.keyEquivalent), modifiers: .command)
        .disabled(command != .settings && appState.apiKey.isEmpty)
    }

    private func perform(_ command: MacTornCommand) {
        switch command {
        case .refresh:
            appState.refreshNow()
        case .settings:
            navigation.showSettings()
        default:
            if let tab = command.tab {
                navigation.select(tab)
            }
        }
    }

    private func handleEscape() {
        if showSentryOptIn {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            UserDefaults.standard.set(version, forKey: SentryManager.promptShownKey)
            showSentryOptIn = false
            return
        }
        if appState.showFeedbackPrompt {
            appState.feedbackDismissed()
            return
        }
        _ = navigation.dismissSettings(hasConfiguredAccount: !appState.apiKey.isEmpty)
    }

    private func moduleBorderColor(for tab: AppTab) -> Color {
        if navigationFocus == .tab(tab) {
            return .accentColor
        }
        if currentTab == tab && colorSchemeContrast == .increased {
            return .accentColor
        }
        return .clear
    }
    
    private func checkSentryOptInPrompt() {
        guard !UITestConfiguration.isActive else { return }
        guard !appState.apiKey.isEmpty else { return }
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let shownFor = UserDefaults.standard.string(forKey: SentryManager.promptShownKey) ?? ""
        if shownFor != currentVersion && !SentryManager.isEnabled {
            showSentryOptIn = true
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var currentTab: AppTab {
        navigation.selectedTab
    }
}
