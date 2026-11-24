import Foundation

/// Hushållet som ligger kvar i iCloud, under tiden som hushållen flyttas till brevlådan.
public protocol LegacyHousehold: HouseholdSync {
    /// Mitt id i iCloud, eller `nil` innan det är känt.
    var legacyMyId: String? { get }
    /// Hushållet när det är fullständigt hämtat och synkat, annars `nil`. Ett osäkert läge flyttas aldrig.
    func legacySnapshot() async -> HouseholdState?
    /// Länken till brevlådan som ägaren har lagt i zonen, eller `nil`.
    func migrationLink() async -> URL?
    func writeMigrationLink(_ url: URL) async throws
    /// Tar bort delningen och zonen. Bara ägaren.
    func removeShare() async throws
}

/// Var flytten är på den här telefonen, `household-migration.json`.
public struct HouseholdMigration: Hashable, Codable, Sendable {
    /// När ägaren började flytta sitt hushåll.
    public var startedAt: Date?
    /// Inbjudan i `HushallFlytt`, och när den går ut.
    public var link: URL?
    public var linkExpiresAt: Date?
    /// Länken ligger i zonen.
    public var linkWritten = false
    /// Hushållet finns i brevlådan, och det i iCloud gäller inte längre på den här telefonen.
    public var moved = false
    public var shareRemoved = false

    public init() {}

    /// Ägaren har börjat men inte blivit klar. Till dess gäller hushållet i iCloud.
    var inProgress: Bool { startedAt != nil && !moved }
}

public final class HouseholdMigrationStore: Sendable {
    private static let fileName = "household-migration.json"
    private let store: LocalStore

    public init(store: LocalStore) {
        self.store = store
    }

    /// `nil` när filen inte går att läsa just nu. Då görs inget, och iCloud räknas inte bort.
    public var current: HouseholdMigration? {
        switch store.rawData(named: Self.fileName) {
        case .value(let data): try? JSONDecoder().decode(HouseholdMigration.self, from: data)
        case .missing: HouseholdMigration()
        case .unavailable, .unreadable: nil
        }
    }

    func save(_ migration: HouseholdMigration) throws {
        try store.setRawData(JSONEncoder().encode(migration), named: Self.fileName)
    }

    func reset() {
        try? store.removeRawData(named: Self.fileName)
    }
}
