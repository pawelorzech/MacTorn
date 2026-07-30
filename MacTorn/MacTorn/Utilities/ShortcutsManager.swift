import Foundation
import Observation
import SwiftUI

/// The stable keyboard contract for MacTorn itself. Torn website shortcuts remain
/// user-customizable below; app navigation intentionally uses fixed, conflict-free
/// command-number pairs so every module is directly reachable.
enum MacTornCommand: String, CaseIterable, Identifiable {
    case refresh
    case settings
    case status
    case travel
    case attacks
    case money
    case faction
    case watchlist
    case forums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refresh: return "Refresh"
        case .settings: return "Settings…"
        case .status: return "Go to Status"
        case .travel: return "Go to Travel"
        case .attacks: return "Go to Attacks"
        case .money: return "Go to Money"
        case .faction: return "Go to Faction"
        case .watchlist: return "Go to Watchlist"
        case .forums: return "Go to Forums"
        }
    }

    var keyEquivalent: Character {
        switch self {
        case .refresh: return "r"
        case .settings: return ","
        case .status: return "1"
        case .travel: return "2"
        case .attacks: return "3"
        case .money: return "4"
        case .faction: return "5"
        case .watchlist: return "6"
        case .forums: return "7"
        }
    }

    var tab: AppTab? {
        switch self {
        case .status: return .status
        case .travel: return .travel
        case .attacks: return .attacks
        case .money: return .money
        case .faction: return .faction
        case .watchlist: return .watchlist
        case .forums: return .forums
        case .refresh, .settings: return nil
        }
    }

    static var navigation: [MacTornCommand] {
        allCases.filter { $0.tab != nil }
    }
}

/// Shared by the menu-bar popover and the macOS command menu. Keeping selection and
/// Settings presentation in one observable object prevents keyboard commands and clicks
/// from drifting into different destinations.
@Observable
final class AppNavigationState {
    private(set) var selectedTab: AppTab
    private(set) var isShowingSettings: Bool

    init(selectedTab: AppTab = .status, isShowingSettings: Bool = false) {
        self.selectedTab = selectedTab
        self.isShowingSettings = isShowingSettings
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
        isShowingSettings = false
    }

    func showSettings() {
        isShowingSettings = true
    }

    func toggleSettings() {
        isShowingSettings.toggle()
    }

    @discardableResult
    func dismissSettings(hasConfiguredAccount: Bool) -> Bool {
        guard hasConfiguredAccount, isShowingSettings else { return false }
        isShowingSettings = false
        return true
    }
}

@MainActor
class ShortcutsManager: ObservableObject {
    @Published var shortcuts: [KeyboardShortcut] = []
    
    private let storageKey = "customShortcuts"
    
    init() {
        loadShortcuts()
    }
    
    func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            shortcuts = saved
        } else {
            shortcuts = KeyboardShortcut.defaults
            saveShortcuts()
        }
    }
    
    func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    func updateShortcut(_ shortcut: KeyboardShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
            saveShortcuts()
        }
    }
    
    func resetToDefaults() {
        shortcuts = KeyboardShortcut.defaults
        saveShortcuts()
    }
    
    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        BrowserManager.shared.open(url)
    }
}
