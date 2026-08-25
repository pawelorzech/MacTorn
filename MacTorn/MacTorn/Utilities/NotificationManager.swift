import Foundation
import UserNotifications
import AppKit
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
    case virusReady

    var url: URL {
        switch self {
        case .drugReady, .medicalReady, .boosterReady:
            return URL(string: "https://www.torn.com/item.php")!
        case .landed, .travelApproaching:
            return URL(string: "https://www.torn.com/page.php?sid=ItemMarket")!
        case .chainExpiring:
            return URL(string: "https://www.torn.com/factions.php?step=your#/tab=wars")!
        case .released:
            return URL(string: "https://www.torn.com/")!
        case .energy, .happy:
            return URL(string: "https://www.torn.com/gym.php")!
        case .nerve:
            return URL(string: "https://www.torn.com/crimes.php")!
        case .life:
            return URL(string: "https://www.torn.com/hospitalview.php")!
        case .priceAlert:
            return URL(string: "https://www.torn.com/page.php?sid=ItemMarket")!
        case .ocReady:
            return URL(string: "https://www.torn.com/factions.php?step=your#/tab=crimes")!
        case .bountyOnMe:
            return URL(string: "https://www.torn.com/bounties.php")!
        case .forumNewPosts, .factionNewThread:
            return URL(string: "https://www.torn.com/forums.php")!
        case .virusReady:
            return URL(string: "https://www.torn.com/crimes.php")!
        }
    }
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Sanitize text that originated from the Torn API before it lands in
    /// `UNNotificationContent.title`/`.body`. Strips control characters and caps
    /// length so a compromised or MITM'd response can't spoof multi-line / oversized
    /// notifications. `notificationBodyMaxLength` is small on purpose — banners only
    /// surface ~120 chars anyway.
    static let notificationTitleMaxLength = 80
    static let notificationBodyMaxLength = 200

    static func sanitize(_ text: String, maxLength: Int) -> String {
        let stripped = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(Character.init)
        return String(String(stripped).prefix(maxLength))
    }

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

    /// Current system authorization state, for the Diagnostics screen (Etap F). Maps
    /// the `UNAuthorizationStatus` enum to a short human-readable string.
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

    func send(title: String, body: String, type: NotificationType, customURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = Self.sanitize(title, maxLength: Self.notificationTitleMaxLength)
        content.body = Self.sanitize(body, maxLength: Self.notificationBodyMaxLength)
        content.sound = .default
        content.categoryIdentifier = type.rawValue
        if let customURL = customURL {
            content.userInfo["customURL"] = customURL.absoluteString
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Notification error: \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a notification for a specific date
    func scheduleNotification(title: String, body: String, type: NotificationType, at date: Date, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = Self.sanitize(title, maxLength: Self.notificationTitleMaxLength)
        content.body = Self.sanitize(body, maxLength: Self.notificationBodyMaxLength)
        content.sound = .default
        content.categoryIdentifier = type.rawValue

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Scheduled notification error: \(error.localizedDescription)")
            } else {
                logger.info("Scheduled notification '\(identifier)' for \(date)")
            }
        }
    }

    /// Cancel all travel-related notifications
    func cancelTravelNotifications() {
        let identifiers = TravelNotificationSetting.defaults.map { "\($0.id)_alert" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancel a specific notification by identifier
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
