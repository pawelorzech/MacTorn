import SwiftUI

/// The panel's navigation: every module one click away, down the left edge. Groups are
/// separated by a short rule rather than named — the icons carry the meaning, and the name
/// is in the tooltip, the accessibility label and the header of the screen it opens.
struct ModuleRail: View {
    @Environment(AppState.self) private var appState
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        VStack(spacing: 4) {
            ForEach(AppGroup.allCases, id: \.self) { group in
                if group != AppGroup.allCases.first {
                    Board.outline
                        .frame(width: 20, height: 1)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
                ForEach(group.tabs, id: \.self) { tab in
                    moduleButton(tab)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Modules")

            Spacer(minLength: Board.Space.s)

            moreMenu
            settingsButton
        }
        .padding(.vertical, 10)
        .frame(width: Board.railWidth)
        .frame(maxHeight: .infinity)
        .background(Board.rail)
        .overlay(alignment: .trailing) {
            Board.hairline.frame(width: 1)
        }
    }

    private func isSelected(_ tab: AppTab) -> Bool {
        !navigation.isShowingSettings && navigation.selectedTab == tab
    }

    private func moduleButton(_ tab: AppTab) -> some View {
        Button {
            navigation.select(tab)
        } label: {
            RailGlyph(systemImage: tab.icon, isSelected: isSelected(tab))
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
        .uiTestID("uitest.tab.\(tab.rawValue)")
    }

    private var settingsButton: some View {
        Button {
            navigation.toggleSettings()
        } label: {
            RailGlyph(systemImage: "slider.horizontal.3", isSelected: navigation.isShowingSettings)
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(navigation.isShowingSettings ? .isSelected : [])
        .uiTestID("uitest.openSettings")
    }

    /// Refresh, the keyboard map and Quit. Also where ⌘R, ⌘, and ⌘1–⌘9 are registered while
    /// the panel is open.
    private var moreMenu: some View {
        Menu {
            commandButton(.refresh)
            Divider()
            ForEach(MacTornCommand.navigation) { command in
                commandButton(command)
            }
            Divider()
            commandButton(.settings)
            Divider()
            Button("Quit MacTorn") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            RailGlyph(systemImage: "ellipsis", isSelected: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 32)
        .help("Commands and Quit")
        .accessibilityLabel("Commands")
        .accessibilityHint("Refresh, go to a module, open Settings or quit MacTorn")
    }

    private func commandButton(_ command: MacTornCommand) -> some View {
        Button(command.title) {
            switch command {
            case .refresh: appState.refreshNow()
            case .settings: navigation.showSettings()
            case .go(let tab): navigation.select(tab)
            }
        }
        .keyboardShortcut(KeyEquivalent(command.keyEquivalent), modifiers: .command)
        .disabled(command != .settings && appState.apiKey.isEmpty)
    }
}

private struct RailGlyph: View {
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Board.onAccent : Board.inkSecondary)
            .frame(width: 36, height: 32)
            .background(isSelected ? Board.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
