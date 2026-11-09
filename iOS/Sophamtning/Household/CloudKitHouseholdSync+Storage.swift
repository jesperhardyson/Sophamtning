import CloudKit
import Foundation
import SophamtningKit

/// Synkens filer i `LocalStore`-katalogen: kopian av posterna och motorernas tillstånd.
extension CloudKitHouseholdSync {
    // MARK: Lagring

    func engineState(named name: String) -> CKSyncEngine.State.Serialization? {
        guard case .value(let data) = stateStore.rawData(named: name) else { return nil }
        return try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func saveEngineState(_ serialization: CKSyncEngine.State.Serialization, scope: CKDatabase.Scope) {
        let name = scope == .private ? Self.privateEngineFile : Self.sharedEngineFile
        do {
            try stateStore.setRawData(try PropertyListEncoder().encode(serialization), named: name)
        } catch {
            logger.error("Kunde inte spara motorns tillstånd: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Läser kopian av posterna. `false` när den saknas eller inte går att läsa, och motorerna då ska börja om.
    static func loadCache(into inner: inout Inner, from store: LocalStore) -> Bool {
        guard case .value(let data) = store.rawData(named: HouseholdRecordCache.fileName),
              let cache = try? PropertyListDecoder().decode(HouseholdRecordCache.self, from: data) else { return false }
        inner.myId = cache.myId
        inner.hasPrivateZone = cache.hasPrivateZone
        if let name = cache.sharedZoneName, let owner = cache.sharedZoneOwner {
            inner.sharedZoneID = CKRecordZone.ID(zoneName: name, ownerName: owner)
        }
        for record in cache.privateRecords.compactMap(HouseholdRecords.unarchive) {
            inner.privateRecords[record.recordID.recordName] = record
        }
        for record in cache.sharedRecords.compactMap(HouseholdRecords.unarchive) {
            inner.sharedRecords[record.recordID.recordName] = record
        }
        inner.known = true
        return true
    }

    static func cache(of inner: Inner) -> HouseholdRecordCache {
        HouseholdRecordCache(
            myId: inner.myId,
            hasPrivateZone: inner.hasPrivateZone,
            sharedZoneName: inner.sharedZoneID?.zoneName,
            sharedZoneOwner: inner.sharedZoneID?.ownerName,
            privateRecords: inner.privateRecords.values.compactMap(HouseholdRecords.archive),
            sharedRecords: inner.sharedRecords.values.compactMap(HouseholdRecords.archive)
        )
    }
}
