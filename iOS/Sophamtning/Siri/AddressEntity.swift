import AppIntents
import SophamtningKit

/// En sparad adress, som Siri och Genvägar kan fråga efter. Id:t är adressens filnamn, som bara jämförs med de sparade
/// adresserna och aldrig tolkas.
struct AddressEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Adress"
    static let defaultQuery = AddressQuery()

    let id: String
    let name: String
    let place: String

    init(_ address: SavedAddress) {
        id = SiriAnswers.id(for: address)
        name = address.displayName
        place = HomeContent.lines(for: address).singleLine
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(place)")
    }
}

/// Alla sparade adresser, också delade från hushållet. Läser bara från lagringen.
struct AddressQuery: EntityQuery {
    func entities(for identifiers: [AddressEntity.ID]) async throws -> [AddressEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AddressEntity] {
        Self.all()
    }

    private static func all() -> [AddressEntity] {
        LocalStore.shared().addresses().map(AddressEntity.init)
    }
}
