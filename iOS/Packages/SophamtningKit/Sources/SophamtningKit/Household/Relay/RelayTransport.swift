import Foundation

/// Ett anrop till brevlådan. `path` är relativ till bas-URL:en, till exempel `/households`.
public struct RelayRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct RelayResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// Nätet mot brevlådan, så att synken kan prövas mot en server i minnet.
public protocol RelayTransport: Sendable {
    /// Kastar bara när inget svar kom, till exempel utan nät. Ett svar med en felstatus kastas inte.
    func send(_ request: RelayRequest) async throws -> RelayResponse
    /// Löpnumret varje gång något har ändrats, så länge någon lyssnar. Ger `0` efter varje ny uppkoppling, eftersom
    /// ändringar kan ha missats när den var nere.
    func signals(householdId: String, authorization: String) -> AsyncStream<Int>
}

/// Det som gör telefonen till en deltagare. Hemligt, och sparas bara i nyckelringen.
public struct HouseholdCredentials: Codable, Hashable, Sendable {
    public var householdId: String
    public var householdKey: Data
    public var participantId: String
    public var participantSecret: String

    public init(householdId: String, householdKey: Data, participantId: String, participantSecret: String) {
        self.householdId = householdId
        self.householdKey = householdKey
        self.participantId = participantId
        self.participantSecret = participantSecret
    }

    var authorization: String { "Bearer \(participantId).\(participantSecret)" }
}

extension HouseholdCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "HouseholdCredentials" }
    public var debugDescription: String { description }
}

/// Var nycklarna sparas. `load` svarar `nil` bara när det säkert inte finns några, och kastar när det inte går att läsa,
/// till exempel innan telefonen har låsts upp. Då vet appen inte om den är med i ett hushåll.
public protocol HouseholdCredentialStore: Sendable {
    func load() throws -> HouseholdCredentials?
    func save(_ credentials: HouseholdCredentials) throws
    func delete() throws
}

/// Nycklarna i iCloud-nyckelringen och en kopia på den här telefonen.
///
/// Försvinner de synkade, för att jag har lämnat på en annan telefon eller stängt av iCloud-nyckelringen, används kopian.
/// Då är det serverns svar som avgör om jag fortfarande är med, aldrig att en post saknas.
public final class LayeredCredentialStore: HouseholdCredentialStore {
    private let synced: any HouseholdCredentialStore
    private let local: any HouseholdCredentialStore

    public init(synced: any HouseholdCredentialStore, local: any HouseholdCredentialStore) {
        self.synced = synced
        self.local = local
    }

    public func load() throws -> HouseholdCredentials? {
        let mine = try local.load()
        // Går den synkade inte att läsa gäller kopian. Finns ingen kopia vet appen inte, och felet går vidare.
        guard let shared = mine == nil ? try synced.load() : try? synced.load() else { return mine }
        if shared != mine { try? local.save(shared) }
        return shared
    }

    public func save(_ credentials: HouseholdCredentials) throws {
        try local.save(credentials)
        try synced.save(credentials)
    }

    public func delete() throws {
        try synced.delete()
        try local.delete()
    }
}
