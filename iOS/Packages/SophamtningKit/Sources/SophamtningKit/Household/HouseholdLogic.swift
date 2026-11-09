import Foundation

/// Rena regler för hushållet. Inget här läser klockan eller rör CloudKit.
public enum HouseholdLogic {
    /// Sant för en delad adress när nästa tömning är i dag eller i morgon.
    public static func showsPlaceOutButton(isShared: Bool, nextPickup: DayDate?, today: DayDate) -> Bool {
        guard isShared, let nextPickup else { return false }
        return (0...1).contains(today.days(until: nextPickup))
    }

    /// Bocken för adressens nästa tömning, om någon. Bocken gäller hämtdatumet, aldrig dagen då någon tryckte.
    public static func currentMark(for key: AddressKey, nextPickup: DayDate?, in marks: [HouseholdMark]) -> HouseholdMark? {
        guard let nextPickup else { return nil }
        return marks.first { $0.placedOut.key == key && $0.placedOut.date == nextPickup }
    }

    /// Bockar vars hämtdatum har passerat. Bocken gäller hela hämtdagen och förbrukas dagen efter.
    public static func expired(_ marks: [HouseholdMark], today: DayDate) -> [HouseholdMark] {
        marks.filter { $0.placedOut.date < today }
    }

    /// Andras bockar som inte har passerat.
    public static func othersActive(_ marks: [HouseholdMark], myId: String?, today: DayDate) -> [HouseholdMark] {
        marks.filter { $0.by != myId && $0.placedOut.date >= today }
    }

    /// Lägger in delade adresser som saknas och tar bort mottagna adresser som inte längre delas.
    /// En adress som redan finns i listan ändras inte och blir inte mottagen, så att mina egna val består.
    /// Nya adresser får notiser av och blir aldrig huvudadress.
    public static func merge(shared: [HouseholdAddress], into list: [SavedAddress], received: Set<AddressKey>) -> (list: [SavedAddress], received: Set<AddressKey>) {
        var result = list
        var receivedKeys = received
        let sharedKeys = Set(shared.map(\.address.key))

        for key in received.subtracting(sharedKeys) {
            result = AddressList.remove(key, from: result)
            receivedKeys.remove(key)
        }
        for item in shared where !result.contains(where: { $0.key == item.address.key }) {
            var incoming = item.address
            incoming.notificationsOn = false
            incoming.isPrimary = false
            result = AddressList.add(incoming, to: result)
            receivedKeys.insert(incoming.key)
        }
        return (result, receivedKeys)
    }
}
