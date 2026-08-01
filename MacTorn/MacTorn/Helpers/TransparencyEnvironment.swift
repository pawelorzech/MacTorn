import SwiftUI
import AppKit

// Environment key for reduce transparency setting
private struct ReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// How the app's own toggle combines with the system accessibility setting.
///
/// README has always promised: "Reduce Transparency: when enabled in System Settings →
/// Accessibility → Display, the app uses solid backgrounds". It never did — the value
/// came from an `@AppStorage` toggle defaulting to `false`, and nothing in the tree ever
/// read `NSWorkspace.accessibilityDisplayShouldReduceTransparency`. A user who had set
/// the system preference still got full translucency until they found the app's own
/// switch, buried under the "Startup" section. (Audit finding A-01.)
///
/// The system setting now wins as a floor; the in-app toggle can only add to it.
enum TransparencyPolicy {
    static func effective(system: Bool, userOverride: Bool) -> Bool {
        system || userOverride
    }
}

/// Live view of the macOS accessibility display options this app reacts to.
@MainActor
@Observable
final class SystemAccessibilitySettings {
    private(set) var reduceTransparency: Bool

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // The setting can be flipped while the app runs; without this the window keeps
        // whatever it sampled at launch.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reduceTransparency =
                    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

struct OpenMacTornSettingsAction: @unchecked Sendable {
    private let action: () -> Void

    init(_ action: @escaping () -> Void = {}) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

private struct OpenMacTornSettingsKey: EnvironmentKey {
    static let defaultValue = OpenMacTornSettingsAction()
}

extension EnvironmentValues {
    var reduceTransparency: Bool {
        get { self[ReduceTransparencyKey.self] }
        set { self[ReduceTransparencyKey.self] = newValue }
    }

    var openMacTornSettings: OpenMacTornSettingsAction {
        get { self[OpenMacTornSettingsKey.self] }
        set { self[OpenMacTornSettingsKey.self] = newValue }
    }
}
