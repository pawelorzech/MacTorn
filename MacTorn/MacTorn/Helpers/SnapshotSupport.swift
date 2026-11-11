#if DEBUG
import AppKit
import SwiftUI

// MARK: - Offscreen snapshots
//
// `--uitesting -uitest-snapshots <dir>` renders every screen of the panel to PNG files from
// the fixture world and quits. Nothing is shown on screen and nothing is activated, so it is
// safe to run while someone is working on the Mac — unlike XCUITest, which takes the screen.
// This is how a visual change gets looked at as pixels rather than read as code.
//
//   -uitest-snapshots <dir|name>        enables the mode. An absolute path is used as is, which
//                                       needs a build without the App Sandbox
//                                       (CODE_SIGN_ENTITLEMENTS=""); a bare name lands in the
//                                       sandbox container under tmp/MacTornSnapshots/<name>
//   -uitest-snapshot-screens a,b,c      subset: tab names, "Settings", "Settings-<section>", "Diagnostics", "Credits",
//                                       "FeedbackPrompt", "SentryPrompt"
//   -uitest-snapshot-appearance light   "light", "dark" or both when absent
//   -uitest-window-height 1400          taller than the panel, to see below the fold
//   -uitest-snapshot-seed 0             only what the canned network returns (modules off)
//   -uitest-snapshot-healthy 1          forget endpoint failures before drawing. The canned
//                                       network answers most calls with an empty object, so
//                                       every tab otherwise carries a "Stale" notice; this
//                                       is for screenshots of the app working normally
//   -uitest-fixture / -uitest-apikey    as for UI tests; no key renders onboarding

extension UITestConfiguration {
    static let snapshotKey = "-uitest-snapshots"
    static let snapshotScreensKey = "-uitest-snapshot-screens"
    static let snapshotAppearanceKey = "-uitest-snapshot-appearance"
    static let snapshotSeedKey = "-uitest-snapshot-seed"

    /// "0" renders only what the canned network returns: optional modules off, lists
    /// empty. Anything else (the default) adds `SnapshotFixtures`.
    static var snapshotSeedsExtras: Bool { snapshotArgument(snapshotSeedKey) != "0" }
    static var snapshotForgetsFailures: Bool { snapshotArgument("-uitest-snapshot-healthy") == "1" }

    private static func snapshotArgument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var snapshotDirectory: URL? {
        snapshotArgument(snapshotKey).map {
            if $0.hasPrefix("/") { return URL(fileURLWithPath: $0, isDirectory: true) }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MacTornSnapshots", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
        }
    }

    /// The UI-test window is for XCUITest. A snapshot run draws offscreen instead.
    static var showsTestWindow: Bool { isActive && snapshotDirectory == nil }

    static var snapshotScreens: [String]? {
        snapshotArgument(snapshotScreensKey)?.split(separator: ",").map { String($0).lowercased() }
    }

    static var snapshotAppearances: [(name: String, appearance: NSAppearance)] {
        let all: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        let wanted = snapshotArgument(snapshotAppearanceKey)
        return all.filter { wanted == nil || wanted == $0.0 }
            .compactMap { name, id in NSAppearance(named: id).map { (name, $0) } }
    }
}

@MainActor
enum SnapshotRunner {
    private enum Screen {
        case tab(AppTab)
        case settings(SettingsSection?)
        case diagnostics
        case credits
        case feedbackPrompt
        case sentryPrompt

        var name: String {
            switch self {
            case .tab(let tab): return tab.rawValue
            case .settings(let section): return section.map { "Settings-\($0.id)" } ?? "Settings"
            case .diagnostics: return "Diagnostics"
            case .credits: return "Credits"
            case .feedbackPrompt: return "FeedbackPrompt"
            case .sentryPrompt: return "SentryPrompt"
            }
        }
    }

