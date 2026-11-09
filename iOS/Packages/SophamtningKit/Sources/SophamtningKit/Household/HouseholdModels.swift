import Foundation

/// Min roll i hushållet. `none` är att jag inte delar med någon.
public enum HouseholdRole: String, Codable, Sendable {
    case none, owner, member
}

public struct HouseholdParticipant: Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var isOwner: Bool

    public init(id: String, name: String, isOwner: Bool) {
        self.id = id
        self.name = name
        self.isOwner = isOwner
    }
}

/// En adress som delas i hushållet, och vem som lade till den.
public struct HouseholdAddress: Hashable, Codable, Sendable {
    public var address: SavedAddress
    public var addedBy: String

    public init(address: SavedAddress, addedBy: String) {
        self.address = address
        self.addedBy = addedBy
    }
}

/// En bock i hushållet: vem som ställde ut, när, och om den ännu inte nått iCloud.
public struct HouseholdMark: Hashable, Codable, Sendable {
    public var placedOut: PlacedOut
    public var by: String
    public var at: Date
    public var isPending: Bool

    public init(placedOut: PlacedOut, by: String, at: Date, isPending: Bool) {
        self.placedOut = placedOut
        self.by = by
        self.at = at
        self.isPending = isPending
    }
}

/// Hushållets läge. Tekniska fel ger `failed`, aldrig ett tomt hushåll.
public enum HouseholdStatus: Hashable, Codable, Sendable {
    case synced
    case notSignedIn
    case quotaExceeded(ownerName: String)
    case removed
    case failed
}

/// Det senast kända hushållet, sparat lokalt så att det syns utan nät.
public struct HouseholdState: Hashable, Codable, Sendable {
    public var role: HouseholdRole
    public var myId: String?
    public var participants: [HouseholdParticipant]
    public var addresses: [HouseholdAddress]
    public var marks: [HouseholdMark]
    public var status: HouseholdStatus
    /// Mitt namn som det är sparat i hushållet, eller `nil` när jag inte har skrivit något än.
    public var myName: String?
    /// Mitt förnamn från Apple-kontot, när iOS vet det. Fyller i fältet Ditt namn.
    public var suggestedName: String?

    public init(role: HouseholdRole, myId: String?, participants: [HouseholdParticipant], addresses: [HouseholdAddress], marks: [HouseholdMark], status: HouseholdStatus, myName: String? = nil, suggestedName: String? = nil) {
        self.role = role
        self.myId = myId
        self.participants = participants
        self.addresses = addresses
        self.marks = marks
        self.status = status
        self.myName = myName
        self.suggestedName = suggestedName
    }

    /// Inget hushåll: ingen roll, inget innehåll och inga fel.
    public static let empty = HouseholdState(role: .none, myId: nil, participants: [], addresses: [], marks: [], status: .synced)
}

/// Mina val för hushållet. Fält som saknas i en äldre fil får sina standardvärden.
public struct HouseholdPreferences: Hashable, Codable, Sendable {
    /// Tysta min påminnelse när någon annan har ställt ut. På från början.
    public var silenceWhenOthersPlaceOut: Bool
    /// Notiser från hushållet: när någon ställer ut kärlen och när någon går med. Av från början.
    public var notifyWhenOthersPlaceOut: Bool
    /// Adresser som kom från hushållet. Bara de tas bort när de slutar delas.
    public var receivedKeys: Set<AddressKey>
    /// Andras bockar som redan gett en notis, så att ingen visas två gånger.
    public var notifiedMarks: Set<PlacedOut>
    /// Mitt namn i hushållet, som de andra ser. Skrivs när jag sparar det och skickas till hushållet tills det står där.
    public var myName: String?
    /// Deltagarna som redan är kända. `nil` tills hushållet har setts synkat en gång, och då räknas ingen som ny.
    public var knownParticipants: Set<String>?
    /// Namnen i raden "{namn} gick med i hushållet", tills arket Hushåll har öppnats eller raden stängts.
    public var joinedNames: [String]

    public init(
        silenceWhenOthersPlaceOut: Bool = true,
        notifyWhenOthersPlaceOut: Bool = false,
        receivedKeys: Set<AddressKey> = [],
        notifiedMarks: Set<PlacedOut> = [],
        knownParticipants: Set<String>? = nil,
        joinedNames: [String] = [],
        myName: String? = nil
    ) {
        self.myName = myName
        self.silenceWhenOthersPlaceOut = silenceWhenOthersPlaceOut
        self.notifyWhenOthersPlaceOut = notifyWhenOthersPlaceOut
        self.receivedKeys = receivedKeys
        self.notifiedMarks = notifiedMarks
        self.knownParticipants = knownParticipants
        self.joinedNames = joinedNames
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        silenceWhenOthersPlaceOut = try container.decodeIfPresent(Bool.self, forKey: .silenceWhenOthersPlaceOut) ?? true
        notifyWhenOthersPlaceOut = try container.decodeIfPresent(Bool.self, forKey: .notifyWhenOthersPlaceOut) ?? false
        receivedKeys = try container.decodeIfPresent(Set<AddressKey>.self, forKey: .receivedKeys) ?? []
        notifiedMarks = try container.decodeIfPresent(Set<PlacedOut>.self, forKey: .notifiedMarks) ?? []
        knownParticipants = try container.decodeIfPresent(Set<String>.self, forKey: .knownParticipants)
        joinedNames = try container.decodeIfPresent([String].self, forKey: .joinedNames) ?? []
        myName = try container.decodeIfPresent(String.self, forKey: .myName)
    }
}
