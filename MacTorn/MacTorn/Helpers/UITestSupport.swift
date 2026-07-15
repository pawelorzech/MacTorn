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
}

enum UITestConfiguration {
    static let launchArgument = "--uitesting"
    static let fixtureKey = "-uitest-fixture"   // value: FixtureScenario.rawValue
    static let apiKeyKey = "-uitest-apikey"     // value: seeded key ("" / absent ⇒ onboarding)
    static let onlineKey = "-uitest-online"     // value: "1" (default) / "0"

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

        return AppState(session: session,
                        connectivity: connectivity,
                        defaults: defaults,
                        time: SystemTimeSource())
    }
}

// MARK: - Fixture network session

/// A `NetworkSession` that serves canned JSON per endpoint and never touches the
/// network. Routing is by URL so the fast user call, faction, and the v2 endpoints
/// each get an appropriate, decodable body.
final class FixtureNetworkSession: NetworkSession, @unchecked Sendable {
    private let scenario: FixtureScenario

    init(scenario: FixtureScenario) { self.scenario = scenario }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url
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
        let isFastUser = s.contains("api.torn.com/user/") && s.contains("bars")

        let json: [String: Any]
        switch (isFastUser, scenario) {
        case (true, .full):
            json = fullUserResponse()
        case (true, .invalidKey):
            json = invalidKeyEnvelope
        default:
            json = [:]
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }

    /// The Torn v1 "incorrect key" envelope (code 2). `AppState` classifies this as a
    /// permanent key error and halts polling.
    static let invalidKeyEnvelope: [String: Any] = [
        "error": ["code": 2, "error": "Incorrect key"]
    ]

    /// A healthy, fully-populated fast-user response. Mirrors the shape of the unit
    /// suite's `TornAPIFixtures.validFullResponse()` (kept in sync by construction —
    /// same keys), with `server_time = now` so live countdowns anchor to the run.
    static func fullUserResponse() -> [String: Any] { [
        "name": "TestPlayer",
        "player_id": 123456,
        "server_time": Int(Date().timeIntervalSince1970),
        "energy": ["current": 100, "maximum": 150, "increment": 5, "interval": 300, "ticktime": 60, "fulltime": 600],
        "nerve": ["current": 50, "maximum": 60, "increment": 1, "interval": 300, "ticktime": 120, "fulltime": 1800],
        "life": ["current": 7500, "maximum": 7500, "increment": 100, "interval": 300, "ticktime": 0, "fulltime": 0],
        "happy": ["current": 5000, "maximum": 10000, "increment": 50, "interval": 300, "ticktime": 100, "fulltime": 30000],
        "cooldowns": ["drug": 0, "medical": 0, "booster": 0],
        "travel": ["destination": "Torn", "timestamp": 0, "departed": 0, "time_left": 0],
        "status": ["description": "Okay", "details": "", "state": "Okay", "until": 0],
        "chain": ["current": 0, "maximum": 10, "timeout": 0, "cooldown": 0],
        "money_onhand": 1_000_000,
        "points": 10,
    ] }
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
                    .frame(width: 320, height: 640)
            } else {
                EmptyView()
            }
        }
        .background(UITestWindowConfigurator(active: UITestConfiguration.isActive))
    }
}

/// Grabs the enclosing `NSWindow` to either front it (UI test) or close it (normal Debug).
private struct UITestWindowConfigurator: NSViewRepresentable {
    let active: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if active {
                window.setContentSize(NSSize(width: 320, height: 640))
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
