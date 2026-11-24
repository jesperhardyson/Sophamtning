import CloudKit
import Foundation
import SophamtningKit

/// Det som flytten till brevlådan behöver av hushållet i iCloud. Tas bort tillsammans med resten av CloudKit-synken.
extension CloudKitHouseholdSync: LegacyHousehold {
    var legacyMyId: String? {
        inner.withLock { $0.myId }
    }

    /// Bara ett fullständigt hämtat och synkat hushåll där allt har skickats flyttas.
    func legacySnapshot() async -> HouseholdState? {
        let engines = inner.withLock { [$0.privateEngine, $0.sharedEngine].compactMap { $0 } }
        guard engines.allSatisfy({ $0.state.pendingRecordZoneChanges.isEmpty }) else { return nil }
        return inner.withLock { inner in
            guard inner.signedIn, inner.trust.complete, inner.retry.isEmpty, inner.retryShared.isEmpty,
                  let state = Self.state(of: inner, pending: []), state.role != .none, state.status == .synced else { return nil }
            return state
        }
    }

    var isReliablyEmpty: Bool {
        inner.withLock { $0.signedIn && $0.trust.complete && $0.status != .failed && Self.role(of: $0) == .none }
    }

    func removeParticipants(_ ids: [String]) async throws {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: HouseholdRecords.privateZoneID)
        guard let share = try await container.privateCloudDatabase.record(for: id) as? CKShare else { throw HouseholdSyncError.shareMissing }
        let removed = share.participants.filter { participant in
            participant.role != .owner && participant.userIdentity.userRecordID.map { ids.contains($0.recordName) } == true
        }
        guard !removed.isEmpty else { return }
        for participant in removed { share.removeParticipant(participant) }
        let results = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        for result in results.saveResults.values { _ = try result.get() }
    }

    func migrationLink() async -> URL? {
        inner.withLock { inner in
            switch Self.role(of: inner) {
            case .owner: inner.privateRecords[HouseholdRecords.migrationName].flatMap(HouseholdRecords.migrationLink(from:))
            case .member: inner.sharedRecords[HouseholdRecords.migrationName].flatMap(HouseholdRecords.migrationLink(from:))
            case .none: nil
            }
        }
    }

    /// Skrivs direkt och inte via motorn, så att flytten vet att länken har kommit fram.
    func writeMigrationLink(_ url: URL) async throws {
        let record = HouseholdRecords.migrationRecord(link: url, at: Date())
        let results = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        guard let result = results.saveResults.values.first else { throw HouseholdSyncError.shareMissing }
        let saved = try result.get()
        mutate { inner in
            if inner.hasPrivateZone { inner.privateRecords[HouseholdRecords.migrationName] = saved }
        }
    }

    func removeShare() async throws {
        guard inner.withLock({ Self.role(of: $0) }) == .owner else { return }
        try await deleteZone(HouseholdRecords.privateZoneID, in: container.privateCloudDatabase)
        dropPrivateZone()
    }
}
