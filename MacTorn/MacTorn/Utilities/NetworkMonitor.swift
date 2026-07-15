import Foundation
import Network

/// Protocol for network connectivity checks, enabling dependency injection for testing
@MainActor
protocol NetworkConnectivity: AnyObject {
    var isConnected: Bool { get }
    /// Invoked when connectivity transitions from down to up, so the app can trigger a
    /// safe refresh (Etap D: "offline → online powoduje bezpieczny refresh"). Set by the
    /// owner; may be nil.
    var onConnectivityRestored: (() -> Void)? { get set }
}

@MainActor
final class NetworkMonitor: NetworkConnectivity {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    var onConnectivityRestored: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mactorn.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let nowConnected = path.status == .satisfied
                let wasConnected = self.isConnected
                self.isConnected = nowConnected
                // Fire only on a genuine down→up edge, so a refresh happens once per
                // reconnect (not on every path update while already online).
                if nowConnected && !wasConnected {
                    self.onConnectivityRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
