import Foundation
import SwiftUI

// MARK: - UI-test accessibility identifiers (always compiled? no — DEBUG only)

extension View {
    /// Applies an accessibility identifier used solely by the UI-test harness. Compiled
    /// out of Release, so no automation identifiers ship in the production binary while the
    /// UI tests (built Debug) still see them.
    @ViewBuilder func uiTestID(_ identifier: String) -> some View {
        #if DEBUG
        self.accessibilityIdentifier(identifier)
        #else
        self
        #endif
    }
}

// MARK: - UI-test harness (Etap G / ISC-20)
//
// A deterministic, hermetic harness for XCUITest runs. The production app never
// exercises any of this: it only activates when the process is launched with the
// `--uitesting` argument, which only the UI-test runner passes.
//
// Everything that fabricates data or bypasses real I/O is compiled **only in DEBUG**,
// so no fixture/test surface ships in a Release build. A tiny always-compiled shim
// (`#else` branch at the bottom) keeps `UITestConfiguration.isActive` referenceable
// from Release code paths, where it is a constant `false`.
//
// When active it wires an `AppState` from fully controllable doubles:
//   • `FixtureNetworkSession` — serves canned JSON per endpoint, never hits the network.
//   • an isolated, ephemeral `UserDefaults` suite — a blank slate every run.
//   • an in-memory Keychain (see `KeychainStore` in AppState.swift) — the real Torn
//     key on the developer's machine is never read or overwritten by a UI test.
//   • `UITestConnectivity` — connectivity the test can flip by hand.
//
// This is the "first brick" the audit ISA called out: it makes the MenuBarExtra UI
// drivable and reproducible so real UI tests can gate merges.

#if DEBUG

/// Which canned world the UI test runs against. Selected via `-uitest-fixture <raw>`.
enum FixtureScenario: String {
    /// A fully-populated, healthy player (bars, travel home, chain inactive, money…).
    case full
    /// The Torn "incorrect key" envelope (code 2) on the fast user call — drives the
    /// permanent-key halt + error UI without touching the real key.
    case invalidKey
    /// Every endpoint returns an empty (but valid) JSON object — used to assert the
    /// onboarding / empty states render without a decode crash.
    case empty
    /// Two synthetic identities selected by the request's fake key. A repeated request
    /// for account A is deliberately delayed and ignores task cancellation so XCUITest
    /// can prove that a stale A response never flashes after switching to B.
    case accountSwitch
    /// Rich, deterministic values for screen-reader contracts: an active flight,
    /// a recent attack, and both faction progress bars.
    case accessibility
    /// Deterministic Watchlist and Forum Watch rows used to verify compact control
    /// hit areas and the non-visual state exposed to assistive technologies.
    case watchAccessibility
}

enum UITestConfiguration {
    static let launchArgument = "--uitesting"
    static let fixtureKey = "-uitest-fixture"   // value: FixtureScenario.rawValue
    static let apiKeyKey = "-uitest-apikey"     // value: seeded key ("" / absent ⇒ onboarding)
    static let onlineKey = "-uitest-online"     // value: "1" (default) / "0"
    static let windowHeightKey = "-uitest-window-height"

