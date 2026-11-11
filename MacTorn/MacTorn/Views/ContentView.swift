import SwiftUI

/// The whole panel: the module rail on the left, and beside it either a module under its
/// header or Settings. The menu bar and the window a widget opens both show exactly this.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppNavigationState.self) private var navigation
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

    private var currentTab: AppTab {
        navigation.selectedTab
    }

    var body: some View {
        ZStack {
            panel
                // A prompt overlay is modal: hide what's underneath from VoiceOver and keep
                // the keyboard/pointer from reaching it until the prompt is answered.
                .accessibilityHidden(isShowingModalPrompt)
                .disabled(isShowingModalPrompt)

            // Feedback Prompt Overlay — the Sentry opt-in wins when both are due, so at
            // most one modal is on screen; feedback shows once the opt-in is dismissed.
            if appState.showFeedbackPrompt && !showSentryOptIn {
                BoardScrim()

                FeedbackPromptView()
                    .accessibilityAddTraits(.isModal)
            }

            if showSentryOptIn {
                BoardScrim()

                SentryOptInPromptView(isPresented: $showSentryOptIn)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .frame(width: Board.panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.surface)
        .tint(Board.accent)
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

    // MARK: - Panel

    @ViewBuilder
    private var panel: some View {
        if appState.apiKey.isEmpty {
            // First run: there is nothing to navigate to yet, so no rail.
            SettingsView()
        } else {
            HStack(spacing: 0) {
                ModuleRail()

                VStack(spacing: 0) {
                    if navigation.isShowingSettings {
                        SettingsView {
                            _ = navigation.dismissSettings(hasConfiguredAccount: true)
                        }
                    } else {
                        header

                        if isBlockingInitialLoad {
                            loadingState
                        } else {
                            // `.top`, not the default centre, so a module shorter than
                            // the panel starts under the header instead of floating.
                            tabContent
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Header

    /// What you are looking at, how fresh it is, and the one way to make it fresher.
    private var header: some View {
        HStack(alignment: .top, spacing: Board.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.boardTitle)
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if currentTab == .status {
                    PlayerStateLine()
                }
            }

            Spacer(minLength: Board.Space.s)

            if let lastUpdated = appState.player.lastUpdated {
                Text(lastUpdated, formatter: Self.timeFormatter)
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
                    .padding(.top, 6)
                    .accessibilityLabel("Updated \(Self.timeFormatter.string(from: lastUpdated))")
            }

            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                IconButton(systemImage: "arrow.clockwise", label: "Refresh Torn data") {
                    appState.refreshNow()
                }
            }
        }
        .padding(.leading, Board.gutter)
        .padding(.trailing, Board.Space.m)
        .padding(.top, Board.Space.m)
        .padding(.bottom, Board.Space.m)
    }

    /// Status is "you", so it is headed by the player's name; every other module by its own.
    private var headerTitle: String {
        if currentTab == .status, let name = appState.player.data?.name {
            return name
        }
        return currentTab.rawValue
    }

    private var loadingState: some View {
        VStack(spacing: Board.Space.m) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading Torn data")
                .font(.boardCaption)
                .foregroundStyle(Board.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        tabContentBody
            // A single element whose identifier tracks the active tab, so a UI test can
            // assert navigation actually switched content.
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

    // MARK: - Events

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
}
