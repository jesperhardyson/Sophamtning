import Foundation

/// Rena regler för hushållet. Inget här läser klockan eller rör CloudKit.
public enum HouseholdLogic {
    /// Hur ofta hushållets ändringar hämtas medan appen är öppen, som reserv när den tysta pushen dröjer.
    public static let liveFetchInterval: Duration = .seconds(15)

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

    /// Deltagare som har gått med sedan förra synkade läget. Utan kända deltagare (`nil`), när jag just gått med eller
    /// hämtar hushållet på nytt, är ingen ny. Jag själv är aldrig ny.
    public static func newParticipants(_ participants: [HouseholdParticipant], known: Set<String>?, myId: String?) -> [HouseholdParticipant] {
        guard let known else { return [] }
        return participants.filter { $0.id != myId && !known.contains($0.id) }
    }

    /// Id:n för deltagare som var kända men inte längre är med. Saknar listan mig är delningen inte hämtad, och då har
    /// ingen lämnat.
    public static func departedParticipants(_ participants: [HouseholdParticipant], known: Set<String>?, myId: String?) -> [String] {
        guard let known, let myId, participants.contains(where: { $0.id == myId }) else { return [] }
        let current = Set(participants.map(\.id))
        return known.subtracting(current).subtracting([myId]).sorted()
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
    /// Nya adresser får notiser av. De blir huvudadress bara när listan var tom, eftersom en lista alltid har en huvudadress.
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