    /// True only when the process was launched with `--uitesting`.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Reads a `-key value` pair from the launch arguments (nil if absent).
    private static func argValue(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var scenario: FixtureScenario {
        argValue(fixtureKey).flatMap(FixtureScenario.init(rawValue:)) ?? .full
    }

    /// The API key to seed. Absent or empty ⇒ the app shows onboarding.
    static var seededAPIKey: String { argValue(apiKeyKey) ?? "" }

    static var startsOnline: Bool { argValue(onlineKey) != "0" }
    static var windowHeight: CGFloat {
        let requested = argValue(windowHeightKey).flatMap(Double.init) ?? 640
        return CGFloat(min(max(requested, 640), 1_000))
    }

    /// In-memory Keychain backing store, consulted by `KeychainStore` while a UI test
    /// runs so the app process never reads or writes the real login Keychain.
    static var keychainOverride: [String: String] = [:]

    /// Builds the fully-injected `AppState` for a UI-test run. Must run on the main actor
    /// because `AppState` is `@MainActor`.
    @MainActor
    static func makeAppState() -> AppState {
        // Seed the in-memory Keychain *before* AppState.init reads it.
        keychainOverride.removeAll()
        if !seededAPIKey.isEmpty {
            keychainOverride[KeychainStore.account] = seededAPIKey
        }

        // Isolated, ephemeral defaults so each run starts from a known blank slate.
        let suiteName = "com.mactorn.uitests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let session = FixtureNetworkSession(scenario: scenario)
        let connectivity = UITestConnectivity(connected: startsOnline)

        let appState = AppState(session: session,
                                connectivity: connectivity,
                                defaults: defaults,
                                time: SystemTimeSource())

        if scenario == .accessibility {
            let now = Int(Date().timeIntervalSince1970)
            appState.recentAttacks = [
                AttackResult(
                    code: "fixture-attack",
                    timestampStarted: now - 150,
                    timestampEnded: now - 120,
                    attackerId: 123_456,
                    attackerName: "TestPlayer",
                    defenderId: 654_321,
                    defenderName: "Fixture Opponent",
                    result: "Mugged",
                    respect: 2.5
                ),
                AttackResult(
                    code: "fixture-incoming-attack",
                    timestampStarted: now - 240,
                    timestampEnded: now - 210,
                    attackerId: 777_777,
                    attackerName: "Fixture Aggressor",
                    defenderId: 123_456,
                    defenderName: "TestPlayer",
                    result: "Hospitalized",
                    respect: 1.25
                )
            ]

            // Properties: the fast-user fixture JSON deliberately omits the
            // "properties" key (parseProperties(_:) then returns nil), so this
            // assignment is never clobbered by the real (mocked) poll pipeline —
            // same trick as recentAttacks above. Used by the a11y UI tests to
            // pin PropertyCard's combined VoiceOver label (issue #45).
            appState.propertiesData = [
                PropertyInfo(
                    id: 9101,
                    propertyType: "Property",
                    status: "Rented from Fixture Landlord",
                    cost: 500_000,
                    marketprice: 750_000,
                    happy: 200,
                    rented: true,
                    rentDaysLeft: 2
                )
            ]

            // Activity events: the activity-endpoint fixture JSON returns `[:]`
            // for the `.accessibility` scenario (no "events" key), so this is
            // never overwritten by fetchActivityData's `if let events = ...`
            // guard — same non-clobbering trick as above. Used to pin
            // EventsView's combined VoiceOver label (issue #45).
            //
            // This only holds because `UserSnapshotService.loadActivity` reports an
            // *absent* "events" key as nil rather than as an empty array (issue #84).
            // Before that fix the first poll wiped this seed and StatusView's
            // `if !appState.activityEvents.isEmpty` dropped EventsView from the tree
            // entirely. Never rely on this pattern for a field whose parser collapses
            // "absent" to an empty collection.
            let fixtureEventJSON = Data("""
            {"timestamp": \(now - 90), "event": "You were mugged by <a href=\\"#\\">Fixture Mugger</a> for $500."}
            """.utf8)
            if let fixtureEvent = try? JSONDecoder().decode(TornEvent.self, from: fixtureEventJSON) {
                appState.activityEvents = [fixtureEvent.identified(by: "9002")]
            }
        }

        if scenario == .watchAccessibility {
            appState.watchlistItems = [
                WatchlistItem(
                    id: 206,
                    name: "Accessibility Item",
                    lowestPrice: 4_200,
                    lowestPriceQuantity: 2,
                    secondLowestPrice: 4_300,
                    lastUpdated: Date(),
                    error: nil
                )
            ]
            appState.watchedThreads = [
                WatchedThread(
                    id: 101,
                    title: "Unavailable forum thread",
                    notificationsEnabled: true,
                    lastKnownPostCount: 3,
                    lastChecked: Date(),
                    error: "Fixture forum unavailable."
                ),
                WatchedThread(
                    id: 102,
                    title: "Healthy forum thread",
                    notificationsEnabled: false,
                    lastKnownPostCount: 8,
                    lastChecked: Date(),
                    error: nil
                ),
            ]
        }

        return appState
    }
}

// MARK: - Fixture network session

/// A `NetworkSession` that serves canned JSON per endpoint and never touches the
/// network. Routing is by URL so the fast user call, faction, and the v2 endpoints
/// each get an appropriate, decodable body.
final class FixtureNetworkSession: NetworkSession, @unchecked Sendable {
    static let accountAKey = "fixture-account-a"
    static let accountBKey = "fixture-account-b"

