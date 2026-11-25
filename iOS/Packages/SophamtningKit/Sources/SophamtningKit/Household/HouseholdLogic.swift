import Foundation

/// Rena regler för hushållet. Inget här läser klockan, nätet eller CloudKit.
public enum HouseholdLogic {
    /// Hur ofta ändringarna i ett hushåll i iCloud hämtas medan appen är öppen, som reserv när den tysta pushen dröjer.
    /// Hushåll i brevlådan får i stället en signal när något har ändrats.
    public static let liveFetchInterval: Duration = .seconds(15)

    /// Sant när nästa tömning är i dag eller i morgon, för en delad adress eller en adress med påminnelser på. Utan knappen
    /// går en ångrad bock från Live Activity inte att sätta igen på tömningsdagen, när aktiviteten inte startar om.
    public static func showsPlaceOutButton(isShared: Bool, remindersOn: Bool = false, nextPickup: DayDate?, today: DayDate) -> Bool {
        guard isShared || remindersOn, let nextPickup else { return false }
        return (0...1).contains(today.days(until: nextPickup))
    }

    /// Bocken för adressens nästa tömning, om någon. Bocken gäller hämtdatumet, aldrig dagen då någon tryckte.
    public static func currentMark(for key: AddressKey, nextPickup: DayDate?, in marks: [HouseholdMark]) -> HouseholdMark? {
        guard let nextPickup else { return nil }
        return marks.first { $0.placedOut.key == key && $0.placedOut.date == nextPickup }
    }

    /// Deltagare som har gått med sedan förra synkade läget. Utan kända deltagare (`nil`), när jag just gått med eller
    /// hämtar hushållet på nytt, är ingen ny. Jag själv är aldrig ny, och inte heller den som bara har flyttats från iCloud.
    public static func newParticipants(_ participants: [HouseholdParticipant], known: Set<String>?, myId: String?) -> [HouseholdParticipant] {
        guard let known else { return [] }
        return participants.filter { $0.id != myId && !isKnown($0, known: known) && isPresented($0) }
    }

    /// I brevlådan kommer namnet strax efter att någon har gått med. Till dess räknas personen inte som ny, så att ingen
    /// rad säger "Någon" och den som bara har flyttats från iCloud hinner visa det.
    private static func isPresented(_ participant: HouseholdParticipant) -> Bool {
        !isRelayId(participant.id) || participant.name != HouseholdTexts.unknownName || !participant.legacyIds.isEmpty
    }

    /// Mitt namn så som det sparas: utan mellanslag runt om, och så kort att det ryms hos brevlådan.
    public static func validName(_ name: String) -> String {
        var result = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        while let encoded = try? JSONEncoder().encode(result), encoded.count > 200 { result.removeLast() }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Om deltagaren är känd, med sitt id eller med det som personen hade i iCloud.
    public static func isKnown(_ participant: HouseholdParticipant, known: Set<String>) -> Bool {
        known.contains(participant.id) || participant.legacyIds.contains { known.contains($0) }
    }

    /// Id:n för deltagare som var kända men inte längre är med. Saknar listan mig är delningen inte hämtad, och då har
    /// ingen lämnat. I ett hushåll som har flyttats från iCloud har den som inte har flyttat än inte lämnat.
    public static func departedParticipants(_ participants: [HouseholdParticipant], known: Set<String>?, myId: String?) -> [String] {
        guard let known, let myId, participants.contains(where: { $0.id == myId }) else { return [] }
        let current = Set(participants.map(\.id))
        let departed = known.subtracting(current).subtracting([myId])
        return (isRelayId(myId) ? departed.filter(isRelayId) : departed).sorted()
    }

    /// De kända deltagarna efter ett synkat läge. Id:n från iCloud står kvar i ett flyttat hushåll, så att den som flyttar
    /// senare inte räknas som ny.
    public static func knownAfter(_ participants: [HouseholdParticipant], known: Set<String>?, myId: String?) -> Set<String> {
        let current = Set(participants.map(\.id))
        guard let known, let myId, isRelayId(myId) else { return current }
        let presented = participants.filter { isPresented($0) || known.contains($0.id) || $0.id == myId }.map(\.id)
        return Set(presented).union(known.filter { !isRelayId($0) })
    }

    /// Deltagarens id i brevlådan är 16 byte som base64url. I iCloud ser id:t annorlunda ut.
    static func isRelayId(_ id: String) -> Bool {
        id.utf8.count == 22 && Data(base64URL: id)?.count == 16
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
