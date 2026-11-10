import Foundation

/// Om synkens kopia av hushållet går att lita på. Appens CloudKit-synk sparar den med posterna, så att ett avbrott
/// (appen stängs mitt i en hämtning, utloggning, motorer som börjar om) aldrig ger ett synkat läge som saknar hushållet
/// eller dess adresser.
public struct HouseholdSyncTrust: Hashable, Codable, Sendable {
    /// En fullständig hämtning har lyckats sedan kopian senast började om.
    public private(set) var complete: Bool
    /// Kontot loggades ut. Motorerna har då börjat om, och kopian töms när kontot är tillbaka.
    public private(set) var resetOnSignIn: Bool

    public init(complete: Bool = false, resetOnSignIn: Bool = false) {
        self.complete = complete
        self.resetOnSignIn = resetOnSignIn
    }

    /// En hämtning av båda databaserna har lyckats. Väntar kopian på att tömmas vid inloggningen gör hämtningen den inte
    /// pålitlig, eftersom den kan blanda poster från före och efter utloggningen.
    public mutating func fetchCompleted() {
        guard !resetOnSignIn else { return }
        complete = true
    }

    /// Motorerna började om utan sparat tillstånd, eller ett nytt hushåll har ännu inte hämtats. Kopian ska tömmas,
    /// eller fyllas, innan den gäller.
    public mutating func restarted() {
        complete = false
    }

    public mutating func signedOut() {
        resetOnSignIn = true
    }

    /// Inloggad igen. Svarar med om kopian ska tömmas, eftersom motorerna började om vid utloggningen.
    public mutating func signedIn() -> Bool {
        guard resetOnSignIn else { return false }
        resetOnSignIn = false
        complete = false
        return true
    }

    /// Ett annat konto: kopian töms, och inget gäller förrän det nya kontot har hämtats.
    public mutating func switchedAccount() {
        resetOnSignIn = false
        complete = false
    }

    /// Läget som får skickas. Innan kopian är komplett skickas bara lägen med fel, utan roll och innehåll, som appens modell
    /// behandlar som "behåll det senast sparade". Ett synkat läge skickas aldrig då.
    public func gate(_ state: HouseholdState) -> HouseholdState? {
        if complete { return state }
        guard state.status != .synced else { return nil }
        return HouseholdState(role: .none, myId: state.myId, participants: [], addresses: [], marks: [], status: state.status)
    }
}

/// Synkens sparade kopia: posterna som arkiverad data (paketet tolkar dem inte), vilken delad zon som gäller, mitt id
/// och om kopian går att lita på. Sparas som `household-records.data` i `LocalStore`-katalogen.
public struct HouseholdSyncCache: Hashable, Codable, Sendable {
    public static let fileName = "household-records.data"

    public var myId: String?
    public var hasPrivateZone: Bool
    public var sharedZoneName: String?
    public var sharedZoneOwner: String?
    public var privateRecords: [Data]
    public var sharedRecords: [Data]
    public var trust: HouseholdSyncTrust

    public init(myId: String? = nil, hasPrivateZone: Bool = false, sharedZoneName: String? = nil, sharedZoneOwner: String? = nil, privateRecords: [Data] = [], sharedRecords: [Data] = [], trust: HouseholdSyncTrust = HouseholdSyncTrust()) {
        self.myId = myId
        self.hasPrivateZone = hasPrivateZone
        self.sharedZoneName = sharedZoneName
        self.sharedZoneOwner = sharedZoneOwner
        self.privateRecords = privateRecords
        self.sharedRecords = sharedRecords
        self.trust = trust
    }

    /// En fil utan `trust` är från innan den sparades och räknas som inte komplett.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myId = try container.decodeIfPresent(String.self, forKey: .myId)
        hasPrivateZone = try container.decodeIfPresent(Bool.self, forKey: .hasPrivateZone) ?? false
        sharedZoneName = try container.decodeIfPresent(String.self, forKey: .sharedZoneName)
        sharedZoneOwner = try container.decodeIfPresent(String.self, forKey: .sharedZoneOwner)
        privateRecords = try container.decodeIfPresent([Data].self, forKey: .privateRecords) ?? []
        sharedRecords = try container.decodeIfPresent([Data].self, forKey: .sharedRecords) ?? []
        trust = try container.decodeIfPresent(HouseholdSyncTrust.self, forKey: .trust) ?? HouseholdSyncTrust()
    }

    /// Läser kopian. En fil som inte går att tolka är `unreadable`, och synken börjar då om.
    public static func load(from store: LocalStore) -> StoreRead<HouseholdSyncCache> {
        switch store.rawData(named: fileName) {
        case .value(let data):
            guard let cache = try? PropertyListDecoder().decode(HouseholdSyncCache.self, from: data) else { return .unreadable }
            return .value(cache)
        case .missing: return .missing
        case .unavailable: return .unavailable
        case .unreadable: return .unreadable
        }
    }

    public func save(to store: LocalStore) throws {
        try store.setRawData(try PropertyListEncoder().encode(self), named: Self.fileName)
    }
}
