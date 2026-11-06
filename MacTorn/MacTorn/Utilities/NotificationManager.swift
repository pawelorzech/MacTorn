import Foundation
import AppKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "NotificationManager")

enum NotificationType: String {
    case drugReady
    case medicalReady
    case boosterReady
    case landed
    case chainExpiring
    case released
    case energy
    case nerve
    case happy
    case life
    case travelApproaching
    case priceAlert
    case ocReady
    case bountyOnMe
    case forumNewPosts
    case factionNewThread
    case ocOpportunity, stockBonus, tradeChanged
    case virusReady

    var url: URL {
        switch self {
        case .drugReady, .medicalReady, .boosterReady:
            return TornLink.items
        case .landed, .travelApproaching:
            return TornLink.itemMarket
        case .chainExpiring:
            return TornLink.factionWars
        case .released:
            return TornLink.home
        case .energy, .happy:
            return TornLink.gym
        case .nerve:
            return TornLink.crimes
        case .life:
            return TornLink.hospital
        case .priceAlert:
            return TornLink.itemMarket
        case .stockBonus:
            return TornLink.stocks
        case .tradeChanged:
            return TornLink.trades
        case .ocReady, .ocOpportunity:
            return TornLink.factionCrimes
        case .bountyOnMe:
            return TornLink.bounties
        case .forumNewPosts, .factionNewThread:
            return TornLink.forums
        case .virusReady:
            return TornLink.crimes
        }
    }
}

/// The real `Notifying`: posts through `UNUserNotificationCenter` and opens the right
/// torn.com page when a banner is clicked.
@MainActor
final class NotificationManager: NSObject, Notifying, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Torn text reaches banners verbatim, so titles and bodies are sanitised and capped;
    /// banners only surface ~120 characters anyway.
    static let notificationTitleMaxLength = 80
    static let notificationBodyMaxLength = 200

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("Notification permission granted")
            }
        } catch {
            logger.error("Notification permission error: \(error.localizedDescription)")
        }
    }

    func authorizationStatusDescription() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "not requested"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    func send(title: String, body: String, type: NotificationType, url: URL?) {
        let content = Self.content(title: title, body: body, type: type)
        if let url {
            content.userInfo["customURL"] = url.absoluteString
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Notification error: \(error.localizedDescription)")
            }
        }
    }

    func schedule(title: String, body: String, type: NotificationType, at date: Date, identifier: String) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: Self.content(title: title, body: body, type: type),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Scheduled notification error: \(error.localizedDescription)")
            } else {
                logger.info("Scheduled notification '\(identifier)' for \(date)")
            }
        }
    }

    func cancelPending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func play(_ sound: NotificationSound) {
        switch sound {
        case .none: return
        case .default: NSSound.beep()
        default:
            if let systemSound = NSSound(named: sound.rawValue) {
                systemSound.play()
            } else {
                NSSound.beep()
            }
        }
    }

    private static func content(title: String, body: String, type: NotificationType) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title.sanitizedForDisplay(limit: notificationTitleMaxLength)
        content.body = body.sanitizedForDisplay(limit: notificationBodyMaxLength)
        content.sound = .default
        content.categoryIdentifier = type.rawValue
        return content
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        if let customURLString = content.userInfo["customURL"] as? String,
           let customURL = URL(string: customURLString) {
            BrowserManager.shared.open(customURL)
        } else if let type = NotificationType(rawValue: content.categoryIdentifier) {
            BrowserManager.shared.open(type.url)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
