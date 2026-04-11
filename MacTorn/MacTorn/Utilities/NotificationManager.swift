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
        }
    }
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

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
    
    func send(title: String, body: String, type: NotificationType) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = type.rawValue

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
        content.title = title
        content.body = body
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
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        if let type = NotificationType(rawValue: categoryIdentifier) {
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