    private let scenario: FixtureScenario
    private let requestCountQueue = DispatchQueue(label: "com.mactorn.uitests.fixture-counts")
    private var accountAFastRequestCount = 0

    init(scenario: FixtureScenario) { self.scenario = scenario }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url
        if scenario == .accountSwitch,
           Self.isFastUserURL(url),
           Self.apiKey(in: url) == Self.accountAKey {
            let requestNumber = requestCountQueue.sync {
                accountAFastRequestCount += 1
                return accountAFastRequestCount
            }
            if requestNumber > 1 {
                // A continuation backed by asyncAfter is intentionally non-cancellable.
                // This models a transport that still delivers A after AppState cancelled it.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        continuation.resume()
                    }
                }
            }
        }

        let body = Self.body(for: url, scenario: scenario)
        let response = HTTPURLResponse(url: url ?? URL(string: "https://api.torn.com")!,
                                       statusCode: 200,
                                       httpVersion: nil,
                                       headerFields: nil)!
        return (body, response)
    }

    /// Chooses the JSON body for a request URL. Only the fast user call (v1 `/user/`
    /// with the point-in-time selections, identifiable by the `bars` selection) carries
    /// the rich fixture; every other endpoint returns an empty—but valid—object, which
    /// the app's `try?`-guarded overlays decode into "no extra data" cleanly.
    static func body(for url: URL?, scenario: FixtureScenario) -> Data {
        let s = url?.absoluteString ?? ""
        let isFastUser = isFastUserURL(url)
        let isKeyInfo = s.contains("/key/info")

        if scenario == .accessibility,
           let fixture = accessibilityResponse(for: url) {
            return (try? JSONSerialization.data(withJSONObject: fixture)) ?? Data("{}".utf8)
        }

        let json: [String: Any]
        switch (isKeyInfo, isFastUser, scenario) {
        case (true, _, .invalidKey):
            json = invalidKeyEnvelope
        case (true, _, _):
            json = keyInfoResponse()
        case (_, true, .full):
            json = fullUserResponse()
        case (_, true, .accessibility):
            json = fullUserResponse(traveling: true, hospitalized: true)
        case (_, true, .watchAccessibility):
            json = fullUserResponse()
        case (_, true, .accountSwitch):
            switch apiKey(in: url) {
            case accountAKey:
                json = fullUserResponse(name: "Fixture Account A", playerID: 100_001)
            case accountBKey:
                json = fullUserResponse(name: "Fixture Account B", playerID: 200_002)
            default:
                json = invalidKeyEnvelope
            }
        case (_, true, .invalidKey):
            json = invalidKeyEnvelope
        default:
            json = [:]
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }

    private static func accessibilityResponse(for url: URL?) -> [String: Any]? {
        let path = url?.path ?? ""
        let now = Int(Date().timeIntervalSince1970)

        if path == "/v2/user" {
            return [
                "organizedCrime": [
                    "id": 101,
                    "name": "Fixture Crime",
                    "difficulty": 4,
                    "status": "Planning",
                    "created_at": now - 600,
                    "ready_at": now + 3_600,
                    "expired_at": now + 86_400,
                    "executed_at": NSNull(),
                    "slots": [
                        [
                            "position": "Muscle",
                            "checkpoint_pass_rate": 80,
                            "user": ["id": 123_456, "progress": 62, "joined_at": now - 600],
                        ]
                    ],
                ],
                "refills": ["energy": true, "nerve": true, "token": true, "special_count": 0],
                "education": ["complete": [], "current": NSNull()],
                "bounties": [],
            ]
        }

        if path.contains("/v2/faction/rankedwars") {
            return [
                "rankedwars": [
                    [
                        "id": 202,
                        "start": now - 7_200,
                        "end": 0,
                        "target": 1_000,
                        "winner": NSNull(),
                        "factions": [
                            ["id": 6_789, "name": "Fixture Faction", "score": 1_250, "chain": 10],
                            ["id": 9_876, "name": "Fixture Rivals", "score": 750, "chain": 5],
                        ],
                    ]
                ]
            ]
        }

        if path == "/faction/" || path == "/faction" {
            return [
                "name": "Fixture Faction",
                "ID": 6_789,
                "respect": 1_000,
                // Active chain, timeout ~150s out: lands in ChainView's "orange /
                // warning" bucket (60..<180s remaining) so the a11y UI test can
                // pin the combined chain-card VoiceOver label (issue #45) without
                // racing the "red / critical" (<60s) edge as the test runs.
                "chain": ["current": 5, "max": 10, "timeout": now + 150, "cooldown": 0],
            ]
        }

        return nil
    }

    private static func isFastUserURL(_ url: URL?) -> Bool {
        let value = url?.absoluteString ?? ""
        return value.contains("api.torn.com/user/") && value.contains("bars")
    }

    private static func apiKey(in url: URL?) -> String? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "key" })?.value
    }

    /// A full-access `/key/info` response granting every selection MacTorn requests, so
    /// Test Connection reports all features available and the endpoint gate lets every
    /// request through. Shape matches the verified `KeyInfoResponse` schema.
    ///
    /// The granted selections are **derived from the endpoint registry**, not listed by
    /// hand. A hand-written list silently goes stale the moment an endpoint gains a
    /// selection: the gate then refuses that endpoint for the whole UI-test run, and the
    /// failure surfaces as an unrelated empty panel rather than as "the fixture is wrong".
    static func keyInfoResponse() -> [String: Any] {
        var granted: [String: [String]] = [:]
        for category in TornKeyInfo.Category.allCases {
            granted[category.rawValue] = []
        }
        for endpoint in TornEndpointRegistry.all {
            let category = KeyValidator.category(for: endpoint).rawValue
            var names = granted[category] ?? []
            for selection in endpoint.selections where !names.contains(selection) {
                names.append(selection)
            }
            granted[category] = names
        }
        // `key.info` takes no selections, so nothing above grants it — but a key that
        // cannot read its own info is not a full-access key.
        granted["key"] = ["info"]

        return [
            "info": [
                "access": ["level": 4, "type": "Full Access", "faction": true, "company": false,
                           "log": ["custom_permissions": false, "available": []]],
                "user": ["id": 123456, "faction_id": 6789, "company_id": NSNull()],
                "selections": granted,
            ],
        ]
    }

    /// The Torn v1 "incorrect key" envelope (code 2). `AppState` classifies this as a
    /// permanent key error and halts polling.
    static let invalidKeyEnvelope: [String: Any] = [
        "error": ["code": 2, "error": "Incorrect key"]
    ]

    /// A healthy, fully-populated fast-user response. Mirrors the shape of the unit
    /// suite's `TornAPIFixtures.validFullResponse()` (kept in sync by construction —
    /// same keys), with `server_time = now` so live countdowns anchor to the run.
    static func fullUserResponse(name: String = "TestPlayer",
                                 playerID: Int = 123456,
                                 traveling: Bool = false,
                                 hospitalized: Bool = false) -> [String: Any] {
        let now = Int(Date().timeIntervalSince1970)
        return [
        "name": name,
        "player_id": playerID,
        "server_time": now,
        "energy": ["current": 100, "maximum": 150, "increment": 5, "interval": 300, "ticktime": 60, "fulltime": 600],
        "nerve": ["current": 50, "maximum": 60, "increment": 1, "interval": 300, "ticktime": 120, "fulltime": 1800],
        "life": ["current": 7500, "maximum": 7500, "increment": 100, "interval": 300, "ticktime": 0, "fulltime": 0],
        "happy": ["current": 5000, "maximum": 10000, "increment": 50, "interval": 300, "ticktime": 100, "fulltime": 30000],
        "cooldowns": ["drug": 0, "medical": 0, "booster": 0],
        "travel": traveling
            ? ["destination": "Japan", "timestamp": now + 300, "departed": now - 300, "time_left": 300]
            : ["destination": "Torn", "timestamp": 0, "departed": 0, "time_left": 0],
        // `until` is regenerated relative to "now" on every poll (not anchored to a
        // fixed wall-clock moment), so the ~2-minute remaining window stays roughly
        // stable across repeated polls instead of counting down to zero mid-test.
        "status": hospitalized
            ? ["description": "In hospital", "details": "Hospitalized by Fixture Attacker",
               "state": "Hospital", "until": now + 125]
            : ["description": "Okay", "details": "", "state": "Okay", "until": 0],
        // NOTE: no "chain" key here on purpose. Torn's v1 `user` endpoint does not
        // return one, and this fixture used to invent it — which is exactly what hid
        // audit finding C-01 (the chain alert read the user snapshot and was therefore
        // dead in production). Chain lives on the faction fixture, like the real API.
        "money_onhand": 1_000_000,
        "points": 10,
        // Deliberately long: compact-window UI tests use this list to prove the
        // module scrolls to its bottom instead of expanding beyond the footer.
        "stocks": Dictionary(
            uniqueKeysWithValues: (1...24).map { stockID in
                (
                    String(stockID),
                    [
                        "stock_id": stockID,
                        "total_shares": stockID * 100_000,
                    ]
                )
            }
        ),
        ]
    }
}

