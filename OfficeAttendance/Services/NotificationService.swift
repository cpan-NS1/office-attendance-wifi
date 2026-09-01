import UserNotifications
import AppKit

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendCheckInNotification(status: AttendanceStatus) {
        let content = UNMutableNotificationContent()
        content.title = "\(status.icon) Attendance logged: \(status.menuLabel)"
        content.body = formattedToday()
        content.categoryIdentifier = "CHECKIN"
        content.sound = .default
        schedule(content: content, id: "checkin-\(formattedToday())")
    }

    func sendChangeConfirmation(status: AttendanceStatus) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Changed to: \(status.menuLabel)"
        content.body = formattedToday()
        content.sound = .default
        schedule(content: content, id: "change-\(UUID().uuidString)")
    }

    func sendSetupReminder() {
        let content = UNMutableNotificationContent()
        content.title = "⚙️ Office Attendance — Setup required"
        content.body = "Tap to open Settings"
        content.categoryIdentifier = "SETUP"
        schedule(content: content, id: "setup-reminder")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "CHANGE", UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == "CHECKIN" {
                NotificationCenter.default.post(name: .openMenuBarDropdown, object: nil)
            } else if response.notification.request.content.categoryIdentifier == "SETUP" {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        default: break
        }
        completionHandler()
    }

    // MARK: - Private

    private func registerCategories() {
        let changeAction = UNNotificationAction(identifier: "CHANGE",
                                               title: "Change", options: [.foreground])
        let okAction = UNNotificationAction(identifier: "OK", title: "OK", options: [])
        let checkinCategory = UNNotificationCategory(identifier: "CHECKIN",
                                                     actions: [changeAction, okAction],
                                                     intentIdentifiers: [])
        let openAction = UNNotificationAction(identifier: "OPEN_SETTINGS",
                                              title: "Open Settings", options: [.foreground])
        let setupCategory = UNNotificationCategory(identifier: "SETUP",
                                                   actions: [openAction],
                                                   intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([checkinCategory, setupCategory])
    }

    private func schedule(content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func formattedToday() -> String {
        let f = DateFormatter()
        f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: Date())
    }
}

extension Notification.Name {
    static let openMenuBarDropdown = Notification.Name("openMenuBarDropdown")
    static let openSettings        = Notification.Name("openSettings")
}
