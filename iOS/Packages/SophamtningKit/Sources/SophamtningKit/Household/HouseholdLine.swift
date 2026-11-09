import Foundation

/// Hushållets rad på ett kort och i adressvyn. `nil` utan hushåll.
public struct HouseholdLine: Equatable, Sendable {
    /// Adressen delas med hushållet.
    public var isShared: Bool
    /// Knappen Ställ ut kärlen visas: delad adress, tömning i dag eller i morgon, och ingen bock än.
    public var showsButton: Bool
    /// "Utställt av Kim, kl. 19:42", när nästa tömning har en bock.
    public var placedOutText: String?
    /// Raden under "Utställt": "av Kim · kl. 19:42", eller "skickas när nätet finns" för en bock som väntar.
    public var placedOutSubtitle: String?
    /// Bocken har inte nått iCloud än, och en klocka visas bredvid den.
    public var isPending: Bool
    /// Hushållets läge när något inte fungerar, annars `nil`.
    public var statusText: String?

    public init(isShared: Bool, showsButton: Bool, placedOutText: String?, placedOutSubtitle: String? = nil, isPending: Bool, statusText: String?) {
        self.isShared = isShared
        self.showsButton = showsButton
        self.placedOutText = placedOutText
        self.placedOutSubtitle = placedOutSubtitle
        self.isPending = isPending
        self.statusText = statusText
    }

    /// Raden för en adress och dess nästa tömning. `nil` när det inte finns något hushåll.
    ///
    /// - Parameter ownPlacedOut: mina egna utställda i `placed-out.json`. En sådan för en delad adress, som hushållet saknar
    ///   bock för, visas som en bock som väntar på att skickas, till exempel efter knappen i Live Activity.
    public static func make(household: HouseholdState, key: AddressKey, nextPickup: DayDate?, today: DayDate, ownPlacedOut: Set<PlacedOut> = []) -> HouseholdLine? {
        // Utan roll men med adresser kvar, till exempel efter ett fel, visas raden ändå.
        guard household.role != .none || !household.addresses.isEmpty else { return nil }
        let isShared = household.addresses.contains { $0.address.key == key }
        let mark = HouseholdLogic.currentMark(for: key, nextPickup: nextPickup, in: household.marks)
        let ownPending = mark == nil && isShared && nextPickup.map { ownPlacedOut.contains(PlacedOut(key: key, date: $0)) } == true
        if ownPending {
            return HouseholdLine(
                isShared: true,
                showsButton: false,
                placedOutText: HouseholdTexts.placedOutByMe,
                placedOutSubtitle: HouseholdTexts.pendingSubtitle,
                isPending: true,
                statusText: HouseholdTexts.status(household.status)
            )
        }
        return HouseholdLine(
            isShared: isShared,
            showsButton: mark == nil && HouseholdLogic.showsPlaceOutButton(isShared: isShared, nextPickup: nextPickup, today: today),
            placedOutText: mark.map { HouseholdTexts.placedOut($0, participants: household.participants, myId: household.myId) },
            placedOutSubtitle: mark.map {
                $0.isPending ? HouseholdTexts.pendingSubtitle : HouseholdTexts.placedOutSubtitle($0, participants: household.participants, myId: household.myId)
            },
            isPending: mark?.isPending ?? false,
            statusText: HouseholdTexts.status(household.status)
        )
    }
}
