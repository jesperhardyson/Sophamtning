#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Attribut för Live Activityn. Innehållet ligger i `ContentState`, så att det kan bytas utan att aktiviteten startas om.
public struct PickupActivityAttributes: ActivityAttributes {
    public typealias ContentState = PickupActivityContent

    public let key: AddressKey
    public let pickupDate: DayDate
    /// Den planerade starten, så att appen kan se om en väntande aktivitet gäller en ändrad påminnelsetid.
    public let start: Date

    public init(key: AddressKey, pickupDate: DayDate, start: Date) {
        self.key = key
        self.pickupDate = pickupDate
        self.start = start
    }
}
#endif