// MARK: - UI-test root view

import AppKit

/// The production app is an accessory (`LSUIElement`), so its `WindowGroup` never
/// auto-opens a window — leaving XCUITest with nothing to drive. Under the harness this
/// delegate promotes the app to a regular activation policy *before* launch finishes, so
/// the window materializes, and activates it so the test runner can see it.
final class UITestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard UITestConfiguration.isActive else { return }
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UITestConfiguration.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Hosts `ContentView` in the UI-test window. Because `SceneBuilder` can't conditionalize
/// a scene at runtime, the window is always declared (in DEBUG); this view is what makes it
/// appear *only* under the harness: with `--uitesting` it shows `ContentView` and brings the
/// window to the front so XCUITest can drive it; otherwise it renders nothing and closes the
/// window, so a normal Debug launch is unaffected.
struct UITestRootView: View {
    let appState: AppState
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false

    var body: some View {
        Group {
            if UITestConfiguration.isActive {
                // No accessibilityIdentifier here: a container-level identifier propagates
                // to every descendant in AppKit-backed SwiftUI and shadows the per-element
                // ids the tests rely on. The window itself is the query root instead.
                ContentView()
                    .environment(appState)
                    .environment(\.reduceTransparency, reduceTransparency)
                    .frame(width: 320, height: UITestConfiguration.windowHeight)
            } else {
                EmptyView()
            }
        }
        .background(
            UITestWindowConfigurator(
                active: UITestConfiguration.isActive,
                height: UITestConfiguration.windowHeight
            )
        )
    }
}

/// Grabs the enclosing `NSWindow` to either front it (UI test) or close it (normal Debug).
private struct UITestWindowConfigurator: NSViewRepresentable {
    let active: Bool
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if active {
                window.title = "MacTorn UI Tests"
                window.setContentSize(NSSize(width: 320, height: height))
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                window.close()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Controllable connectivity

/// Connectivity a UI test can flip by hand (mirrors `ControllableConnectivity` in the
/// unit test target, but lives in the app target so the launched app process can use it).
@MainActor
final class UITestConnectivity: NetworkConnectivity {
    var isConnected: Bool
    var onConnectivityRestored: (() -> Void)?

    init(connected: Bool = true) { isConnected = connected }
}

#else

/// Release shim: the UI-test harness does not exist, so activation is always false.
enum UITestConfiguration {
    static var isActive: Bool { false }
}

#endif
