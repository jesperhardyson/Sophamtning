import Foundation
import SophamtningKit
import UserNotifications

/// Schemalägger notiser hos iOS. Rör bara väntande notiser vars identifierare planeraren har skapat
/// (`NotificationDiff.isOwn`), aldrig andra.
struct NotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        // Ett okänt tillstånd visas inte som nekat. Då rörs inga val, och tillståndet frågas om vid nästa påslag.
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pending() async -> [PendingNotification] {
        await center.pendingNotificationRequests()
            .filter { NotificationDiff.isOwn(identifier: $0.identifier) }
            .map { request in
                PendingNotification(
                    identifier: request.identifier,
                    fireDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                    body: request.content.body
                )
            }
    }

    func schedule(_ notifications: [PlannedNotification]) async -> [String] {
        var failed: [String] = []
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: Self.trigger(for: notification.fireDate))
            // Ett misslyckat tillägg rapporteras, så att appen visar det och försöker igen vid nästa körning.
            do { try await center.add(request) } catch { failed.append(notification.identifier) }
        }
        return failed
    }

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers.filter { NotificationDiff.isOwn(identifier: $0) })
    }

    /// Visar notisen direkt, utan utlösare. Identifieraren känns inte igen av `NotificationDiff.isOwn`, så planeringen rör den aldrig.
    /// Ett fel tas inte om: notisen gäller bara just nu.
    func deliverNow(identifier: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Utställt"
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Klockslaget anges i `Europe/Stockholm`, så att tiden gäller oavsett telefonens tidszon.
    static func trigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = StockholmClock.timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.calendar = calendar
        components.timeZone = StockholmClock.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
