#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Attribut för Live Activityn. Innehållet ligger i `ContentState`, så att det kan bytas utan att aktiviteten startas om.
public struct PickupActivityAttributes: ActivityAttributes {
    public typealias ContentState = PickupActivityContent

    public let key: AddressKey
    public let pickupDate: DayDate

    public init(key: AddressKey, pickupDate: DayDate) {
        self.key = key
        self.pickupDate = pickupDate
    }
}
#endif
