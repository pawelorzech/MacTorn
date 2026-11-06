import Foundation

/// Everything MacTorn says to the user outside its own window: banners, scheduled
/// landing alerts and alert sounds.
///
/// The default everywhere is `SilentNotifier`; only the app's composition root hands
/// out the real `NotificationManager`, so tests and the UI-test host never reach the
/// system notification centre.
@MainActor
protocol Notifying: AnyObject {
    func requestPermission() async
    func authorizationStatusDescription() async -> String
    func send(title: String, body: String, type: NotificationType, url: URL?)
    func schedule(title: String, body: String, type: NotificationType, at date: Date, identifier: String)
    func cancelPending(identifiers: [String])
    func play(_ sound: NotificationSound)
}

extension Notifying {
    func send(title: String, body: String, type: NotificationType) {
        send(title: title, body: body, type: type, url: nil)
    }
}

@MainActor
final class SilentNotifier: Notifying {
    nonisolated init() {}
    func requestPermission() async {}
    func authorizationStatusDescription() async -> String { "not requested" }
    func send(title: String, body: String, type: NotificationType, url: URL?) {}
    func schedule(title: String, body: String, type: NotificationType, at date: Date, identifier: String) {}
    func cancelPending(identifiers: [String]) {}
    func play(_ sound: NotificationSound) {}
}
