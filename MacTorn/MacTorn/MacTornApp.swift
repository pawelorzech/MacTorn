import SwiftUI

@main
struct MacTornApp: App {
    @State private var appState: AppState
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false

    #if DEBUG
    // Promotes the accessory app to a regular window when launched under `--uitesting`,
    // so the UI-test window actually appears. Inert on any normal launch.
    @NSApplicationDelegateAdaptor(UITestAppDelegate.self) private var uiTestDelegate
    #endif

    init() {
        #if DEBUG
        // Under the UI-test harness, build a hermetic AppState from fixtures/doubles and
        // skip Sentry (no crash reporter, no network) so runs are deterministic.
        if UITestConfiguration.isActive {
            _appState = State(initialValue: UITestConfiguration.makeAppState())
            return
        }
        #endif
        SentryManager.startIfEnabled()
        _appState = State(initialValue: AppState())
    }

    var body: some Scene {
        #if DEBUG
        uiTestWindow
        #endif
        MenuBarExtra {
            ContentView()
                .environment(appState)
                .environment(\.reduceTransparency, reduceTransparency)
                .onAppear {
                    updateAppearance()
                }
                .onChange(of: appearanceModeRaw) { _, _ in
                    updateAppearance()
                }
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }

    #if DEBUG
    // A MenuBarExtra has no ordinary window, so XCUITest cannot see or drive its content.
    // Under the UI-test harness, surface the exact same ContentView in a real window the
    // test runner can query. Otherwise fall back to an inert `Settings` scene, which never
    // auto-opens a window — so a normal Debug launch is unaffected. Production ships
    // MenuBarExtra only (this whole scene is `#if DEBUG`).
    //
    // Note: `SceneBuilder` does not support runtime `if`/`else` (only `#available`), so the
    // window cannot be conditionalized at the scene level — it is always present in DEBUG.
    // `UITestRootView` gates its content on `UITestConfiguration.isActive` and closes this
    // window on a normal (non-UI-test) Debug launch, so it is invisible outside UI tests.
    private var uiTestWindow: some Scene {
        WindowGroup(id: "uitest-window") {
            UITestRootView(appState: appState)
        }
    }
    #endif

    private func updateAppearance() {
        let mode = AppearanceMode(rawValue: appearanceModeRaw) ?? .system
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Menu Bar Label
struct MenuBarLabel: View {
    // @Bindable is the @Observable equivalent of @ObservedObject for views that
    // are passed an instance (vs. reading it from the environment). Plain `var`
    // would also work since SwiftUI tracks property reads in body for @Observable
    // types, but @Bindable keeps the call-site identical to before.
    @Bindable var appState: AppState

    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            switch appState.menuBarDisplay {
            case .traveling(let flag, let seconds):
                Text("✈️\(flag)\(formatShortTime(seconds))")
            case .hospitalAbroad(let flag, let seconds):
                Text("🏥\(flag)\(formatShortTime(seconds))")
            case .hospitalAtHome(let seconds):
                Text("🏥\(formatShortTime(seconds))")
            case .jail(let seconds):
                Text("🚓\(formatShortTime(seconds))")
            case .cooldown(let emoji, let seconds):
                Text("\(emoji)\(formatShortTime(seconds))")
            case .fallbackIcon:
                Image(systemName: menuBarIcon)
            }
        }
        .transaction { $0.animation = nil }
        #if DEBUG
        // The menu-bar label renders at launch even for an accessory app, so it's the one
        // reliable place to explicitly open the UI-test window (a MenuBarExtra's own content
        // only appears on click, which XCUITest can't trigger). Inert on a normal launch.
        .onAppear {
            if UITestConfiguration.isActive {
                openWindow(id: "uitest-window")
            }
        }
        #endif
    }

    private var menuBarIcon: String {
        // Error state
        if appState.errorMsg != nil {
            return "exclamationmark.triangle.fill"
        }

        // Abroad state
        if let travel = appState.data?.travel, travel.isAbroad {
            return "globe"
        }

        // Energy full state
        if let bars = appState.data?.bars {
            if bars.energy.current >= bars.energy.maximum {
                return "bolt.fill"
            }
        }

        // Default
        return "bolt"
    }

    private func flagForDestination(_ destination: String) -> String {
        TornDestination.flag(for: destination)
    }

    private func formatShortTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "0:00" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
