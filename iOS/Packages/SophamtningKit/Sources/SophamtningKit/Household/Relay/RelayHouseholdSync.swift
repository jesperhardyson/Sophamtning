import Foundation
import Synchronization

/// Hushållets synk mot brevlådan på Cloudflare. Innehållet krypteras här och servern kan inte läsa det.
///
/// Synken har en egen kopia (`household-relay.json`) och en kö med ändringar som väntar (`household-relay-pending.json`).
/// Kön skrivs före nätet, så att ett tryck aldrig går förlorat. Allt som rör nätet körs i tur och ordning. Bara serverns svar
/// `removed` och `ended` tar bort hushållet. Allt annat är `failed`, med kopian kvar.
public final class RelayHouseholdSync: HouseholdSync, HouseholdMembership {
    private struct Inner {
        var loaded = false
        var credentials: HouseholdCredentials?
        /// Nycklarna gick inte att läsa, till exempel innan telefonen har låsts upp.
        var credentialsUnreadable = false
        var cache: RelayCache?
        var queue: RelayPendingQueue?
        var status: HouseholdStatus = .synced
        var lastEmitted: HouseholdState?
        var continuations: [UUID: AsyncStream<HouseholdState>.Continuation] = [:]
        var device: Device?
        var deviceSent = false
        var wantsSignals = false
        var signals: (authorization: String, task: Task<Void, Never>)?
    }

    private struct Device {
        var token: String
        var environment: String
    }

    /// Vad ett svar betyder för hushållet.
    private enum Outcome {
        case ok(Data)
        case gone
        case error(status: Int, code: RelayErrorCode?, body: Data)
        case unreachable
    }

    private let transport: any RelayTransport
    private let credentialStore: any HouseholdCredentialStore
    private let store: LocalStore
    private let deviceId: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let inner = Mutex(Inner())
    private let serial = RelaySerial()

    public init(
        transport: any RelayTransport,
        credentials: any HouseholdCredentialStore,
        store: LocalStore,
        deviceId: @escaping @Sendable () -> String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        credentialStore = credentials
        self.store = store
        self.deviceId = deviceId
        self.now = now
        loadIfNeeded()
        emit()
    }

    /// Om telefonen hör till ett hushåll i brevlådan. Sant också när nycklarna inte går att läsa just nu men kopian finns.
    public var hasHousehold: Bool {
        loadIfNeeded()
        return inner.withLock { $0.credentials != nil || ($0.credentialsUnreadable && $0.cache != nil) }
    }

    public var managesMembers: Bool { true }

    var lastState: HouseholdState? { inner.withLock { $0.lastEmitted } }
    var pendingCount: Int { inner.withLock { $0.queue?.items.count ?? 0 } }

    // MARK: HouseholdSync

