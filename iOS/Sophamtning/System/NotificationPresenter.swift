import SophamtningKit
import UserNotifications

/// Visar notisen med banner och ljud även när appen är öppen. Utan den döljer iOS notiser i förgrunden. Tar också emot
/// knappen **Utställt** i påminnelsenotisen.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    /// Kategorin med knappen Utställt. Registreras när appen startar, innan någon notis visas. Knappen öppnar inte appen.
    static func registerCategories() {
        let action = UNNotificationAction(identifier: PlacedOutNotification.actionIdentifier, title: PlacedOutNotification.actionTitle, options: [])
        let category = UNNotificationCategory(identifier: PlacedOutNotification.categoryIdentifier, actions: [action], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Utställt i notisen gör samma sak som Klart i Live Activityn: sparar bocken, tar bort tömningens påminnelser och
    /// aktivitet och skickar bocken till hushållet. En notis utan tömning gör ingenting.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == PlacedOutNotification.actionIdentifier,
              let entry = PlacedOutNotification.entry(from: response.notification.request.content.userInfo)
        else { return }
        _ = try? await MarkPlacedOutIntent(key: entry.key, pickupDate: entry.date).perform()
    }
}
