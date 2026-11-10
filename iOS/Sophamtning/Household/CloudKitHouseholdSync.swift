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
        /// Om posterna går att lita på. Sparas med kopian. Innan en fullständig hämtning har lyckats skickas bara lägen med
        /// fel, så att appen aldrig tror att hushållet är tomt eller saknar adresser.
        var trust = HouseholdSyncTrust()
        var hasPrivateZone = false
        var sharedZoneID: CKRecordZone.ID?
        var privateRecords: [String: CKRecord] = [:]
        var sharedRecords: [String: CKRecord] = [:]
        /// Ändringar som motorn inte försöker igen med själv, till exempel efter `quotaExceeded`. De köas vid nästa hämtning.
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var retryShared: [CKSyncEngine.PendingRecordZoneChange] = []
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
        var privateState = loaded ? Self.engineState(named: Self.privateEngineFile, in: stateStore) : nil
        var sharedState = loaded ? Self.engineState(named: Self.sharedEngineFile, in: stateStore) : nil
        if privateState == nil || sharedState == nil {
            // Motorerna börjar om från början och hämtar allt igen. Kopian töms och gäller inte förrän den hämtningen
            // har lyckats, så att den aldrig blandar poster från före och efter omstarten.
            privateState = nil
            sharedState = nil
            Self.clearHousehold(&initial)
            initial.trust.restarted()
            try? stateStore.removeRawData(named: Self.privateEngineFile)
            try? stateStore.removeRawData(named: Self.sharedEngineFile)
            try? Self.cache(of: initial).save(to: stateStore)
        }
        inner = Mutex(initial)
        let privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: privateState,
            delegate: self
        ))
        let sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: sharedState,
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

    /// Mitt namn skrivs i en egen post. Bara jag skriver den, så en ändring ersätter det förra namnet.
    func setMyName(_ name: String) async throws {
        let myId = try await requireMyId()
        let target = try requireTarget()
        let recordName = HouseholdRecords.recordName(forParticipant: myId)
        let record = mutate { inner -> CKRecord in
            let existing = Self.records(in: inner, scope: target.scope)[recordName]
            let record = HouseholdRecords.participantRecord(id: myId, name: name, existing: existing, zoneID: target.zoneID)
            if target.scope == .private { inner.privateRecords[recordName] = record } else { inner.sharedRecords[recordName] = record }
            return record
        }
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
        let engines = inner.withLock { inner -> (CKSyncEngine, CKSyncEngine, [CKSyncEngine.PendingRecordZoneChange], [CKSyncEngine.PendingRecordZoneChange])? in
            // Utloggad ligger omförsöken kvar till nästa hämtning.
            guard inner.signedIn, let privateEngine = inner.privateEngine, let sharedEngine = inner.sharedEngine else { return nil }
            defer {
                inner.retry = []
                inner.retryShared = []
            }
            return (privateEngine, sharedEngine, inner.retry, inner.retryShared)
        }
        guard let (privateEngine, sharedEngine, retry, retryShared) = engines else {
            emit()
            return
        }
        privateEngine.state.add(pendingRecordZoneChanges: retry)
        sharedEngine.state.add(pendingRecordZoneChanges: retryShared)
        do {
            try await privateEngine.fetchChanges()
            try await sharedEngine.fetchChanges()
            await refreshShare()
            mutate { inner in
                // Bara en hämtning av båda databaserna gör kopian komplett.
                inner.trust.fetchCompleted()
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
    ///
    /// Kopian skrivs medan låset hålls, så att skrivningarna alltid kommer i samma ordning som ändringarna och en äldre
    /// bild aldrig skriver över en nyare. Den är skriven innan funktionen svarar, alltså innan motorn får spara ett
    /// tillstånd som räknar med ändringen.
    @discardableResult
    func mutate<T>(_ change: (inout Inner) -> T) -> T {
        let (result, failure) = inner.withLock { inner -> (T, (any Error)?) in
            let result = change(&inner)
            do {
                try Self.cache(of: inner).save(to: stateStore)
                return (result, nil)
            } catch {
                return (result, error)
            }
        }
        if let failure {
            // Kopian skrivs igen vid nästa ändring.
            logger.error("Kunde inte spara hushållets poster: \(failure.localizedDescription, privacy: .public)")
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
        inner.trust.gate(fullState(of: inner, pending: pending))
    }

    /// Läget enligt kopian, innan det prövas mot om kopian går att lita på.
    private static func fullState(of inner: Inner, pending: Set<String>) -> HouseholdState {
        let status = inner.signedIn ? inner.status : .notSignedIn
        let role = role(of: inner)
        guard role != .none else {
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
        // Namnen som deltagarna själva har skrivit går före namnen från iCloud, som oftast saknas för andra än mig.
        let names = Dictionary(records.values.compactMap(HouseholdRecords.participantName(from:)), uniquingKeysWith: { first, _ in first })
        let participants = (share.map { HouseholdRecords.participants(of: $0, myId: inner.myId) } ?? []).map { participant in
            var named = participant
            if let name = names[participant.id] { named.name = name }
            return named
        }
        return HouseholdState(
            role: role,
            myId: inner.myId,
            participants: participants,
            addresses: addresses,
            marks: marks,
            status: status == .removed ? .synced : status,
            myName: inner.myId.flatMap { names[$0] },
            suggestedName: share.flatMap(HouseholdRecords.suggestedName(in:))
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
        // Ett avbrott är inget fel. Det förra läget gäller.
        if error is CancellationError { return }
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