    static func run(into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appState = UITestConfiguration.makeAppState()
        let hasAccount = !appState.apiKey.isEmpty
        if hasAccount {
            appState.startPolling()
            try? await Task.sleep(for: .seconds(1.5))
        }

        var screens: [Screen] = hasAccount ? AppTab.inNavigationOrder.map(Screen.tab) : []
        screens += hasAccount ? SettingsSection.allCases.map { .settings($0) } : [.settings(nil)]
        screens += [.diagnostics, .credits, .feedbackPrompt, .sentryPrompt]
        if let wanted = UITestConfiguration.snapshotScreens {
            screens = screens.filter { wanted.contains($0.name.lowercased()) }
        }

        for screen in screens {
            let navigation = AppNavigationState()
            switch screen {
            case .tab(let tab):
                navigation.select(tab)
            case .settings(let section):
                navigation.showSettings(section)
            case .diagnostics, .credits, .feedbackPrompt, .sentryPrompt:
                break
            }
            for (appearanceName, appearance) in UITestConfiguration.snapshotAppearances {
                if hasAccount, UITestConfiguration.snapshotSeedsExtras { SnapshotFixtures.seed(appState) }
                if UITestConfiguration.snapshotForgetsFailures {
                    appState.requester.health.reset()
                    appState.errorMsg = nil
                }
                let root = rootView(for: screen, appState: appState, navigation: navigation)
                let file = directory.appendingPathComponent("\(screen.name)-\(appearanceName).png")
                await render(root, appearance: appearance, to: file)
            }
        }
    }

    /// The panel for tabs and Settings; the sheet, the credits page and the two modal prompts
    /// are drawn directly, on the surface they sit on in the app.
    private static func rootView(for screen: Screen, appState: AppState, navigation: AppNavigationState) -> AnyView {
        switch screen {
        case .tab, .settings:
            return AnyView(ContentView()
                .macTornRoot(appState, navigation: navigation)
                .frame(height: UITestConfiguration.windowHeight))
        case .diagnostics:
            return AnyView(DiagnosticsView(appState: appState)
                .macTornRoot(appState, navigation: navigation)
                .background(Board.surface))
        case .credits:
            return AnyView(CreditsView(showCredits: .constant(true))
                .frame(width: Board.panelWidth, height: Board.panelHeight)
                .macTornRoot(appState, navigation: navigation)
                .background(Board.surface))
        case .feedbackPrompt:
            return AnyView(FeedbackPromptView()
                .padding(Board.Space.xl)
                .frame(width: Board.panelWidth)
                .macTornRoot(appState, navigation: navigation)
                .background(Board.surface))
        case .sentryPrompt:
            return AnyView(SentryOptInPromptView(isPresented: .constant(true))
                .padding(Board.Space.xl)
                .frame(width: Board.panelWidth)
                .macTornRoot(appState, navigation: navigation)
                .background(Board.surface))
        }
    }

    private static func render(_ root: some View, appearance: NSAppearance, to file: URL) async {
        let host = NSHostingView(rootView: root)
        let size = host.fittingSize
        let frame = NSRect(x: 0, y: 0, width: max(size.width, 200), height: max(size.height, 200))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        // Far outside any display: the window has to be ordered in for SwiftUI to lay out
        // and fire `onAppear`, but it must never be visible or take focus.
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(450))

        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
        }
        window.close()
    }
}

/// Data the canned network world does not carry: the optional modules, activity and the
/// lists a player builds themselves. Seeded straight into the stores, after the first poll.
@MainActor
enum SnapshotFixtures {
    static func seed(_ app: AppState) {
        let now = Int(Date().timeIntervalSince1970)
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
            try? decoder.decode(type, from: Data(json.utf8))
        }

