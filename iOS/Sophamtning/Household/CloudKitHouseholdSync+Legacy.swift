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
