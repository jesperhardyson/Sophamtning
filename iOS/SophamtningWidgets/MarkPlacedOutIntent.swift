import ActivityKit
import AppIntents
import os
import SophamtningKit
import UserNotifications

/// Knappen **Utställt**: sparar att soporna är utställda, så att samma tömning inte startas igen, avslutar aktiviteten och tar bort
/// tömningens väntande reservnotis.
/// Ingår i både app- och widgetmålet, och körs utan att appen öppnas.
struct MarkPlacedOutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Utställt"
    static let isDiscoverable = false

    @Parameter(title: "Källa")
    var source: String

    @Parameter(title: "Adress")
    var addressID: String

    @Parameter(title: "Datum")
    var pickupDate: String

    init() {
        source = ""
        addressID = ""
        pickupDate = ""
    }

    init(key: AddressKey, pickupDate: DayDate) {
        source = key.source
        addressID = key.id
        self.pickupDate = pickupDate.iso
    }

    func perform() async throws -> some IntentResult {
        let key = AddressKey(source: source, id: addressID)
        let iso = pickupDate
        let end: @Sendable () async -> Void = {
            for activity in Activity<PickupActivityAttributes>.activities
            where activity.attributes.key == key && activity.attributes.pickupDate.iso == iso {
                switch activity.activityState {
                case .pending:
                    // En väntande aktivitet har aldrig visats, så den tas bort direkt utan bock.
                    await activity.end(nil, dismissalPolicy: .immediate)
                case .ended, .dismissed:
                    break
                default:
                    // Bocken står kvar i tre sekunder innan aktiviteten försvinner.
                    let done = ActivityContent(state: activity.content.state.markedPlacedOut(), staleDate: nil)
                    await activity.end(done, dismissalPolicy: .after(Date().addingTimeInterval(PlacedOutAction.checkmarkSeconds)))
                }
            }
        }
        if let date = DayDate(iso) {
            let saved = await PlacedOutAction.perform(store: LocalStore.shared(), entry: PlacedOut(key: key, date: date), today: StockholmClock.today(now: Date()), end: end, cancelReminder: Self.cancelReminder)
            if !saved {
                // Aktiviteten är avslutad ändå. Nästa planering kan starta samma tömning igen.
                Logger(subsystem: "se.hardyson.sophamtning", category: "LiveActivity").error("Kunde inte spara Utställt")
            }
        } else {
            await end()
        }
        return .result()
    }

    /// Tar bort den väntande notisen. Misslyckas det blir följden bara en extra påminnelse, och nästa planering rättar det.
    private static let cancelReminder: @Sendable (String) async throws -> Void = { identifier in
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
