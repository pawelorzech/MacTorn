import SwiftUI

private enum NavigationFocus: Hashable {
    case group(AppGroup)
    case tab(AppTab)
    case settings
    case commands
    case quit
}

/// Full-panel backdrop behind a blocking overlay: an opaque window colour under
/// Reduce Transparency, otherwise a dimmed blur.
private struct ModalScrim: View {
    var dimming: Double = 0.3
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        (reduceTransparency ? Color(.windowBackgroundColor) : Color.black.opacity(dimming))
            .background(reduceTransparency ? AnyShapeStyle(Color(.windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
    }
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
        appState.isLoading && appState.player.lastUpdated == nil
    }

    private var isShowingModalPrompt: Bool {
        appState.showFeedbackPrompt || showSentryOptIn
    }

    var body: some View {

        ZStack {
            VStack(spacing: 0) {
                Group {
                    if appState.apiKey.isEmpty || navigation.isShowingSettings {
                        SettingsView {
                            _ = navigation.dismissSettings(hasConfiguredAccount: !appState.apiKey.isEmpty)
                        }
                    } else {
                        // Header with last updated
                        headerView

                        // Two-level navigation: three stable groups and only the active
                        // group's modules. Every destination is at most two actions away.
                        groupBar
                        modulePicker

                        Divider()

                        // Content based on selected tab.
                        //
                        // The expansion belongs here and nowhere higher. `Group` applies a
                        // modifier to each of its children *separately*, so putting
                        // `maxHeight: .infinity` on the enclosing Group handed an infinite
                        // height to the header, the group bar, the module picker and the
                        // divider as well, and the VStack shared the window out between all
                        // five. Only the scrolling content should absorb the slack.
                        tabContent
                            .disabled(isBlockingInitialLoad)
                            // `.top`, not the default centre: `TravelView` is a plain
                            // VStack rather than a ScrollView, so centring would float its
                            // content in the middle of the panel. Scroll views fill the
                            // space either way and are unaffected.
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                Divider()
                    .padding(.vertical, 4)

                // Footer buttons — always interactive, see above.
                footerView
            }
            // A prompt overlay is modal: hide what's underneath from VoiceOver and keep
            // the keyboard/pointer from reaching it until the prompt is answered.
            .accessibilityHidden(isShowingModalPrompt)
            .disabled(isShowingModalPrompt)
            
            // Loading Overlay
            if isBlockingInitialLoad && !navigation.isShowingSettings {
                ModalScrim(dimming: 0.4)
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

            // Feedback Prompt Overlay — the Sentry opt-in wins when both are due, so at
            // most one modal is on screen; feedback shows once the opt-in is dismissed.
            if appState.showFeedbackPrompt && !showSentryOptIn {
                ModalScrim()

                FeedbackPromptView()
                    .accessibilityAddTraits(.isModal)
            }

            // Sentry Opt-In Prompt Overlay
            if showSentryOptIn {
                ModalScrim()

                SentryOptInPromptView(isPresented: $showSentryOptIn)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
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
            await appState.notifier.requestPermission()
            appState.checkForAppUpdates()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            if let lastUpdated = appState.player.lastUpdated {
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
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .overlay {
                        Capsule()
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
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(moduleBorderColor(for: tab),
                                        lineWidth: navigationFocus == .tab(tab) ? 2 : 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
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
        case .travel:
            TravelView()
        case .money:
            MoneyView()
        case .properties:
            PropertiesView()
        case .stocks:
            StocksView()
        case .attacks:
            AttacksView()
        case .faction:
            FactionView()
        case .watchlist:
            WatchlistView()
        case .forums:
            ForumWatchView()
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
            // Spelled out as an HStack rather than a `Label`, because a `Label` is
            // re-rendered by the menu style and loses the font set on it.
            HStack(spacing: 3) {
                Image(systemName: "command")
                Text("Commands")
            }
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        // `Menu` is an NSPopUpButton underneath and takes its font from the control size,
        // not from `.font` on the label — which is why stating the font alone left
        // "Commands" visibly larger than the "Settings" and "Quit" beside it. `.small`
        // shrinks the control itself, including the disclosure chevron, so the whole item
        // matches the footer instead of just its text.
        .controlSize(.small)
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
        case .refresh: appState.refreshNow()
        case .settings: navigation.showSettings()
        case .go(let tab): navigation.select(tab)
        }
    }

    private func handleEscape() {
        if showSentryOptIn {
            SentryManager.markPromptShown()
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
        guard !appState.apiKey.isEmpty else { return }
        if SentryManager.isPromptDue {
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
