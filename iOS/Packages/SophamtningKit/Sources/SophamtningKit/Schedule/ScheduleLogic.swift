import Foundation

/// Nästa hämtning för en fraktion, räknad lokalt från händelserna.
public struct FractionPickup: Hashable, Sendable {
    /// Fraktions-id.
    public let fraction: String
    public let date: DayDate
    public let estimated: Bool
    public let warning: String?
    /// Dagar från `today` till `date`. Räknas lokalt, aldrig från API:ts `daysUntil`.
    public let daysUntil: Int

    public init(fraction: String, date: DayDate, estimated: Bool, warning: String?, daysUntil: Int) {
        self.fraction = fraction
        self.date = date
        self.estimated = estimated
        self.warning = warning
        self.daysUntil = daysUntil
    }
}

/// Ren schemalogik. Allt räknas från händelserna och given dag, aldrig från sparade `next`-fält.
public enum ScheduleLogic {
    /// Neutral färg för fraktioner som API:t inte känner till.
    static let neutralColor = "#526158"
    static let fallbackIcon = "recycle"

    /// Händelser från och med `today`, sorterade på datum.
    public static func upcoming(_ events: [PickupEvent], today: DayDate) -> [PickupEvent] {
        events.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    public static func nextPickup(_ events: [PickupEvent], today: DayDate) -> PickupEvent? {
        upcoming(events, today: today).first
    }

    /// Första kommande datum per fraktion, sorterat på datum och sedan på fraktions-id.
    public static func nextByFraction(_ events: [PickupEvent], today: DayDate) -> [FractionPickup] {
        var first: [String: FractionPickup] = [:]
        for event in upcoming(events, today: today) {
            for id in event.fractions where first[id] == nil {
                first[id] = FractionPickup(
                    fraction: id,
                    date: event.date,
                    estimated: event.estimated,
                    warning: event.warning,
                    daysUntil: today.days(until: event.date)
                )
            }
        }
        return first.values.sorted { ($0.date, $0.fraction) < ($1.date, $1.fraction) }
    }

    /// Visningsinfo för ett fraktions-id. Okända id:n får id:t som namn, neutral färg och ikonen `recycle`.
    public static func displayInfo(for id: String, in fractions: [String: FractionInfo]) -> FractionInfo {
        fractions[id] ?? FractionInfo(name: id, short: id, color: neutralColor, icon: fallbackIcon)
    }
}
