import CloudKit
import Foundation
import SophamtningKit

/// Händelserna från de två `CKSyncEngine`, en för den privata databasen (ägaren) och en för den delade (medlem).
/// Vilken motor det är syns på `syncEngine.database.databaseScope`.
extension CloudKitHouseholdSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let scope = syncEngine.database.databaseScope
        switch event {
        case .stateUpdate(let update):
            saveEngineState(update.stateSerialization, scope: scope)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleDatabaseChanges(changes, scope: scope)
        case .fetchedRecordZoneChanges(let changes):
            handleRecordZoneChanges(changes, scope: scope)
        case .sentRecordZoneChanges(let sent):
            handleSentRecordZoneChanges(sent, scope: scope, engine: syncEngine)
        case .didFetchRecordZoneChanges(let fetched):
            if let error = fetched.error { handleZoneError(error, zoneID: fetched.zoneID, scope: scope) }
        case .didFetchChanges:
            // En hämtning som en tyst push startade läser också om delningen, så att nya och inbjudna deltagare syns.
            refreshShareOutsideCallback()
        case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges, .didSendChanges:
            // Zonerna skapas och tas bort direkt mot databasen, inte via motorn.
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = syncEngine.database.databaseScope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let records = inner.withLock { Self.records(in: $0, scope: scope) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            // En post som har tagits bort lokalt, eller hör till en annan zon, ska inte sparas. Den väntande sparningen
            // tas bort, som i Apples exempel, så att den inte ligger kvar och visas som väntande.
            guard let record = records[recordID.recordName], record.recordID == recordID else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return record
        }
    }

    // MARK: Konto

    /// Utloggad: posterna står kvar som cache med "Synkar inte just nu". Ett annat konto är inte med i hushållet.
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            mutate { inner in
                inner.signedIn = true
                if inner.trust.signedIn() {
                    // Motorerna började om vid utloggningen, så allt hämtas igen. Innan dess skickas inget synkat läge.
                    Self.clearHousehold(&inner)
                }
            }
            emit()
            fetchChangesOutsideCallback()
        case .signOut:
            mutate { inner in
                inner.signedIn = false
                inner.trust.signedOut()
            }
            emit()
        case .switchAccounts:
            mutate { inner in
                Self.clearHousehold(&inner)
                inner.myId = nil
                inner.signedIn = true
                // Det nya kontot är inte med i hushållet, men det syns först när dess hämtning har lyckats.
                inner.trust.switchedAccount()
            }
            emit()
            fetchChangesOutsideCallback()
        @unknown default:
            break
        }
    }

    /// Hämtar ändringar utanför motorns callback. En vanlig `Task` ärver callbackens sammanhang, och då stoppar
    /// CKSyncEngine appen ("Cannot await a call into CKSyncEngine from within a delegate callback"). Därför `detached`.
    private func fetchChangesOutsideCallback() {
        Task.detached { [self] in await fetchChanges() }
    }

    /// Läser om delningen utanför motorns callback, av samma skäl som ovan, och skickar det nya läget.
    private func refreshShareOutsideCallback() {
        Task.detached { [self] in
            await refreshShare()
            emit()
        }
    }

    static func clearHousehold(_ inner: inout Inner) {
        inner.hasPrivateZone = false
        inner.privateRecords = [:]
        inner.sharedZoneID = nil
        inner.sharedRecords = [:]
        inner.retry = []
        inner.retryShared = []
        inner.status = .synced
    }

    // MARK: Hämtat

    private func handleDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges, scope: CKDatabase.Scope) {
        var droppedPrivate = false
        var removedShared: CKRecordZone.ID?
        mutate { inner in
            for modification in changes.modifications where modification.zoneID.zoneName == HouseholdRecords.zoneName {
                if scope == .private {
                    inner.hasPrivateZone = true
                } else if inner.sharedZoneID == nil {
                    inner.sharedZoneID = modification.zoneID
                }
            }
            for deletion in changes.deletions where deletion.zoneID.zoneName == HouseholdRecords.zoneName {
                if scope == .private {
                    // Ägaren avslutade hushållet på en annan av sina enheter.
                    droppedPrivate = inner.hasPrivateZone
                } else if inner.sharedZoneID == deletion.zoneID {
                    // Ägaren avslutade hushållet eller tog bort mig.
                    removedShared = deletion.zoneID
                }
            }
        }
        if droppedPrivate { dropPrivateZone() }
        if let removedShared { dropSharedZone(removedShared, status: .removed) }
        emit()
    }

    private func handleRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, scope: CKDatabase.Scope) {
        mutate { inner in
            for modification in changes.modifications {
                let record = modification.record
                guard Self.accepts(record.recordID.zoneID, scope: scope, inner: &inner) else { continue }
                if scope == .private {
                    inner.privateRecords[record.recordID.recordName] = record
                } else {
                    inner.sharedRecords[record.recordID.recordName] = record
                }
            }
            for deletion in changes.deletions {
                guard Self.accepts(deletion.recordID.zoneID, scope: scope, inner: &inner) else { continue }
                if scope == .private {
                    inner.privateRecords[deletion.recordID.recordName] = nil
                } else {
                    inner.sharedRecords[deletion.recordID.recordName] = nil
                }
            }
        }
        emit()
    }

    /// Om en post i zonen hör till hushållet. Den första delade zonen `Hushall` som syns blir medlemmens hushåll.
    private static func accepts(_ zoneID: CKRecordZone.ID, scope: CKDatabase.Scope, inner: inout Inner) -> Bool {
        guard zoneID.zoneName == HouseholdRecords.zoneName else { return false }
        if scope == .private {
            inner.hasPrivateZone = true
            return true
        }
        if inner.sharedZoneID == nil { inner.sharedZoneID = zoneID }
        return inner.sharedZoneID == zoneID
    }

    // MARK: Skickat

    private func handleSentRecordZoneChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, scope: CKDatabase.Scope, engine: CKSyncEngine) {
        let ownerName = HouseholdRecords.ownerName(of: share)
        var requeue: [CKSyncEngine.PendingRecordZoneChange] = []
        var zoneGone: CKRecordZone.ID?

        mutate { inner in
            var newStatus: HouseholdStatus?
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []

            for saved in sent.savedRecords {
                let name = saved.recordID.recordName
                // En post som togs bort medan den skickades får inte komma tillbaka.
                if scope == .private, inner.privateRecords[name] != nil { inner.privateRecords[name] = saved }
                if scope == .shared, inner.sharedRecords[name] != nil { inner.sharedRecords[name] = saved }
            }

            for failure in sent.failedRecordSaves {
                let recordID = failure.record.recordID
                let name = recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Serverns post gäller: första trycket vinner.
                    guard let server = failure.error.serverRecord else { break }
                    if scope == .private { inner.privateRecords[name] = server } else { inner.sharedRecords[name] = server }
                case .zoneNotFound, .userDeletedZone:
                    zoneGone = recordID.zoneID
                case .unknownItem:
                    // Posten har tagits bort på servern sedan den hämtades. Den skrivs igen som ny.
                    let local = scope == .private ? inner.privateRecords[name] : inner.sharedRecords[name]
                    guard let local else { break }
                    let fresh = HouseholdRecords.freshCopy(of: local)
                    if scope == .private { inner.privateRecords[name] = fresh } else { inner.sharedRecords[name] = fresh }
                    requeue.append(.saveRecord(recordID))
                default:
                    guard let status = HouseholdRecords.status(for: failure.error, ownerName: ownerName) else { break }
                    newStatus = status
                    if case .quotaExceeded = status { retry.append(.saveRecord(recordID)) }
                }
            }

            for (recordID, error) in sent.failedRecordDeletes {
                switch error.code {
                case .unknownItem:
                    // Redan borta.
                    break
                case .zoneNotFound, .userDeletedZone:
                    zoneGone = recordID.zoneID
                default:
                    guard let status = HouseholdRecords.status(for: error, ownerName: ownerName) else { break }
                    newStatus = status
                    if case .quotaExceeded = status { retry.append(.deleteRecord(recordID)) }
                }
            }

            if let newStatus {
                if newStatus == .notSignedIn { inner.signedIn = false } else { inner.status = newStatus }
            } else if sent.failedRecordSaves.isEmpty, sent.failedRecordDeletes.isEmpty, inner.status != .removed {
                // Allt gick fram, så ett tidigare fel gäller inte längre.
                inner.status = .synced
            }
            if scope == .private { inner.retry += retry } else { inner.retryShared += retry }
        }

        engine.state.add(pendingRecordZoneChanges: requeue)
        if let zoneGone { dropZone(zoneGone, scope: scope) }
        emit()
    }

    /// Ett fel när en zon hämtades. En borttagen delad zon betyder att jag inte längre är med.
    private func handleZoneError(_ error: CKError, zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        switch error.code {
        case .zoneNotFound, .userDeletedZone:
            dropZone(zoneID, scope: scope)
        default:
            record(error, scope: scope)
            emit()
        }
    }

    private func dropZone(_ zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        guard zoneID.zoneName == HouseholdRecords.zoneName else { return }
        if scope == .private {
            dropPrivateZone()
        } else {
            dropSharedZone(zoneID, status: .removed)
        }
    }
}
