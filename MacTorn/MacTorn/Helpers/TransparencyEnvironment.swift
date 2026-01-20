import SwiftUI

// Environment key for reduce transparency setting
private struct ReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var reduceTransparency: Bool {
        get { self[ReduceTransparencyKey.self] }
        set { self[ReduceTransparencyKey.self] = newValue }
    }
}
