import SwiftUI

// Environment key for reduce transparency setting
private struct ReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool = false
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
