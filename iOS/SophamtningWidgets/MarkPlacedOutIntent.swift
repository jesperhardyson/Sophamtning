import ActivityKit
import AppIntents
import SophamtningKit

/// Knappen **Utställt**: sparar att soporna är utställda, så att samma tömning inte startas igen, och avslutar aktiviteten.
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
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let date = DayDate(iso) {
            await PlacedOutAction.perform(store: LocalStore.shared(), entry: PlacedOut(key: key, date: date), today: StockholmClock.today(now: Date()), end: end)
        } else {
            await end()
        }
        return .result()
    }
}
