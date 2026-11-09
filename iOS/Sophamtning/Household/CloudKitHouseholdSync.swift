import CloudKit
import Foundation
import os
import SophamtningKit
import Synchronization

enum HouseholdSyncError: Error {
    /// Det finns inget hushåll att skriva till.
    case noHousehold
    /// CloudKit svarade utan delning.
    case shareMissing
}

/// Hushållets synk med CloudKit. Ägaren har zonen `Hushall` i sin privata databas och delar hela zonen med en `CKShare`.
/// En medlem ser samma zon i sin delade databas. En `CKSyncEngine` per databas skickar och hämtar posterna, köar ändringar
/// utan nät och sköter prenumerationerna för tyst push.
///
/// Synken har en egen kopia av posterna med systemfält (`household-records.data`), och motorernas tillstånd sparas som
/// `household-engine-private.data` och `household-engine-shared.data`. Ett nytt läge skickas bara när det har ändrats.
/// Händelserna från motorerna hanteras i `CloudKitHouseholdSync+Engine.swift`, delningen i `+Sharing` och filerna i `+Storage`.
final class CloudKitHouseholdSync: HouseholdSync {
    static let privateEngineFile = "household-engine-private.data"
    static let sharedEngineFile = "household-engine-shared.data"

    struct Inner {
        var myId: String?
        var signedIn = true
        var status: HouseholdStatus = .synced
        /// Om posterna går att lita på: kopian lästes, eller en hämtning har lyckats. Innan dess skickas bara lägen med fel,
        /// så att appen aldrig tror att hushållet är tomt.
        var known = false
        var hasPrivateZone = false
        var sharedZoneID: CKRecordZone.ID?
        var privateRecords: [String: CKRecord] = [:]
        var sharedRecords: [String: CKRecord] = [:]
        /// Ändringar som motorn inte försöker igen med själv, till exempel efter `quotaExceeded`. De köas vid nästa hämtning.
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var retryShared: [CKSyncEngine.PendingRecordZoneChange] = []
        /// Efter en utloggning har motorerna börjat om, så posterna hämtas på nytt när kontot är tillbaka.
        var resetOnSignIn = false
        var lastEmitted: HouseholdState?
        var continuations: [UUID: AsyncStream<HouseholdState>.Continuation] = [:]
        var privateEngine: CKSyncEngine?
        var sharedEngine: CKSyncEngine?
    }

    let container: CKContainer
    let stateStore: LocalStore
    let inner: Mutex<Inner>
    let logger = Logger(subsystem: "se.hardyson.sophamtning", category: "Hushall")

