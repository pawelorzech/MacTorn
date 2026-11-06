import SwiftUI

/// What every MacTorn window hands its content: the shared state, navigation, the
/// effective reduce-transparency setting and the appearance the user picked.
private struct AppRootModifier: ViewModifier {
    let appState: AppState
    let navigation: AppNavigationState
    @AppStorage(StoredPreference.appearanceMode) private var appearanceMode: AppearanceMode = .system
    @AppStorage(StoredPreference.reduceTransparency) private var reduceTransparencyOverride = false
    @State private var systemAccessibility = SystemAccessibilitySettings()

    func body(content: Content) -> some View {
        content
            .environment(appState)
            .environment(navigation)
            .environment(\.reduceTransparency,
                          TransparencyPolicy.effective(system: systemAccessibility.reduceTransparency,
                                                       userOverride: reduceTransparencyOverride))
            .onAppear { apply(appearanceMode) }
            .onChange(of: appearanceMode) { _, mode in apply(mode) }
    }

    private func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension View {
    func macTornRoot(_ appState: AppState, navigation: AppNavigationState) -> some View {
        modifier(AppRootModifier(appState: appState, navigation: navigation))
    }
}
