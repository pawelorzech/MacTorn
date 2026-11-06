import Foundation
import XCTest
@testable import MacTorn

// MARK: - Test Helpers

/// Creates a Travel instance for testing
func makeTravel(destination: String? = "Torn", timestamp: Int? = nil, departed: Int? = nil, timeLeft: Int? = 0) -> Travel {
    return Travel(destination: destination, timestamp: timestamp, departed: departed, timeLeft: timeLeft)
}

/// Creates a Status instance for testing
func makeStatus(description: String? = "Okay", details: String? = nil, state: String? = "Okay", until: Int? = nil) -> Status {
    return Status(description: description, details: details, state: state, until: until)
}

/// Creates a Chain instance for testing
func makeChain(current: Int? = 0, maximum: Int? = 10, timeout: Int? = 0, cooldown: Int? = 0) -> Chain {
    return Chain(current: current, maximum: maximum, timeout: timeout, cooldown: cooldown)
}

/// Creates a WatchlistItem instance for testing
func makeWatchlistItem(
    id: Int = 1,
    name: String = "Test Item",
    lowestPrice: Int = 1000,
    lowestPriceQuantity: Int = 5,
    secondLowestPrice: Int = 1100,
    lastUpdated: Date? = Date(),
    error: String? = nil
) -> WatchlistItem {
    return WatchlistItem(
        id: id,
        name: name,
        lowestPrice: lowestPrice,
        lowestPriceQuantity: lowestPriceQuantity,
        secondLowestPrice: secondLowestPrice,
        lastUpdated: lastUpdated,
        error: error
    )
}

// MARK: - JSON Decoding Helpers

extension XCTestCase {
    /// Decode JSON string to a Decodable type
    func decode<T: Decodable>(_ type: T.Type, from jsonString: String) throws -> T {
        let data = jsonString.data(using: .utf8)!
        return try JSONDecoder().decode(type, from: data)
    }

    /// Decode JSON dictionary to a Decodable type
    func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Connectivity Test Double

/// Controllable connectivity for tests: flip `isConnected` and fire the restore edge
/// by hand.
@MainActor
final class ControllableConnectivity: NetworkConnectivity {
    var isConnected: Bool
    var onConnectivityRestored: (() -> Void)?

    init(connected: Bool = true) { isConnected = connected }

    /// Simulate a down→up transition (as `NetworkMonitor` does on a real reconnect).
    func restore() {
        isConnected = true
        onConnectivityRestored?()
    }

    func goOffline() { isConnected = false }
}

// MARK: - UserDefaults Test Helpers

extension UserDefaults {
    /// Create a mock UserDefaults for testing
    static func createMockDefaults() -> UserDefaults {
        let suiteName = "com.mactorn.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return defaults
    }
}

/// Test clock: advance time by hand.
final class MutableTimeSource: TimeSource {
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    var now: Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    func set(_ date: Date) { current = date }
}

/// Records what would have been shown to the user.
@MainActor
final class RecordingNotifier: Notifying {
    struct Sent: Equatable {
        let title: String
        let body: String
        let type: NotificationType
        let url: URL?
    }

    private(set) var sent: [Sent] = []
    private(set) var scheduled: [String] = []
    private(set) var cancelled: [[String]] = []
    private(set) var sounds: [NotificationSound] = []

    nonisolated init() {}

    func requestPermission() async {}
    func authorizationStatusDescription() async -> String { "not requested" }
    func send(title: String, body: String, type: NotificationType, url: URL?) {
        sent.append(Sent(title: title, body: body, type: type, url: url))
    }
    func schedule(title: String, body: String, type: NotificationType, at date: Date, identifier: String) {
        scheduled.append(identifier)
    }
    func cancelPending(identifiers: [String]) { cancelled.append(identifiers) }
    func play(_ sound: NotificationSound) { sounds.append(sound) }
}

/// The selections a v2 user URL asks for, as the app's request would carry them.
func userV2Selections(_ url: URL) -> Set<String> {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "selections" }?.value
        .map { Set($0.split(separator: ",").map(String.init)) }
        ?? Set(TornEndpointRegistry.endpoint(id: "user.v2")?.selections ?? [])
}

/// A response body as the top-level JSON object the parsers receive; `[:]` when it is not one.
func jsonObject(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

extension TornRequester {
    /// Sets or clears the key capabilities as if `/key/info` had just answered.
    var testKeyInfo: TornKeyInfo? {
        get { keyInfo }
        set {
            if let newValue { adopt(newValue, at: Date()) } else { forgetKeyInfo() }
        }
    }
}

/// The URL the app would request for a registry endpoint.
func tornURL(_ id: String, key: String, parameter: Int? = nil) -> URL {
    guard let url = TornEndpointRegistry.endpoint(id: id)?.url(key: key, parameter: parameter) else {
        preconditionFailure("no URL for endpoint \(id)")
    }
    return url
}

/// Polls `condition` until it holds or `timeout` passes; returns whether it held.
@MainActor
func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// Lets in-flight work run so an assertion that something did NOT happen has had its chance.
func settle(milliseconds: UInt64 = 150) async {
    try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
}

extension TornRequester {
    /// Whether `endpointID` is currently in a cool-off.
    func isPaused(_ endpointID: String) -> Bool {
        if case .paused = denial(endpointID) { return true }
        return false
    }
}