    init(container: CKContainer, stateStore: LocalStore) {
        self.container = container
        self.stateStore = stateStore
        var initial = Inner()
        let loaded = Self.loadCache(into: &initial, from: stateStore)
        inner = Mutex(initial)
        if !loaded {
            // Utan kopian av posterna måste motorerna hämta allt från början.
            try? stateStore.removeRawData(named: Self.privateEngineFile)
            try? stateStore.removeRawData(named: Self.sharedEngineFile)
        }
        let privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: loaded ? engineState(named: Self.privateEngineFile) : nil,
            delegate: self
        ))
        let sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: loaded ? engineState(named: Self.sharedEngineFile) : nil,
            delegate: self
        ))
        inner.withLock {
            $0.privateEngine = privateEngine
            $0.sharedEngine = sharedEngine
        }
        // Kontot läses vid start och när det ändras.
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.fetchChanges() }
        }
        emit()
        Task { await self.fetchChanges() }
    }

    // MARK: HouseholdSync

    func states() -> AsyncStream<HouseholdState> {
        let id = UUID()
        return AsyncStream { continuation in
            inner.withLock { inner in
                inner.continuations[id] = continuation
                if let state = inner.lastEmitted { continuation.yield(state) }
            }
            continuation.onTermination = { [weak self] _ in
                self?.inner.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    func share(_ address: SavedAddress) async throws {
        let myId = try await requireMyId()
        let target = try requireTarget()
        let item = HouseholdAddress(address: address, addedBy: myId)
        let record = try HouseholdRecords.addressRecord(item, zoneID: target.zoneID)
        let added = mutate { inner in
            Self.insertIfMissing(record, scope: target.scope, in: &inner)
        }
        guard added else { return }
        target.engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        emit()
    }

    func unshare(_ key: AddressKey) async throws {
        let target = try requireTarget()
        try remove(recordName: HouseholdRecords.recordName(for: key), target: target)
    }

    /// Finns bocken redan behålls den med sin avsändare och tid. Den första vinner, även på servern.
    func mark(_ placedOut: PlacedOut) async throws {
        let myId = try await requireMyId()
        let target = try requireTarget()
        let mark = HouseholdMark(placedOut: placedOut, by: myId, at: Date(), isPending: true)
        let record = HouseholdRecords.markRecord(mark, zoneID: target.zoneID)
        let added = mutate { inner in
            Self.insertIfMissing(record, scope: target.scope, in: &inner)
        }
        guard added else { return }
        target.engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        emit()
    }

    func unmark(_ placedOut: PlacedOut) async throws {
        let target = try requireTarget()
        try remove(recordName: HouseholdRecords.recordName(for: placedOut), target: target)
    }

    /// En medlem tar bort den delade zonen ur sin delade databas och är då inte längre med. Ägaren tar bort zonen `Hushall`
    /// med delningen, vilket är Avsluta hushållet: medlemmarna får `removed`.
    func leave() async throws {
        let (role, sharedZoneID) = inner.withLock { (Self.role(of: $0), $0.sharedZoneID) }
        switch role {
        case .owner:
            try await deleteZone(HouseholdRecords.privateZoneID, in: container.privateCloudDatabase)
            dropPrivateZone()
        case .member:
            guard let sharedZoneID else { return }
            try await deleteZone(sharedZoneID, in: container.sharedCloudDatabase)
            dropSharedZone(sharedZoneID, status: .synced)
        case .none:
            return
        }
    }

    func removeExpired(today: DayDate) async {
        guard let target = try? requireTarget() else { return }
        let names = inner.withLock { inner in
            let marks = Self.records(in: inner, scope: target.scope).values.compactMap { HouseholdRecords.mark(from: $0, isPending: false) }
            return HouseholdLogic.expired(marks, today: today).map { HouseholdRecords.recordName(for: $0.placedOut) }
        }
        for name in names {
            try? remove(recordName: name, target: target)
        }
    }

    func fetchChanges() async {
        await refreshAccount()
        let (signedIn, privateEngine, sharedEngine, retry, retryShared) = inner.withLock { inner in
            defer {
                inner.retry = []
                inner.retryShared = []
            }
            return (inner.signedIn, inner.privateEngine, inner.sharedEngine, inner.retry, inner.retryShared)
        }
        guard signedIn, let privateEngine, let sharedEngine else {
            emit()
            return
        }
        privateEngine.state.add(pendingRecordZoneChanges: retry)
        sharedEngine.state.add(pendingRecordZoneChanges: retryShared)
        do {
            try await privateEngine.fetchChanges()
            try await sharedEngine.fetchChanges()
            mutate { inner in
                inner.known = true
                if inner.status == .failed { inner.status = .synced }
            }
        } catch {
            record(error, scope: nil)
        }
        emit()
        do {
            try await privateEngine.sendChanges()
            try await sharedEngine.sendChanges()
        } catch {
            record(error, scope: nil)
            emit()
        }
    }

    // MARK: Läget

    /// Ändrar läget och sparar kopian. Skickar inget nytt läge, det gör `emit()` när motorerna har fått sina ändringar.
    @discardableResult
    func mutate<T>(_ change: (inout Inner) -> T) -> T {
        let (result, cache) = inner.withLock { inner in
            (change(&inner), Self.cache(of: inner))
        }
        do {
            try stateStore.setRawData(try PropertyListEncoder().encode(cache), named: HouseholdRecordCache.fileName)
        } catch {
            // Kopian skrivs igen vid nästa ändring.
            logger.error("Kunde inte spara hushållets poster: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    /// Skickar läget till alla som lyssnar, men bara om det har ändrats.
    func emit() {
        let engines = inner.withLock { [$0.privateEngine, $0.sharedEngine] }
        // Motorernas köer läses utanför låset, eftersom motorerna anropar synken.
        var pending: Set<String> = []
        for engine in engines.compactMap({ $0 }) {
            for change in engine.state.pendingRecordZoneChanges {
                if case .saveRecord(let id) = change { pending.insert(id.recordName) }
            }
        }
        inner.withLock { inner in
            guard let state = Self.state(of: inner, pending: pending), state != inner.lastEmitted else { return }
            inner.lastEmitted = state
            for continuation in inner.continuations.values {
                continuation.yield(state)
            }
        }
    }

    static func role(of inner: Inner) -> HouseholdRole {
        if inner.hasPrivateZone, inner.privateRecords[CKRecordNameZoneWideShare] is CKShare { return .owner }
        if inner.sharedZoneID != nil { return .member }
        return .none
    }

    static func state(of inner: Inner, pending: Set<String>) -> HouseholdState? {
        let status = inner.signedIn ? inner.status : .notSignedIn
        let role = role(of: inner)
        guard inner.known, role != .none else {
            // Utan hushåll, eller innan posterna går att lita på. Ett okänt läge skickas bara när något är fel.
            guard inner.known || status != .synced else { return nil }
            return HouseholdState(role: .none, myId: inner.myId, participants: [], addresses: [], marks: [], status: status)
        }
        let records = role == .owner ? inner.privateRecords : inner.sharedRecords
        let share = records[CKRecordNameZoneWideShare] as? CKShare
        let addresses = records.values.compactMap(HouseholdRecords.address(from:)).sorted {
            ($0.address.addedAt, $0.address.key.fileName) < ($1.address.addedAt, $1.address.key.fileName)
        }
        let marks = records.values.compactMap { record in
            HouseholdRecords.mark(from: record, isPending: pending.contains(record.recordID.recordName))
        }.sorted {
            ($0.placedOut.date.iso, $0.placedOut.key.fileName) < ($1.placedOut.date.iso, $1.placedOut.key.fileName)
        }
        return HouseholdState(
            role: role,
            myId: inner.myId,
            participants: share.map { HouseholdRecords.participants(of: $0, myId: inner.myId) } ?? [],
            addresses: addresses,
            marks: marks,
            status: status == .removed ? .synced : status
        )
    }

    // MARK: Hjälpare

    /// Var hushållets poster skrivs: zonen, databasen och motorn.
    struct Target {
        let scope: CKDatabase.Scope
        let zoneID: CKRecordZone.ID
        let engine: CKSyncEngine
    }

    func requireTarget() throws -> Target {
        try inner.withLock { inner in
            switch Self.role(of: inner) {
            case .owner:
                guard let share = inner.privateRecords[CKRecordNameZoneWideShare], let engine = inner.privateEngine else { break }
                return Target(scope: .private, zoneID: share.recordID.zoneID, engine: engine)
            case .member:
                guard let zoneID = inner.sharedZoneID, let engine = inner.sharedEngine else { break }
                return Target(scope: .shared, zoneID: zoneID, engine: engine)
            case .none:
                break
            }
            throw HouseholdSyncError.noHousehold
        }
    }

    private func remove(recordName: String, target: Target) throws {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: target.zoneID)
        mutate { inner in
            if target.scope == .private {
                inner.privateRecords[recordName] = nil
            } else {
                inner.sharedRecords[recordName] = nil
            }
        }
        target.engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        emit()
    }

    static func records(in inner: Inner, scope: CKDatabase.Scope) -> [String: CKRecord] {
        scope == .private ? inner.privateRecords : inner.sharedRecords
    }

    private static func insertIfMissing(_ record: CKRecord, scope: CKDatabase.Scope, in inner: inout Inner) -> Bool {
        let name = record.recordID.recordName
        if scope == .private {
            guard inner.privateRecords[name] == nil else { return false }
            inner.privateRecords[name] = record
        } else {
            guard inner.sharedRecords[name] == nil else { return false }
            inner.sharedRecords[name] = record
        }
        return true
    }

    func requireMyId() async throws -> String {
        if let id = inner.withLock({ $0.myId }) { return id }
        let id = try await container.userRecordID().recordName
        mutate { $0.myId = id }
        return id
    }

    /// Läser kontots läge. `couldNotDetermine` ändrar ingenting.
    func refreshAccount() async {
        guard let status = try? await container.accountStatus() else { return }
        switch status {
        case .available:
            mutate { $0.signedIn = true }
            _ = try? await requireMyId()
        case .noAccount, .restricted, .temporarilyUnavailable:
            mutate { $0.signedIn = false }
        default:
            break
        }
    }

    func deleteZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        do {
            _ = try await database.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone, .unknownItem].contains(error.code) {
            // Zonen är redan borta.
        }
    }

    /// Ägarens zon finns inte längre. Ändringar som väntar för den slängs.
    func dropPrivateZone() {
        let engine = mutate { inner -> CKSyncEngine? in
            inner.hasPrivateZone = false
            inner.privateRecords = [:]
            inner.retry = []
            inner.status = .synced
            return inner.privateEngine
        }
        if let engine {
            let stale = engine.state.pendingRecordZoneChanges.filter { Self.zoneID(of: $0).zoneName == HouseholdRecords.zoneName }
            engine.state.remove(pendingRecordZoneChanges: stale)
        }
        emit()
    }

    /// Den delade zonen finns inte längre: jag lämnade (`synced`) eller togs bort (`removed`).
    func dropSharedZone(_ zoneID: CKRecordZone.ID, status: HouseholdStatus) {
        let engine = mutate { inner -> CKSyncEngine? in
            guard inner.sharedZoneID == zoneID else { return nil }
            inner.sharedZoneID = nil
            inner.sharedRecords = [:]
            inner.retryShared = []
            inner.status = status
            return inner.sharedEngine
        }
        if let engine {
            let stale = engine.state.pendingRecordZoneChanges.filter { Self.zoneID(of: $0) == zoneID }
            engine.state.remove(pendingRecordZoneChanges: stale)
        }
        emit()
    }

    static func zoneID(of change: CKSyncEngine.PendingRecordZoneChange) -> CKRecordZone.ID {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): id.zoneID
        @unknown default: CKRecordZone.ID()
        }
    }

    /// Ett fel från en hämtning eller ett skick som inte gäller en enskild post.
    func record(_ error: any Error, scope: CKDatabase.Scope?) {
        guard let error = error as? CKError else {
            mutate { $0.status = .failed }
            return
        }
        let ownerName = HouseholdRecords.ownerName(of: share)
        guard let status = HouseholdRecords.status(for: error, ownerName: ownerName) else { return }
        logger.error("Hushållet kunde inte synkas: \(error.localizedDescription, privacy: .public)")
        mutate { inner in
            if status == .notSignedIn {
                inner.signedIn = false
            } else {
                inner.status = status
            }
        }
    }
}
