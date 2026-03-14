import Foundation
import Network

/// Protocol for network connectivity checks, enabling dependency injection for testing
@MainActor
protocol NetworkConnectivity: AnyObject {
    var isConnected: Bool { get }
}

@MainActor
final class NetworkMonitor: NetworkConnectivity {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mactorn.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
