import Foundation
import UserNotifications
import AppKit

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
                print("Notification permission granted")
            }
        } catch {
            print("Notification permission error: \(error)")
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
                print("Notification error: \(error)")
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
                print("Scheduled notification error: \(error)")
            } else {
                print("Scheduled notification '\(identifier)' for \(date)")
            }
        }
    }

    /// Cancel all travel-related notifications
    func cancelTravelNotifications() {
        let identifiers = [
            "travel_2min_alert",
            "travel_1min_alert",
            "travel_30sec_alert",
            "travel_10sec_alert"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("Cancelled travel notifications")
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
            NSWorkspace.shared.open(type.url)
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