        let player = app.player
        player.moneyData = MoneyData(cash: 1_840_500, vault: 62_000_000, points: 1_250, tokens: 14, cayman: 250_000_000)
        player.battleStats = BattleStats(strength: 1_204_332_118, defense: 987_654_321, speed: 1_102_938_475, dexterity: 845_112_009)
        player.notificationCounts = TornNotifications(messages: 2, events: 5, awards: 1, competition: 0)
        player.refills = Refills(energy: true, nerve: false, token: false, specialCount: 0)
        player.education = EducationStatus(complete: [], current: CurrentEducation(id: 12, until: now + 183_600))
        if player.recentAttacks == nil {
            player.recentAttacks = [
                AttackResult(code: "snap-1", timestampStarted: now - 900, timestampEnded: now - 880,
                             attackerId: 123_456, attackerName: "TestPlayer", defenderId: 654_321,
                             defenderName: "Duke", result: "Mugged", respect: 2.5),
                AttackResult(code: "snap-2", timestampStarted: now - 5_400, timestampEnded: now - 5_380,
                             attackerId: 777_777, attackerName: "Leslie", defenderId: 123_456,
                             defenderName: "TestPlayer", result: "Hospitalized", respect: 1.25),
                AttackResult(code: "snap-3", timestampStarted: now - 86_000, timestampEnded: now - 85_990,
                             attackerId: 123_456, attackerName: "TestPlayer", defenderId: 222_333,
                             defenderName: "Scrooge", result: "Attacked", respect: 3.1),
            ]
        }
        if player.propertiesData == nil {
            player.propertiesData = [
                PropertyInfo(id: 9101, propertyType: "Private Island", status: "Owned by you", cost: 500_000_000,
                             marketprice: 750_000_000, happy: 4_225, rented: false, rentDaysLeft: 0),
                PropertyInfo(id: 9102, propertyType: "Castle", status: "Rented from Duke", cost: 25_000_000,
                             marketprice: 40_000_000, happy: 2_000, rented: true, rentDaysLeft: 2),
            ]
        }
        if player.activityEvents.isEmpty {
            let events = [
                (9001, now - 90, "You were mugged by <a href=\\\"#\\\">Leslie</a> for $500."),
                (9002, now - 3_700, "Your item <b>Xanax</b> was bought from your bazaar for $835,000."),
                (9003, now - 40_000, "You have been awarded the <b>Globetrotter</b> honor bar."),
            ]
            player.activityEvents = events.compactMap { id, timestamp, text in
                decode(TornEvent.self, #"{"timestamp": \#(timestamp), "event": "\#(text)"}"#)?.identified(by: String(id))
            }
        }

        // Always re-seeded: the canned network world answers market and forum calls with
        // an empty object, which the stores rightly record as an error on every item.
        do {
            app.watchlist.items = [
                WatchlistItem(id: 206, name: "Xanax", lowestPrice: 834_500, lowestPriceQuantity: 12,
                              secondLowestPrice: 835_000, lastUpdated: Date(), error: nil, priceThreshold: 850_000),
                WatchlistItem(id: 367, name: "Feathery Hotel Coupon", lowestPrice: 13_950_000, lowestPriceQuantity: 1,
                              secondLowestPrice: 14_100_000, lastUpdated: Date().addingTimeInterval(-1_900), error: nil),
                WatchlistItem(id: 283, name: "Donator Pack", lowestPrice: 0, lowestPriceQuantity: 0,
                              secondLowestPrice: 0, lastUpdated: nil, error: "Item market unavailable."),
            ]
        }
        do {
            app.forumWatch.threads = [
                WatchedThread(id: 101, title: "Elimination 2026: team recruitment megathread", notificationsEnabled: true,
                              lastKnownPostCount: 482, lastChecked: Date(), error: nil),
                WatchedThread(id: 102, title: "API changes: November", notificationsEnabled: false,
                              lastKnownPostCount: 37, lastChecked: Date().addingTimeInterval(-700), error: nil),
                WatchedThread(id: 103, title: "A thread that was removed", notificationsEnabled: true,
                              lastKnownPostCount: 3, lastChecked: Date(), error: "Thread unavailable."),
            ]
        }

        let companion = app.companion
        companion.enabled = Set(CompanionStore.Feature.allCases)
        companion.errors = [:]
        for id in CompanionStore.Feature.allCases.flatMap(\.endpointIDs) {
            companion.fetchedAt[id] = Date().addingTimeInterval(-26)
        }
        companion.competition = decode(CompetitionV2.self,
            #"{"name": "Rock, Paper, Scissors", "status": "scissors", "hp": {"current": 890, "maximum": 890}}"#)
        let day = 86_400
        let calendar = [
            ("World Diabetes Day", now + 3 * day, now + 4 * day, false),
            ("Torn Anniversary", now + 3 * day + 3_600, now + 4 * day, false),
            ("Black Friday", now + 16 * day, now + 17 * day, false),
        ]
        companion.calendarActivities = calendar.compactMap { title, start, end, isCompetition in
            decode(CalendarActivity.self,
                   #"{"title": "\#(title)", "description": "", "start": \#(start), "end": \#(end), "fixed_start_time": true}"#)
                .map { ($0, isCompetition) }
        }
        companion.shops = decode([ShopItem].self, """
        [
          {"id": 1, "name": "Ash Tray", "value": {"market_price": 809198, "shops": [{"country": "Torn", "shop": "Recycling Center", "buy_price": null, "sell_price": null}]}},
          {"id": 2, "name": "ATM Key", "value": {"market_price": 200358, "shops": [{"country": "Torn", "shop": "Print Shop", "buy_price": null, "sell_price": null}]}},
          {"id": 3, "name": "Axe", "value": {"market_price": 2846, "shops": [{"country": "Mexico", "shop": "Arms Dealer", "buy_price": 4200, "sell_price": 2100}, {"country": "Torn", "shop": "Big Al's Gun Shop", "buy_price": null, "sell_price": null}]}},
          {"id": 4, "name": "Bag of Bloody Eyeballs", "value": {"market_price": 50625, "shops": [{"country": "Torn", "shop": "Sally's Sweet Shop", "buy_price": null, "sell_price": null}]}},
          {"id": 5, "name": "Bag of Bon Bons", "value": {"market_price": 834, "shops": [{"country": "Torn", "shop": "Sally's Sweet Shop", "buy_price": null, "sell_price": null}]}},
          {"id": 6, "name": "Bag of Candy Kisses", "value": {"market_price": 37183, "shops": [{"country": "Torn", "shop": "Sally's Sweet Shop", "buy_price": null, "sell_price": null}]}},
          {"id": 7, "name": "Bag of Chocolate Kisses", "value": {"market_price": 856, "shops": [{"country": "Torn", "shop": "Sally's Sweet Shop", "buy_price": 150, "sell_price": 75}]}},
          {"id": 8, "name": "Xanax", "value": {"market_price": 834500, "shops": [{"country": "Japan", "shop": "Pharmacy", "buy_price": 760000, "sell_price": null}, {"country": "South Africa", "shop": "Pharmacy", "buy_price": 752000, "sell_price": null}]}},
          {"id": 9, "name": "Dahlia", "value": {"market_price": 3120, "shops": [{"country": "Mexico", "shop": "Flower Stall", "buy_price": 300, "sell_price": null}]}},
          {"id": 10, "name": "Camel Plushie", "value": {"market_price": 61250, "shops": [{"country": "UAE", "shop": "Toy Shop", "buy_price": 14000, "sell_price": null}]}}
        ]
        """) ?? []
        companion.trades = decode([TradeV2].self, """
        [{"id": 88231, "user": {"id": 123456, "name": "TestPlayer"}, "trader": {"id": 777, "name": "Duke"},
          "description": "Plushie set for cash", "completed_at": null, "expires_at": \(now + 20_000), "modified_at": \(now - 600)}]
        """) ?? []
        companion.stocks = decode([StockV2].self, """
        [{"id": 1, "shares": 3000000, "bonus": {"available": true, "increment": 1, "progress": 31, "frequency": 31},
          "transactions": [{"id": 1, "shares": 3000000, "price": 310.5, "timestamp": \(now - 9_000_000)}]},
         {"id": 2, "shares": 1500000, "bonus": {"available": false, "increment": 1, "progress": 12, "frequency": 7},
          "transactions": [{"id": 2, "shares": 1500000, "price": 512.25, "timestamp": \(now - 4_000_000)}]}]
        """) ?? []
        companion.stockReferences = decode([StockReferenceV2].self, """
        [{"id": 1, "name": "Torn & Shanghai Banking", "acronym": "TSB", "market": {"price": 1088.42},
          "bonus": {"passive": false, "frequency": 31, "requirement": 3000000, "description": "$50,000,000"}},
         {"id": 2, "name": "Feathery Hotels Group", "acronym": "FHG", "market": {"price": 1304.9},
          "bonus": {"passive": false, "frequency": 7, "requirement": 2000000, "description": "1x Feathery Hotel Coupon"}}]
        """) ?? []
        companion.recruiting = decode([RecruitingCrime].self, """
        [{"id": 501, "name": "Break the Bank", "status": "Recruiting", "slots": [
          {"position": "Muscle", "position_info": {"id": "muscle", "label": "Muscle #2"}, "checkpoint_pass_rate": 78, "user": null},
          {"position": "Thief", "position_info": {"id": "thief", "label": "Thief #1"}, "checkpoint_pass_rate": 64, "user": null}]}]
        """) ?? []
    }
}
#endif
