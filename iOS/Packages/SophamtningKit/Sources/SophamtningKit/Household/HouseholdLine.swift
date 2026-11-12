import Foundation

/// Raden för Utställt på ett kort och i adressvyn: hushållets rad för en delad adress, och för andra adresser bara
/// "Kärlen är utställda" när nästa tömning är markerad. `nil` när det inte finns något att visa.
public struct HouseholdLine: Equatable, Sendable {
    /// Adressen delas med hushållet.
    public var isShared: Bool
    /// "Delas med Sofie" eller "Delas med Sofie och Kim" för en delad adress, annars `nil`.
    public var sharedText: String?
    /// Knappen Ställ ut kärlen visas: delad adress eller påminnelser på, tömning i dag eller i morgon, och ingen bock än.
    public var showsButton: Bool
    /// "Utställt av Kim, kl. 19:42", när nästa tömning har en bock. Det är också det VoiceOver läser.
    public var placedOutText: String?
    /// Rubriken i raden: "Utställt" i hushållet, "Kärlen är utställda" för en adress som inte delas.
    public var placedOutTitle: String
    /// Raden under "Utställt": "av Kim · kl. 19:42", eller "skickas när nätet finns" för en bock som väntar.
    public var placedOutSubtitle: String?
    /// Bocken har inte nått iCloud än, och en klocka visas bredvid den.
    public var isPending: Bool
    /// Hushållets läge när något inte fungerar, annars `nil`.
    public var statusText: String?

    public init(isShared: Bool, sharedText: String? = nil, showsButton: Bool, placedOutText: String?, placedOutTitle: String = HouseholdTexts.placedOutTitle, placedOutSubtitle: String? = nil, isPending: Bool, statusText: String?) {
        self.placedOutTitle = placedOutTitle
        self.isShared = isShared
        self.sharedText = isShared ? sharedText ?? HouseholdTexts.shared : nil
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
    /// - Parameter remindersOn: adressen har notiser eller Live Activity på. Då får också en adress som inte delas knappen,
    ///   så att kärlen går att ställa ut igen efter Ångra.
    public static func make(household: HouseholdState, key: AddressKey, nextPickup: DayDate?, today: DayDate, ownPlacedOut: Set<PlacedOut> = [], remindersOn: Bool = false) -> HouseholdLine? {
        let ownMarked = nextPickup.map { ownPlacedOut.contains(PlacedOut(key: key, date: $0)) } == true
        // Utan roll men med adresser kvar, till exempel efter ett fel, visas raden ändå.
        let hasHousehold = household.role != .none || !household.addresses.isEmpty
        let isShared = hasHousehold && household.addresses.contains { $0.address.key == key }
        guard isShared else {
            // En adress som inte delas har bara min egen markering, till exempel från Klart i Live Activity.
            guard ownMarked else {
                let showsButton = HouseholdLogic.showsPlaceOutButton(isShared: false, remindersOn: remindersOn, nextPickup: nextPickup, today: today)
                guard hasHousehold || showsButton else { return nil }
                return HouseholdLine(isShared: false, showsButton: showsButton, placedOutText: nil, isPending: false, statusText: hasHousehold ? HouseholdTexts.status(household.status) : nil)
            }
            return HouseholdLine(isShared: false, showsButton: false, placedOutText: HouseholdTexts.ownPlacedOut, placedOutTitle: HouseholdTexts.ownPlacedOut, isPending: false, statusText: nil)
        }
        let mark = HouseholdLogic.currentMark(for: key, nextPickup: nextPickup, in: household.marks)
        let others = household.participants.filter { $0.id != household.myId }.map(\.name)
        let sharedText = isShared ? HouseholdTexts.sharedWith(others) : nil
        let ownPending = mark == nil && ownMarked
        if ownPending {
            return HouseholdLine(
                isShared: true,
                sharedText: sharedText,
                showsButton: false,
                placedOutText: HouseholdTexts.placedOutByMe,
                placedOutSubtitle: HouseholdTexts.pendingSubtitle,
                isPending: true,
                statusText: HouseholdTexts.status(household.status)
            )
        }
        return HouseholdLine(
            isShared: isShared,
            sharedText: sharedText,
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
