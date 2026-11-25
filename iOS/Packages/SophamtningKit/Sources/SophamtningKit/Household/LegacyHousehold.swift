import Foundation

/// Hushållet som ligger kvar i iCloud, under tiden som hushållen flyttas till brevlådan.
public protocol LegacyHousehold: HouseholdSync {
    /// Mitt id i iCloud, eller `nil` innan det är känt.
    var legacyMyId: String? { get }
    /// Hushållet när det är fullständigt hämtat och synkat, annars `nil`. Ett osäkert läge flyttas aldrig.
    func legacySnapshot() async -> HouseholdState?
    /// Sant bara när iCloud säkert har svarat att det inte finns något hushåll.
    var isReliablyEmpty: Bool { get }
    /// Länken till brevlådan som ägaren har lagt i zonen, eller `nil`.
    func migrationLink() async -> URL?
    func writeMigrationLink(_ url: URL) async throws
    /// Tar bort deltagare ur delningen, så att de inte kan läsa länken i zonen. Bara ägaren.
    func removeParticipants(_ ids: [String]) async throws
    /// Tar bort delningen och zonen. Bara ägaren.
    func removeShare() async throws
}

/// Var flytten är på den här telefonen, `household-migration.json`.
public struct HouseholdMigration: Hashable, Codable, Sendable {
    /// När ägaren började flytta sitt hushåll.
    public var startedAt: Date?
    /// När inbjudan i `HushallFlytt` går ut. Själva länken är hemlig och sparas inte här.
    public var linkExpiresAt: Date?
    /// Någon har tagits bort, och länken i zonen måste göras om. Id:na är de som ska ut ur delningen.
    public var linkNeedsRenewal = false
    public var removedLegacyIds: [String] = []
    /// När ägarens andra enhet såg länken utan att ha nycklarna.
    public var linkSeenAt: Date?
    /// Hushållet är avslutat, enligt servern eller på den här telefonen. Aldrig för att något saknas.
    public var ended = false
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

    /// Ändrar filen, om den går att läsa.
    func update(_ change: (inout HouseholdMigration) -> Void) {
        guard var migration = current else { return }
        let before = migration
        change(&migration)
        if migration != before { try? save(migration) }
    }

    func save(_ migration: HouseholdMigration) throws {
        try store.setRawData(JSONEncoder().encode(migration), named: Self.fileName)
    }

    func reset() {
        try? store.removeRawData(named: Self.fileName)
    }
}