    public func states() -> AsyncStream<HouseholdState> {
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

    public func share(_ address: SavedAddress) async throws { try await enqueue(.share(address, legacy: nil)) }
    public func unshare(_ key: AddressKey) async throws { try await enqueue(.unshare(key)) }
    public func mark(_ placedOut: PlacedOut) async throws { try await enqueue(.mark(placedOut, at: now(), legacy: nil)) }
    public func unmark(_ placedOut: PlacedOut) async throws { try await enqueue(.unmark(placedOut)) }
    public func setMyName(_ name: String) async throws { try await setMyName(name, legacyId: nil) }

    /// Servern tar själv bort bockar vars hämtdag har passerat, så bara kopian och kön städas här.
    public func removeExpired(today: DayDate) async {
        mutate { inner in
            guard var cache = inner.cache else { return }
            cache.records = cache.records.filter { _, stored in
                if case .mark(let plain) = stored.content { return plain.date >= today }
                return true
            }
            inner.cache = cache
            inner.queue?.items.removeAll { item in
                if case .mark(let placedOut, _, _) = item.change { return placedOut.date < today }
                return false
            }
        }
    }

    public func fetchChanges() async {
        await serial.run { await self.synchronize() }
    }

    /// Medlemmen lämnar. När ägaren lämnar avslutas hushållet för alla.
    public func leave() async throws {
        try await serial.run { try await self.leaveNow() }
    }

    // MARK: HouseholdMembership

    public func create(myName: String) async throws {
        try await create(myName: myName, legacyId: nil)
    }

    /// - Parameter legacyId: mitt id i iCloud, när hushållet flyttas därifrån.
    func create(myName: String, legacyId: String?) async throws {
        try await serial.run {
            try self.requireNoHousehold()
            let created: CreatedWire = try await self.request("POST", "/households")
            let credentials = HouseholdCredentials(
                householdId: created.householdId, householdKey: HouseholdCrypto.newKey(),
                participantId: created.participantId, participantSecret: created.participantSecret
            )
            // Hushållet är nytt och tomt, så kopian är komplett från början.
            var cache = RelayCache(householdId: created.householdId, myId: created.participantId, complete: true)
            cache.participants = [HouseholdParticipant(id: created.participantId, name: HouseholdTexts.unknownName, isOwner: true)]
            try self.adopt(credentials, cache: cache, name: myName, legacyId: legacyId)
            await self.synchronize()
        }
    }

    public func join(_ link: HouseholdInviteLink, myName: String?) async throws {
        try await join(link, myName: myName, legacyId: nil)
    }

    /// - Parameter legacyId: mitt id i iCloud, när hushållet flyttas därifrån.
    func join(_ link: HouseholdInviteLink, myName: String?, legacyId: String?) async throws {
        try await serial.run {
            try self.requireNoHousehold()
            let joined: JoinedWire = try await self.request("POST", "/households/\(link.householdId)/join", body: ["inviteToken": link.inviteToken])
            let credentials = HouseholdCredentials(
                householdId: link.householdId, householdKey: link.householdKey,
                participantId: joined.participantId, participantSecret: joined.participantSecret
            )
            try self.adopt(credentials, cache: RelayCache(householdId: link.householdId, myId: joined.participantId), name: myName, legacyId: legacyId)
            await self.synchronize()
        }
    }

    public func invite() async throws -> URL { try await inviteLink(purpose: "invite").url }

    func inviteLink(purpose: String) async throws -> HouseholdInviteLink {
        try await serial.run {
            let credentials = try self.requireCredentials()
            let invite: InviteWire = try await self.request("POST", "/households/\(credentials.householdId)/invites", body: ["purpose": purpose], as: credentials)
            return HouseholdInviteLink(householdId: credentials.householdId, inviteToken: invite.inviteToken, householdKey: credentials.householdKey)
        }
    }

    public func revokeInvites() async throws {
        try await serial.run {
            let credentials = try self.requireCredentials()
            try await self.perform("DELETE", "/households/\(credentials.householdId)/invites", as: credentials)
        }
    }

    public func remove(participantId: String) async throws {
        try await serial.run {
            let credentials = try self.requireCredentials()
            try await self.perform("DELETE", "/households/\(credentials.householdId)/participants/\(participantId)", as: credentials)
            await self.synchronize()
        }
    }

    public func end() async throws {
        try await serial.run { try await self.endNow() }
    }

    public func registerDevice(token: String, environment: String) async {
        inner.withLock { inner in
            inner.device = Device(token: token, environment: environment)
            inner.deviceSent = false
        }
        await serial.run {
            guard let credentials = self.credentials() else { return }
            await self.sendDevice(credentials)
        }
    }

    public func isCurrent(_ link: HouseholdInviteLink) -> Bool {
        loadIfNeeded()
        return inner.withLock { $0.credentials?.householdId ?? $0.cache?.householdId } == link.householdId
    }

    // MARK: Flytten från iCloud

    /// Laddar upp en adress som någon annan kan ha delat, med den ursprungliga avsändaren.
    func upload(address: SavedAddress, legacyBy: String, at: Date) async throws {
        try await enqueue(.share(address, legacy: LegacyOrigin(by: legacyBy, at: at)), mustSend: true)
    }

    func upload(mark: PlacedOut, legacyBy: String, at: Date) async throws {
        try await enqueue(.mark(mark, at: at, legacy: LegacyOrigin(by: legacyBy, at: at)), mustSend: true)
    }

    func setMyName(_ name: String, legacyId: String?) async throws {
        try await enqueue(.name(name, legacyId: legacyId), mustSend: legacyId != nil)
    }

    // MARK: Signaler

    /// Lyssnar på ändringar medan appen är öppen. Utan hushåll börjar den lyssna när det finns ett.
    public func startSignals() {
        inner.withLock { $0.wantsSignals = true }
        updateSignals()
    }

    public func stopSignals() {
        inner.withLock { $0.wantsSignals = false }
        updateSignals()
    }

    private func updateSignals() {
        inner.withLock { inner in
            let wanted = inner.wantsSignals ? inner.credentials : nil
            if inner.signals?.authorization == wanted?.authorization { return }
            inner.signals?.task.cancel()
            inner.signals = nil
            guard let wanted else { return }
            let stream = transport.signals(householdId: wanted.householdId, authorization: wanted.authorization)
            inner.signals = (wanted.authorization, Task { [weak self] in
                for await seq in stream {
                    guard let self, !Task.isCancelled else { return }
                    if self.inner.withLock({ $0.cache?.seq }) != seq { await self.fetchChanges() }
                }
            })
        }
    }

    // MARK: Hämta och skicka (körs i tur och ordning)

    private func synchronize() async {
        loadIfNeeded()
        guard let credentials = credentials() else {
            if inner.withLock({ $0.credentialsUnreadable }) { setStatus(.failed) }
            emit()
            return
        }
        if await send(credentials), await fetch(credentials) {
            setStatus(.synced)
            await sendDevice(credentials)
        }
        emit()
        updateSignals()
    }

    /// Skickar kön i ordning. Svarar falskt när det inte gick, och resten väntar då till nästa gång.
    private func send(_ credentials: HouseholdCredentials) async -> Bool {
        let crypto = HouseholdCrypto(householdId: credentials.householdId, householdKey: credentials.householdKey)
        while let item = inner.withLock({ $0.queue?.items.first }) {
            guard let request = request(for: item.change, credentials: credentials, crypto: crypto) else {
                finish(item)
                continue
            }
            switch await outcome(request) {
            case .ok(let body):
                let wire = try? JSONDecoder().decode(RecordWire.self, from: body)
                finish(item) { cache in
                    if let wire {
                        cache.store(wire, crypto: crypto)
                    } else if let logical = item.change.logicalName {
                        cache.records[crypto.recordName(logical)] = nil
                    } else if case .name(let name, let legacyId) = item.change {
                        cache.myName = name
                        if let index = cache.participants.firstIndex(where: { $0.id == credentials.participantId }) {
                            cache.participants[index].name = name
                            if let legacyId { cache.participants[index].legacyIds = [legacyId] }
                        }
                    }
                }
            case .error(_, .conflict, let body):
                // Någon annan var först, och den posten gäller.
                let existing = (try? JSONDecoder().decode(ErrorWire.self, from: body))?.record
                finish(item) { cache in
                    if let existing { cache.store(existing, crypto: crypto) }
                }
            case .error(let status, _, _) where [400, 413, 428].contains(status):
                // Servern kommer aldrig att ta emot den, och den får inte stoppa resten.
                finish(item)
            case .gone:
                adoptGone()
                return false
            case .error, .unreachable:
                setStatus(.failed)
                return false
            }
            emit()
        }
        return true
    }

    private func fetch(_ credentials: HouseholdCredentials) async -> Bool {
        let since = inner.withLock { $0.cache?.complete == true ? $0.cache?.seq ?? 0 : 0 }
        let request = RelayRequest(method: "GET", path: "/households/\(credentials.householdId)/changes?since=\(since)", headers: ["Authorization": credentials.authorization])
        switch await outcome(request) {
        case .ok(let body):
            guard let changes = try? JSONDecoder().decode(ChangesWire.self, from: body) else { break }
            let crypto = HouseholdCrypto(householdId: credentials.householdId, householdKey: credentials.householdKey)
            mutate { $0.cache?.apply(changes, crypto: crypto) }
            return true
        case .gone:
            adoptGone()
            return false
        case .error, .unreachable:
            break
        }
        setStatus(.failed)
        return false
    }

    private func sendDevice(_ credentials: HouseholdCredentials) async {
        guard let device = inner.withLock({ $0.deviceSent ? nil : $0.device }) else { return }
        let body = ["platform": "apns", "token": device.token, "environment": device.environment]
        let path = "/households/\(credentials.householdId)/participants/me/devices/\(deviceId())"
        guard case .ok = await outcome(RelayRequest(method: "PUT", path: path, headers: Self.headers(credentials), body: Self.json(body))) else { return }
        inner.withLock { inner in
            if inner.device?.token == device.token, inner.credentials == credentials { inner.deviceSent = true }
        }
    }

    private func leaveNow() async throws {
        loadIfNeeded()
        guard let credentials = credentials() else {
            if inner.withLock({ $0.credentialsUnreadable }) { throw HouseholdMembershipError.failed }
            return
        }
        // Utan kopia vet appen inte om jag är ägare, och ett hushåll får aldrig avslutas av misstag.
        if inner.withLock({ $0.cache?.complete != true }) {
            await synchronize()
            guard inner.withLock({ $0.cache?.complete == true }) else {
                if self.credentials() == nil { return }
                throw HouseholdMembershipError.failed
            }
        }
        if inner.withLock({ $0.cache?.role == .owner }) {
            try await endNow()
        } else {
            let path = "/households/\(credentials.householdId)/participants/\(credentials.participantId)"
            try await depart(RelayRequest(method: "DELETE", path: path, headers: Self.headers(credentials)))
        }
    }

    private func endNow() async throws {
        let credentials = try requireCredentials()
        try await depart(RelayRequest(method: "DELETE", path: "/households/\(credentials.householdId)", headers: Self.headers(credentials)))
    }

    /// Lämnar eller avslutar. Är jag redan borttagen är det också klart.
    private func depart(_ request: RelayRequest) async throws {
        switch await outcome(request) {
        case .ok, .gone:
            try clear(status: .synced)
        case .error, .unreachable:
            throw HouseholdMembershipError.failed
        }
    }

    // MARK: Anrop

    private func request(for change: RelayPendingChange, credentials: HouseholdCredentials, crypto: HouseholdCrypto) -> RelayRequest? {
        let base = "/households/\(credentials.householdId)"
        func record(_ plaintext: some Encodable, kind: RelayRecordKind, expiresAt: Date?) -> RelayRequest? {
            guard let logical = change.logicalName, let plain = try? JSONEncoder().encode(plaintext) else { return nil }
            let name = crypto.recordName(logical)
            guard let data = try? crypto.seal(plain, name: name, kind: kind) else { return nil }
            var body = ["kind": kind.rawValue, "data": data]
            if let expiresAt { body["expiresAt"] = RelayDate.format(expiresAt) }
            var headers = Self.headers(credentials)
            headers["If-None-Match"] = "*"
            return RelayRequest(method: "PUT", path: "\(base)/records/\(name)", headers: headers, body: Self.json(body))
        }
        func removal(_ logical: String) -> RelayRequest {
            RelayRequest(method: "DELETE", path: "\(base)/records/\(crypto.recordName(logical))", headers: Self.headers(credentials))
        }
        switch change {
        case .share(let address, let legacy):
            return record(AddressPlaintext(address: address, legacy: legacy), kind: .address, expiresAt: nil)
        case .unshare(let key):
            return removal(key.relayLogicalName)
        case .mark(let placedOut, _, let legacy):
            let plain = MarkPlaintext(source: placedOut.key.source, id: placedOut.key.id, date: placedOut.date, legacy: legacy)
            // Bocken gäller hela hämtdagen i Sverige.
            return record(plain, kind: .mark, expiresAt: StockholmClock.date(on: placedOut.date.adding(days: 1), minutes: 0))
        case .unmark(let placedOut):
            return removal(placedOut.relayLogicalName)
        case .name(let name, let legacyId):
            let known = inner.withLock { $0.cache?.participants.first { $0.id == credentials.participantId }?.legacyIds } ?? []
            let legacyIds = legacyId.map { [$0] } ?? known
            let plain = NamePlaintext(name: name, legacyIds: legacyIds.isEmpty ? nil : legacyIds)
            guard let encoded = try? JSONEncoder().encode(plain), let data = try? crypto.sealName(encoded, participantId: credentials.participantId) else { return nil }
            return RelayRequest(method: "PUT", path: "\(base)/participants/me/name", headers: Self.headers(credentials), body: Self.json(["data": data]))
        }
    }

    private func outcome(_ request: RelayRequest) async -> Outcome {
        guard let response = try? await transport.send(request) else { return .unreachable }
        if (200..<300).contains(response.status) { return .ok(response.body) }
        let code = (try? JSONDecoder().decode(ErrorWire.self, from: response.body)).flatMap { RelayErrorCode(rawValue: $0.error) }
        // Koden måste höra ihop med sin status, så att ett svar från något annat än brevlådan aldrig tar bort hushållet.
        switch (response.status, code) {
        case (403, .removed), (410, .ended): return .gone
        default: return .error(status: response.status, code: code, body: response.body)
        }
    }

    /// Ett anrop utanför kön, vars svar eller fel går tillbaka till den som bad om det.
    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil, as credentials: HouseholdCredentials? = nil) async throws -> T {
        let data = try await perform(method, path, body: body, as: credentials)
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw HouseholdMembershipError.failed }
        return value
    }

    @discardableResult
    private func perform(_ method: String, _ path: String, body: [String: String]? = nil, as credentials: HouseholdCredentials? = nil) async throws -> Data {
        let headers = credentials.map(Self.headers) ?? ["Content-Type": "application/json"]
        switch await outcome(RelayRequest(method: method, path: path, headers: headers, body: body.map(Self.json))) {
        case .ok(let data):
            return data
        case .gone:
            if credentials != nil { adoptGone() }
            throw HouseholdMembershipError.failed
        case .error(404, .inviteInvalid, _):
            throw HouseholdMembershipError.inviteInvalid
        case .error(409, .full, _):
            throw HouseholdMembershipError.full
        case .error(409, .migrationUnavailable, _):
            throw HouseholdMembershipError.migrationUnavailable
        case .error, .unreachable:
            throw HouseholdMembershipError.failed
        }
    }

    private static func headers(_ credentials: HouseholdCredentials) -> [String: String] {
        ["Authorization": credentials.authorization, "Content-Type": "application/json"]
    }

    private static func json(_ body: [String: String]) -> Data {
        // En ordbok med text går alltid att koda.
        (try? JSONEncoder().encode(body)) ?? Data()
    }

    // MARK: Kön

    /// Ändringen skrivs i kön och visas direkt. Sedan skickas den, om det går.
    /// - Parameter mustSend: kasta om den inte kom fram. Annars räcker det att den väntar.
    private func enqueue(_ change: RelayPendingChange, mustSend: Bool = false) async throws {
        loadIfNeeded()
        let saved = try inner.withLock { inner -> Bool in
            guard inner.loaded, let householdId = inner.credentials?.householdId ?? inner.cache?.householdId else { throw HouseholdMembershipError.noHousehold }
            var queue = inner.queue ?? RelayPendingQueue(householdId: householdId)
            queue.append(change)
            do {
                try store.setRawData(JSONEncoder().encode(queue), named: RelayPendingQueue.fileName)
            } catch {
                return false
            }
            inner.queue = queue
            return true
        }
        guard saved else { throw HouseholdMembershipError.failed }
        emit()
        let sent = await serial.run { () -> Bool in
            guard let credentials = self.credentials() else { return false }
            let sent = await self.send(credentials)
            self.emit()
            return sent
        }
        if mustSend, !sent { throw HouseholdMembershipError.failed }
    }

    /// Ändringen har kommit fram eller nekats för gott.
    private func finish(_ item: RelayPendingQueue.Item, update: (inout RelayCache) -> Void = { _ in }) {
        mutate { inner in
            inner.queue?.items.removeAll { $0.id == item.id }
            if inner.cache != nil { update(&inner.cache!) }
        }
    }

    // MARK: Hushållet byts

    private func requireNoHousehold() throws {
        loadIfNeeded()
        // Går nycklarna inte att läsa vet appen inte om jag redan är med.
        if inner.withLock({ $0.credentialsUnreadable }) { throw HouseholdMembershipError.failed }
        if credentials() != nil { throw HouseholdMembershipError.alreadyMember }
    }

    private func requireCredentials() throws -> HouseholdCredentials {
        loadIfNeeded()
        guard let credentials = credentials() else {
            throw inner.withLock { $0.credentialsUnreadable } ? HouseholdMembershipError.failed : .noHousehold
        }
        return credentials
    }

    private func adopt(_ credentials: HouseholdCredentials, cache: RelayCache, name: String?, legacyId: String? = nil) throws {
        do {
            try credentialStore.save(credentials)
        } catch {
            throw HouseholdMembershipError.failed
        }
        mutate { inner in
            inner.credentials = credentials
            inner.credentialsUnreadable = false
            inner.cache = cache
            inner.queue = RelayPendingQueue(householdId: credentials.householdId)
            if let name { inner.queue?.append(.name(name, legacyId: legacyId)) }
            inner.status = .synced
            inner.deviceSent = false
        }
        emit()
        updateSignals()
    }

    /// Servern har sagt att jag inte längre är med, eller att hushållet är avslutat.
    private func adoptGone() {
        try? clear(status: .removed)
    }

    private func clear(status: HouseholdStatus) throws {
        try credentialStore.delete()
        mutate { inner in
            inner.credentials = nil
            inner.cache = nil
            inner.queue = nil
            inner.status = status
            inner.deviceSent = false
        }
        emit()
        updateSignals()
    }

    // MARK: Lagring och läge

    private func credentials() -> HouseholdCredentials? {
        inner.withLock { $0.credentials }
    }

    /// Läser nycklarna, kopian och kön. Det som inte går att läsa nu, till exempel innan telefonen har låsts upp, läses igen
    /// vid nästa tillfälle. Nycklarna läses varje gång, eftersom en annan av mina enheter kan ha bytt hushåll.
    private func loadIfNeeded() {
        let stored = Result { try credentialStore.load() }
        let cache = inner.withLock { $0.loaded } ? nil : store.rawData(named: RelayCache.fileName)
        let queue = inner.withLock { $0.loaded } ? nil : store.rawData(named: RelayPendingQueue.fileName)
        var switched = false
        inner.withLock { inner in
            if !inner.loaded, let cache, let queue {
                if case .value(let data) = cache { inner.cache = try? JSONDecoder().decode(RelayCache.self, from: data) }
                if case .value(let data) = queue { inner.queue = try? JSONDecoder().decode(RelayPendingQueue.self, from: data) }
                if case .unavailable = cache {} else if case .unavailable = queue {} else { inner.loaded = true }
            }
            switch stored {
            case .failure:
                inner.credentialsUnreadable = true
                inner.credentials = nil
            case .success(let credentials):
                inner.credentialsUnreadable = false
                inner.credentials = credentials
                // En kopia från ett annat hushåll gäller inte.
                if let cache = inner.cache, cache.householdId != credentials?.householdId || cache.myId != credentials?.participantId {
                    inner.cache = nil
                    switched = true
                }
                if let queue = inner.queue, queue.householdId != credentials?.householdId { inner.queue = nil }
                if inner.cache == nil, let credentials { inner.cache = RelayCache(householdId: credentials.householdId, myId: credentials.participantId) }
                if let credentials {
                    inner.cache?.rereadUnreadable(crypto: HouseholdCrypto(householdId: credentials.householdId, householdKey: credentials.householdKey))
                }
            }
        }
        // Det förra hushållet är lämnat på en annan enhet. Adresserna därifrån blir kvar som egna.
        if switched { yield(.empty) }
    }

    private func setStatus(_ status: HouseholdStatus) {
        inner.withLock { $0.status = status }
    }

    /// Ändrar kopian eller kön och sparar dem medan låset hålls, så att en äldre bild aldrig skriver över en nyare.
    private func mutate(_ change: (inout Inner) -> Void) {
        inner.withLock { inner in
            let before = (inner.cache, inner.queue)
            change(&inner)
            // Ett skrivfel rättas vid nästa ändring. Kopian går alltid att hämta igen.
            if before.0 != inner.cache { save(inner.cache, named: RelayCache.fileName) }
            if before.1 != inner.queue { save(inner.queue, named: RelayPendingQueue.fileName) }
        }
        emit()
    }

    private func save(_ value: (some Encodable)?, named name: String) {
        if let value {
            if let data = try? JSONEncoder().encode(value) { try? store.setRawData(data, named: name) }
        } else {
            try? store.removeRawData(named: name)
        }
    }

    private func emit() {
        let state = inner.withLock { inner -> HouseholdState? in
            let pending = inner.queue?.items.map(\.change) ?? []
            let status: HouseholdStatus = inner.credentialsUnreadable ? .failed : inner.status
            guard inner.credentials != nil || inner.credentialsUnreadable else {
                return HouseholdState(role: .none, myId: nil, participants: [], addresses: [], marks: [], status: status)
            }
            guard let cache = inner.cache, cache.complete else {
                // Utan en komplett kopia skickas bara lägen med fel, och de utan innehåll.
                guard status != .synced else { return nil }
                return HouseholdState(role: .none, myId: inner.cache?.myId, participants: [], addresses: [], marks: [], status: status)
            }
            return cache.state(pending: pending, status: status)
        }
        if let state { yield(state) }
    }

    /// Skickar läget till alla som lyssnar, men bara om det har ändrats.
    private func yield(_ state: HouseholdState) {
        inner.withLock { inner in
            guard state != inner.lastEmitted else { return }
            inner.lastEmitted = state
            for continuation in inner.continuations.values { continuation.yield(state) }
        }
    }
}

/// Kör arbeten i tur och ordning. Ett arbete fortsätter även om den som bad om det slutar vänta.
actor RelaySerial {
    private var last: Task<Void, Never>?

    func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = last
        let task = Task { () async throws -> T in
            await previous?.value
            return try await work()
        }
        last = Task { _ = try? await task.value }
        return try await task.value
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let previous = last
        let task = Task { () async -> T in
            await previous?.value
            return await work()
        }
        last = Task { _ = await task.value }
        return await task.value
    }
}
