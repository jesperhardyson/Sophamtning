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

    /// Delningen ändrades i `UICloudSharingController`, till exempel en ny deltagare.
    func shareDidChange(_ share: CKShare) {
        mutate { inner in
            if inner.hasPrivateZone { inner.privateRecords[share.recordID.recordName] = share }
        }
        emit()
    }

    /// Hämtar delningen direkt från iCloud. Att någon har accepterat inbjudan kommer inte alltid som en ändring i zonen,
    /// så deltagarna läses om vid varje hämtning. Ett fel här ändrar ingenting: zonens ändringar gäller då som förut.
    func refreshShare() async {
        let target = inner.withLock { inner -> (CKDatabase, CKRecordZone.ID)? in
            if inner.hasPrivateZone, inner.privateRecords[CKRecordNameZoneWideShare] is CKShare {
                return (container.privateCloudDatabase, HouseholdRecords.privateZoneID)
            }
            if let zoneID = inner.sharedZoneID { return (container.sharedCloudDatabase, zoneID) }
            return nil
        }
        guard let (database, zoneID) = target else { return }
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let fetched: CKShare
        do {
            guard let share = try await database.record(for: id) as? CKShare else { return }
            fetched = share
        } catch {
            logger.error("Kunde inte hämta delningen: \(error.localizedDescription, privacy: .public)")
            return
        }
        mutate { inner in
            if database.databaseScope == .private, inner.hasPrivateZone {
                inner.privateRecords[CKRecordNameZoneWideShare] = fetched
            } else if database.databaseScope == .shared, inner.sharedZoneID == zoneID {
                inner.sharedRecords[CKRecordNameZoneWideShare] = fetched
            }
        }
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
            // Hushållets poster är inte hämtade än. Inget synkat läge skickas förrän de är det.
            inner.trust.restarted()
        }
        emit()
        await fetchChanges()
    }
}
