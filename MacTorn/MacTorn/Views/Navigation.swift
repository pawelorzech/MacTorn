import Foundation
import Observation

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

    /// Display order within the group, and — flattened — the order of the ⌘1…⌘9 shortcuts.
    var tabs: [AppTab] {
        switch self {
        case .now: return [.status, .travel, .attacks]
        case .account: return [.money, .properties, .stocks, .faction]
        case .watch: return [.watchlist, .forums]
        }
    }

    var defaultTab: AppTab { tabs[0] }

    static func group(of tab: AppTab) -> AppGroup {
        allCases.first { $0.tabs.contains(tab) } ?? .now
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

    static var inNavigationOrder: [AppTab] { AppGroup.allCases.flatMap(\.tabs) }

    /// `mactorn://travel` and friends: the lowercased tab name.
    init?(route: String) {
        guard let tab = AppTab.allCases.first(where: { $0.rawValue.lowercased() == route.lowercased() }) else {
            return nil
        }
        self = tab
    }

    var icon: String {
        switch self {
        case .status: return "chart.bar.fill"
        case .travel: return "airplane"
        case .money: return "dollarsign.circle.fill"
        case .properties: return "house.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .attacks: return "bolt.shield.fill"
        case .faction: return "person.3.fill"
        case .watchlist: return "tag.fill"
        case .forums: return "bubble.left.and.bubble.right.fill"
        }
    }

    var group: AppGroup { AppGroup.group(of: self) }
}

/// The keyboard contract for MacTorn itself, shared by the macOS command menu and the
/// popover's Commands menu. Torn website shortcuts are separate and user-customisable.
enum MacTornCommand: Hashable, Identifiable {
    case refresh
    case settings
    case go(AppTab)

    static var navigation: [MacTornCommand] { AppTab.inNavigationOrder.map(MacTornCommand.go) }

    var id: String {
        switch self {
        case .refresh: return "refresh"
        case .settings: return "settings"
        case .go(let tab): return "go.\(tab.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .refresh: return "Refresh"
        case .settings: return "Settings…"
        case .go(let tab): return "Go to \(tab.rawValue)"
        }
    }

    var keyEquivalent: Character {
        switch self {
        case .refresh: return "r"
        case .settings: return ","
        case .go(let tab):
            let position = AppTab.inNavigationOrder.firstIndex(of: tab)! + 1
            return Character(String(position))
        }
    }

    var tab: AppTab? {
        if case .go(let tab) = self { return tab }
        return nil
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

