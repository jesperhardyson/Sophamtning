import ActivityKit
import AppIntents
import os
import SophamtningKit
import UserNotifications

/// Knappen **Klart**: sparar att soporna är utställda, så att samma tömning inte startas igen, avslutar aktiviteten och tar bort
/// tömningens väntande reservnotis.
/// Ingår i både app- och widgetmålet, och körs utan att appen öppnas.
struct MarkPlacedOutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Klart"
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
        if let date = DayDate(pickupDate) {
            await Self.markPlacedOut(PlacedOut(key: key, date: date))
        } else {
            await Self.endActivities(key: key, iso: pickupDate)
        }
        return .result()
    }

    /// Ställer ut kärlen för en tömning: sparar bocken, avslutar tömningens aktivitet, tar bort dess väntande notiser och
    /// skickar bocken till hushållet. Används av Klart, Utställt i notisen och Siri. Svarar med om bocken sparades.
    @discardableResult
    static func markPlacedOut(_ entry: PlacedOut) async -> Bool {
        let end: @Sendable () async -> Void = { await endActivities(key: entry.key, iso: entry.date.iso) }
        let saved = await PlacedOutAction.perform(store: LocalStore.shared(), entry: entry, today: StockholmClock.today(now: Date()), end: end, cancelReminder: cancelReminder)
        if saved {
            // I appens process når bocken hushållet direkt. I widgetmålet görs det nästa gång appen körs.
            await PlacedOutAction.sendToHousehold?()
        } else {
            // Aktiviteten är avslutad ändå. Nästa planering kan starta samma tömning igen.
            Logger(subsystem: "se.hardyson.sophamtning", category: "LiveActivity").error("Kunde inte spara Utställt")
        }
        return saved
    }

    private static func endActivities(key: AddressKey, iso: String) async {
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

    /// Tar bort den väntande notisen. Misslyckas det blir följden bara en extra påminnelse, och nästa planering rättar det.
    private static let cancelReminder: @Sendable (String) async throws -> Void = { identifier in
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
