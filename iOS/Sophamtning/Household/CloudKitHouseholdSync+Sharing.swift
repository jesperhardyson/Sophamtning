import CloudKit
import Foundation
import SophamtningKit

/// Delningen av zonen `Hushall` och inbjudningarna till den.
extension CloudKitHouseholdSync {
    // MARK: Delning

    /// Delningen för hushållet: ägarens om jag är ägare, annars den jag är med i.
    var share: CKShare? {
        inner.withLock { inner in
            if inner.hasPrivateZone, let share = inner.privateRecords[CKRecordNameZoneWideShare] as? CKShare { return share }
            return inner.sharedRecords[CKRecordNameZoneWideShare] as? CKShare
        }
    }

    /// Skapar zonen `Hushall` och en delning av hela zonen, eller ger den som redan finns.
    func makeShare() async throws -> CKShare {
        if inner.withLock({ $0.hasPrivateZone }), let existing = share { return existing }
        _ = try await requireMyId()
        let database = container.privateCloudDatabase
        let zoneID = HouseholdRecords.privateZoneID
        let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        for result in zones.saveResults.values { _ = try result.get() }

        let newShare = CKShare(recordZoneID: zoneID)
        newShare[CKShare.SystemFieldKey.title] = HouseholdRecords.shareTitle as NSString
        newShare.publicPermission = .none
        let saved: CKShare
        do {
            let results = try await database.modifyRecords(saving: [newShare], deleting: [])
            guard let result = results.saveResults.values.first, let share = try result.get() as? CKShare else {
                throw HouseholdSyncError.shareMissing
            }
            saved = share
        } catch let error as CKError where error.code == .serverRecordChanged {
            // En annan av mina enheter hann skapa delningen först. Den gäller.
            guard let server = error.serverRecord as? CKShare else { throw error }
            saved = server
        }
        mutate { inner in
            inner.hasPrivateZone = true
            inner.privateRecords[saved.recordID.recordName] = saved
            inner.known = true
            inner.status = .synced
        }
        emit()
        return saved
    }

    /// Delningen ändrades i `UICloudSharingController`, till exempel en ny deltagare.
    func shareDidChange(_ share: CKShare) {
        mutate { inner in
            if inner.hasPrivateZone { inner.privateRecords[share.recordID.recordName] = share }
        }
        emit()
    }

    /// Ägaren slutade dela i `UICloudSharingController`. Då avslutas hushållet, som med Avsluta hushållet.
    func sharingDidStop() async {
        do {
            try await deleteZone(HouseholdRecords.privateZoneID, in: container.privateCloudDatabase)
        } catch {
            logger.error("Kunde inte ta bort zonen efter att delningen slutade: \(error.localizedDescription, privacy: .public)")
        }
        dropPrivateZone()
    }

    // MARK: Inbjudan

    /// Om inbjudan gäller hushållet jag redan är med i, som ägare eller medlem.
    func isCurrentHousehold(_ metadata: CKShare.Metadata) -> Bool {
        if metadata.participantRole == .owner { return true }
        return inner.withLock { $0.sharedZoneID == metadata.share.recordID.zoneID }
    }

    /// Accepterar en inbjudan och hämtar hushållet.
    func accept(_ metadata: CKShare.Metadata) async throws {
        let accepted = try await container.accept(metadata)
        mutate { inner in
            inner.sharedZoneID = accepted.recordID.zoneID
            inner.sharedRecords = [accepted.recordID.recordName: accepted]
            inner.status = .synced
        }
        emit()
        await fetchChanges()
    }
}
