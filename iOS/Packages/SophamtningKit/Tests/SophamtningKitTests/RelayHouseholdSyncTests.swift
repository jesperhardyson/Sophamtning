import Foundation
import Synchronization
import Testing
@testable import SophamtningKit

private let day = DayDate("2026-11-27")!
private let key = AddressKey(source: "avesta-vatten", id: "Övre Ågatan 3|12")
private let entry = PlacedOut(key: key, date: day)

private func saved(_ key: AddressKey = key, name: String = "Hemma") -> SavedAddress {
    SavedAddress(
        key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adresser/avesta-vatten/%C3%96vre%20%C3%85gatan%203%7C12")!,
        street: "Övre Ågatan 3", locality: "Avesta", kommun: "Avesta", detail: nil, selection: "address",
        displayName: name, isPrimary: true, notificationsOn: true, addedAt: Date(timeIntervalSinceReferenceDate: 785_000_000)
    )
}

/// En telefon: synken med sin egen lagring och sina nycklar.
final class RelayPhone: Sendable {
    let sync: RelayHouseholdSync
    let credentials: InMemoryCredentialStore
    let directory: URL
    private let server: FakeRelayServer

    init(_ server: FakeRelayServer, credentials: InMemoryCredentialStore = InMemoryCredentialStore(), directory: URL? = nil, deviceId: String = "enhet", now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_795_000_000) }) {
        self.server = server
        self.credentials = credentials
        self.directory = directory ?? FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        sync = RelayHouseholdSync(transport: server, credentials: credentials, store: LocalStore(directory: self.directory), deviceId: { deviceId }, now: now)
    }

    /// Samma telefon efter en omstart av appen.
    func restarted() -> RelayPhone {
        RelayPhone(server, credentials: credentials, directory: directory)
    }

    func keys() throws -> HouseholdCredentials { try #require(try credentials.load()) }

    /// Läget som synken skickade senast, eller `nil` när den inte har skickat något.
    func state() async -> HouseholdState? {
        sync.lastState
    }
}

private func owner(_ server: FakeRelayServer, name: String = "Jesper") async throws -> RelayPhone {
    let phone = RelayPhone(server)
    try await phone.sync.create(myName: name)
    return phone
}

private func member(_ server: FakeRelayServer, of owner: RelayPhone, name: String? = "Sofie") async throws -> RelayPhone {
    let phone = RelayPhone(server, deviceId: "enhet-\(name ?? "")")
    let link = try #require(HouseholdInviteLink(url: try await owner.sync.invite()))
    try await phone.sync.join(link, myName: name)
    await owner.sync.fetchChanges()
    return phone
}

// MARK: Skapa och gå med

@Test func skapaOchBjudIn() async throws {
    let server = FakeRelayServer()
    let phone = try await owner(server)
    let url = try await phone.sync.invite()
    #expect(HouseholdInviteLink(url: url)?.householdKey == (try phone.credentials.load())?.householdKey)
    let state = try #require(await phone.state())
    #expect(state.role == .owner)
    #expect(state.status == .synced)
    #expect(state.participants.map(\.name) == ["Jesper"])
    #expect(state.myName == "Jesper")
    #expect(state.myId == state.participants[0].id)
    #expect(phone.sync.hasHousehold)
}

@Test func gaMedSerAgarensAdresser() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    let state = try #require(await sofie.state())
    #expect(state.role == .member)
    #expect(state.addresses.map(\.address) == [saved()])
    #expect(state.addresses[0].address.url.absoluteString == "https://sopor.hardyson.se/api/v1/adresser/avesta-vatten/%C3%96vre%20%C3%85gatan%203%7C12")
    #expect(state.participants.map(\.name) == ["Jesper", "Sofie"])
    #expect(state.addresses[0].addedBy == state.participants[0].id)
    #expect(await jesper.state()?.participants.map(\.name) == ["Jesper", "Sofie"])
}

@Test func utanNamnVisasNagon() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let other = try await member(server, of: jesper, name: nil)
    #expect(await jesper.state()?.participants.map(\.name) == ["Jesper", "Någon"])
    #expect(await other.state()?.myName == nil)
}

@Test func ogiltigInbjudanOchFulltHushall() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let link = try #require(HouseholdInviteLink(url: try await jesper.sync.invite()))
    try await jesper.sync.revokeInvites()
    let sofie = RelayPhone(server)
    await #expect(throws: HouseholdMembershipError.inviteInvalid) { try await sofie.sync.join(link, myName: "Sofie") }
    #expect(!sofie.sync.hasHousehold)

    for _ in 0..<9 { _ = try await member(server, of: jesper, name: "x") }
    let fresh = try #require(HouseholdInviteLink(url: try await jesper.sync.invite()))
    await #expect(throws: HouseholdMembershipError.full) { try await sofie.sync.join(fresh, myName: "Sofie") }
    server.mode = .offline
    await #expect(throws: HouseholdMembershipError.failed) { try await sofie.sync.join(fresh, myName: "Sofie") }
    #expect(try sofie.credentials.load() == nil)
}

@Test func denSomArMedMasteLamnaForst() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let other = try await owner(server, name: "Kim")
    let link = try #require(HouseholdInviteLink(url: try await other.sync.invite()))
    await #expect(throws: HouseholdMembershipError.alreadyMember) { try await jesper.sync.join(link, myName: nil) }
    await #expect(throws: HouseholdMembershipError.alreadyMember) { try await jesper.sync.create(myName: "x") }
    #expect(!jesper.sync.isCurrent(link))
    #expect(other.sync.isCurrent(link))
}

@Test func nycklarSomInteGarAttSparaGerFel() async throws {
    let server = FakeRelayServer()
    let phone = RelayPhone(server)
    phone.credentials.failing = true
    await #expect(throws: HouseholdMembershipError.failed) { try await phone.sync.create(myName: "Jesper") }
}

// MARK: Fel

@Test func serverFelBehallerHushallet() async throws {
    for mode in [FakeRelayServer.Mode.status(500), .status(503), .status(404), .status(401), .offline] {
        let server = FakeRelayServer()
        let jesper = try await owner(server)
        try await jesper.sync.share(saved())
        try await jesper.sync.mark(entry)
        let before = try #require(await jesper.state())
        server.mode = mode
        await jesper.sync.fetchChanges()
        let after = try #require(await jesper.state())
        #expect(after.status == .failed, "\(mode)")
        #expect(after.addresses == before.addresses)
        #expect(after.marks == before.marks)
        #expect(after.role == .owner)
        #expect(try jesper.credentials.load() != nil)

        server.mode = .normal
        await jesper.sync.fetchChanges()
        #expect(await jesper.state()?.status == .synced)
    }
}

@Test func forstaHamtningenSkickarBaraFel() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    // En ny iPhone med nycklarna men utan kopia.
    let fresh = RelayPhone(server, credentials: jesper.credentials)
    #expect(await fresh.state() == nil)
    server.mode = .status(500)
    await fresh.sync.fetchChanges()
    let state = try #require(await fresh.state())
    #expect(state.status == .failed)
    #expect(state.role == .none)
    #expect(state.addresses.isEmpty)
    server.mode = .normal
    await fresh.sync.fetchChanges()
    #expect(await fresh.state()?.addresses.count == 1)
}

@Test func bara401GerFailedInteRemoved() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.change { inner in
        for id in inner.households.keys { inner.households[id]!.participants[0].secret = "annan" }
    }
    await jesper.sync.fetchChanges()
    let state = try #require(await jesper.state())
    #expect(state.status == .failed)
    #expect(state.addresses.count == 1)
}

@Test func notFoundGerFailed() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.change { $0.households = [:] }
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.status == .failed)
    #expect(await jesper.state()?.addresses.count == 1)
    #expect(try jesper.credentials.load() != nil)
}

@Test func removedOchEndedGerRemoved() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    let kim = try await member(server, of: jesper, name: "Kim")
    try await jesper.sync.remove(participantId: try sofie.keys().participantId)
    #expect(await jesper.state()?.participants.map(\.name) == ["Jesper", "Kim"])
    await sofie.sync.fetchChanges()
    try await jesper.sync.end()
    await kim.sync.fetchChanges()
    for phone in [sofie, kim] {
        #expect(await phone.state()?.status == .removed)
        #expect(await phone.state()?.role == HouseholdRole.none)
        #expect(try phone.credentials.load() == nil)
        #expect(!phone.sync.hasHousehold)
    }
    #expect(await jesper.state() == .empty)
}

@Test func borttagenSyntsOcksaNarNagotSkickas() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.remove(participantId: try sofie.keys().participantId)
    try await sofie.sync.mark(entry)
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.status == .removed)
}

@Test func olasbaraNycklarGerFailed() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    jesper.credentials.failing = true
    let restarted = jesper.restarted()
    await restarted.sync.fetchChanges()
    let state = try #require(await restarted.state())
    #expect(state.status == .failed)
    #expect(state.addresses.count == 1)
    #expect(restarted.sync.hasHousehold)
    jesper.credentials.failing = false
    await restarted.sync.fetchChanges()
    #expect(await restarted.state()?.status == .synced)
}

@Test func utanNycklarFinnsIngetHushall() async throws {
    let phone = RelayPhone(FakeRelayServer())
    #expect(await phone.state() == .empty)
    await phone.sync.fetchChanges()
    #expect(await phone.state() == .empty)
    #expect(!phone.sync.hasHousehold)
    await #expect(throws: (any Error).self) { try await phone.sync.mark(entry) }
}

// MARK: Bockar

@Test func sammaBockFranTvaTelefonerForstaVinner() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    server.mode = .offline
    try await jesper.sync.mark(entry)
    try await sofie.sync.mark(entry)
    #expect(await jesper.state()?.marks.map(\.isPending) == [true])
    #expect(await sofie.state()?.marks.map(\.isPending) == [true])
    server.mode = .normal
    await sofie.sync.fetchChanges()
    await jesper.sync.fetchChanges()
    let sofieId = try sofie.keys().participantId
    for phone in [jesper, sofie] {
        let marks = try #require(await phone.state()).marks
        #expect(marks.map(\.by) == [sofieId])
        #expect(marks.map(\.isPending) == [false])
        #expect(marks.map(\.at) == [server.inner.withLock(\.now)])
        #expect(phone.sync.pendingCount == 0)
    }
}

@Test func bockUtanNatArPending() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.mode = .offline
    try await jesper.sync.mark(entry)
    // Kön finns kvar när appen startas om.
    let restarted = jesper.restarted()
    #expect(await restarted.state()?.marks.map(\.isPending) == [true])
    server.mode = .normal
    await restarted.sync.fetchChanges()
    #expect(await restarted.state()?.marks.map(\.isPending) == [false])
    let sofie = try await member(server, of: restarted)
    #expect(await sofie.state()?.marks.map(\.placedOut) == [entry])
}

@Test func markSparasIKonForeNatet() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.mode = .status(500)
    try await jesper.sync.mark(entry)
    #expect(jesper.restarted().sync.pendingCount == 1)
}

@Test func angraTarBortBocken() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.mark(entry)
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.marks.count == 1)
    try await sofie.sync.unmark(entry)
    #expect(await sofie.state()?.marks.isEmpty == true)
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.marks.isEmpty == true)
}

@Test func bockOchAngraUtanNatTarUtVarandra() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    server.mode = .offline
    try await jesper.sync.mark(entry)
    try await jesper.sync.unmark(entry)
    #expect(await jesper.state()?.marks.isEmpty == true)
    try await jesper.sync.mark(entry)
    server.mode = .normal
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.marks.map(\.isPending) == [false])
    #expect(jesper.sync.pendingCount == 0)
}

@Test func slutaDelaTarBortAdressen() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.unshare(key)
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.addresses.isEmpty == true)
}

@Test func expiresAtArDagenEfterISverige() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.mark(entry)
    try await jesper.sync.mark(PlacedOut(key: key, date: DayDate("2026-07-01")!))
    let id = try jesper.keys().householdId
    // 00:00 svensk tid dagen efter: vintertid UTC+1 och sommartid UTC+2.
    let expires = server.household(id)?.records.compactMap(\.wire.expiresAt).compactMap(RelayDate.parse)
    #expect(expires == [RelayDate.parse("2026-11-27T23:00:00Z")!, RelayDate.parse("2026-07-01T22:00:00Z")!])
}

@Test func forbrukadeBockarTasBortLokalt() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.mark(entry)
    let before = server.requests.count
    await jesper.sync.removeExpired(today: DayDate("2026-11-28")!)
    #expect(await jesper.state()?.marks.isEmpty == true)
    #expect(server.requests.count == before)
}

@Test func postSomServernNekarStopparInteKon() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    server.change { $0.failing["PUT"] = 413 }
    try await jesper.sync.share(saved())
    server.change { $0.failing = [:] }
    try await jesper.sync.mark(entry)
    await jesper.sync.fetchChanges()
    #expect(jesper.sync.pendingCount == 0)
    #expect(await jesper.state()?.marks.count == 1)
    #expect(await jesper.state()?.addresses.isEmpty == true)
}

// MARK: Namn och deltagare

@Test func namnSparasKrypterat() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    try await jesper.sync.mark(entry)
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.setMyName("Jeppe")
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.participants.map(\.name) == ["Jeppe", "Sofie"])
    #expect(await jesper.state()?.myName == "Jeppe")
    let text = server.everything
    for secret in ["Jeppe", "Jesper", "Sofie", "gatan", "avesta", "Hemma", key.fileName, try jesper.keys().householdKey.base64URL] {
        #expect(!text.localizedCaseInsensitiveContains(secret), "\(secret)")
    }
}

@Test func legacyVisarRattNamnOchTid() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let at = Date(timeIntervalSince1970: 1_794_000_000)
    try await jesper.sync.upload(address: saved(), legacyBy: "_sofie", at: at)
    try await jesper.sync.upload(mark: entry, legacyBy: "_sofie", at: at)
    let sofie = try await member(server, of: jesper, name: nil)
    #expect(await sofie.state()?.marks.map(\.by) == ["_sofie"])
    try await sofie.sync.setMyName("Sofie", legacyId: "_sofie")
    await jesper.sync.fetchChanges()
    let state = try #require(await jesper.state())
    let sofieId = try sofie.keys().participantId
    #expect(state.marks.map(\.by) == [sofieId])
    #expect(state.marks.map(\.at) == [at])
    #expect(state.addresses.map(\.addedBy) == [sofieId])
    #expect(state.participants.map(\.legacyIds) == [[], ["_sofie"]])
    // Ett nytt namn behåller kopplingen.
    try await sofie.sync.setMyName("Soffan")
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.participants.map(\.legacyIds) == [[], ["_sofie"]])
    #expect(await jesper.state()?.marks.map(\.by) == [sofieId])
}

@Test func nyEnhetSammaDeltagare() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    await jesper.sync.registerDevice(token: "aa", environment: "production")
    let fresh = RelayPhone(server, credentials: jesper.credentials, deviceId: "ny")
    await fresh.sync.fetchChanges()
    await fresh.sync.registerDevice(token: "bb", environment: "sandbox")
    let household = try #require(server.household(try jesper.keys().householdId))
    let me = household.participants[0].id
    #expect(household.participants.count == 1)
    #expect(household.devices == ["enhet": "\(me) aa", "ny": "\(me) bb"])
    #expect(await fresh.state()?.role == .owner)
}

@Test func tokenInnanHushalletSkickasNarDetFinns() async throws {
    let server = FakeRelayServer()
    let phone = RelayPhone(server)
    await phone.sync.registerDevice(token: "aa", environment: "production")
    #expect(server.requests.isEmpty)
    try await phone.sync.create(myName: "Jesper")
    #expect(server.household(try phone.keys().householdId)?.devices.count == 1)
}

@Test func tokenSomInteGickAttSkickaSkickasIgen() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    server.mode = .offline
    await jesper.sync.registerDevice(token: "aa", environment: "production")
    server.mode = .normal
    await jesper.sync.fetchChanges()
    #expect(server.household(try jesper.keys().householdId)?.devices.count == 1)
    let count = server.requests.filter { $0.contains("devices") }.count
    await jesper.sync.fetchChanges()
    #expect(server.requests.filter { $0.contains("devices") }.count == count)
}

// MARK: Lämna

@Test func medlemLamnar() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    server.mode = .offline
    await #expect(throws: (any Error).self) { try await sofie.sync.leave() }
    #expect(try sofie.credentials.load() != nil)
    #expect(await sofie.state()?.role == .member)
    server.mode = .normal
    try await sofie.sync.leave()
    #expect(await sofie.state() == .empty)
    #expect(try sofie.credentials.load() == nil)
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.participants.map(\.name) == ["Jesper"])
    // Efteråt går det att gå med igen, som en ny deltagare.
    let link = try #require(HouseholdInviteLink(url: try await jesper.sync.invite()))
    try await sofie.sync.join(link, myName: "Sofie")
    #expect(await sofie.state()?.role == .member)
}

@Test func agarenAvslutarNarAgarenLamnar() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.leave()
    #expect(await jesper.state() == .empty)
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.status == .removed)
}

// MARK: Ändringar

@Test func baraNyaAndringarHamtas() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    await jesper.sync.fetchChanges()
    let seq = try #require(server.household(try jesper.keys().householdId)).seq
    await jesper.sync.fetchChanges()
    #expect(server.requests.last?.hasSuffix("changes?since=\(seq)") == true)
}

@Test func fullErsatterKopian() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    try await jesper.sync.unshare(key)
    server.change { inner in
        for id in inner.households.keys {
            inner.households[id]!.prunedSeq = inner.households[id]!.seq
            inner.households[id]!.deletions = []
            inner.households[id]!.seq += 1
        }
    }
    await sofie.sync.fetchChanges()
    #expect(await sofie.state()?.addresses.isEmpty == true)
}

@Test func olasbarPostTarInteBortAdressen() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let sofie = try await member(server, of: jesper)
    let other = AddressKey(source: "vafab", id: "77")
    try await jesper.sync.share(saved(other, name: "Stugan"))
    server.change { inner in
        for id in inner.households.keys {
            for index in inner.households[id]!.records.indices { inner.households[id]!.records[index].wire.data = "AAAA" }
            inner.households[id]!.prunedSeq = inner.households[id]!.seq
            inner.households[id]!.seq += 1
        }
    }
    await sofie.sync.fetchChanges()
    let state = try #require(await sofie.state())
    #expect(state.status == .synced)
    #expect(state.addresses.map(\.address.key) == [key])
}

@Test func signalGerHamtning() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    sofie.sync.startSignals()
    defer { sofie.sync.stopSignals() }
    try await jesper.sync.share(saved())
    for _ in 0..<200 where await sofie.state()?.addresses.isEmpty != false { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await sofie.state()?.addresses.count == 1)
}

@Test func signalerBorjarNarHushalletFinns() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = RelayPhone(server)
    sofie.sync.startSignals()
    defer { sofie.sync.stopSignals() }
    #expect(server.inner.withLock { $0.listeners.isEmpty })
    let link = try #require(HouseholdInviteLink(url: try await jesper.sync.invite()))
    try await sofie.sync.join(link, myName: "Sofie")
    for _ in 0..<200 where server.inner.withLock({ $0.listeners.isEmpty }) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(server.inner.withLock { $0.listeners.count } == 1)
}

@Test func oforandratLageSkickasInteIgen() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let count = Mutex(0)
    let task = Task { for await _ in jesper.sync.states() { count.withLock { $0 += 1 } } }
    for _ in 0..<5 { await jesper.sync.fetchChanges() }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    #expect(count.withLock { $0 } == 1)
}

@Test func mangaSamtidigaAnropFungerar() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let keys = (0..<20).map { AddressKey(source: "s", id: "\($0)") }
    await withTaskGroup(of: Void.self) { group in
        for key in keys {
            let sync = jesper.sync
            group.addTask { try? await sync.share(saved(key)) }
            group.addTask { await sync.fetchChanges() }
        }
    }
    await jesper.sync.fetchChanges()
    #expect(Set(try #require(await jesper.state()).addresses.map(\.address.key)) == Set(keys))
    #expect(jesper.sync.pendingCount == 0)
}

@Test func nycklarTillEttAnnatHushallBorjarOm() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let other = try await owner(server, name: "Kim")
    // Jag gick med i ett annat hushåll på min andra telefon.
    try jesper.credentials.save(try other.keys())
    await jesper.sync.fetchChanges()
    let state = try #require(await jesper.state())
    #expect(state.addresses.isEmpty)
    #expect(state.participants.map(\.name) == ["Kim"])
}

// MARK: Nycklarna

@Test func lokalaNycklarGallerNarDeSynkadeForsvinner() throws {
    let a = HouseholdCredentials(householdId: "a", householdKey: Data([1]), participantId: "p", participantSecret: "s")
    let b = HouseholdCredentials(householdId: "b", householdKey: Data([2]), participantId: "q", participantSecret: "t")
    let synced = InMemoryCredentialStore(), local = InMemoryCredentialStore()
    let store = LayeredCredentialStore(synced: synced, local: local)
    #expect(try store.load() == nil)
    try synced.save(a)
    #expect(try store.load() == a)
    try synced.delete()
    #expect(try store.load() == a)
    try synced.save(b)
    #expect(try store.load() == b)
    synced.failing = true
    #expect(try store.load() == b)
    synced.failing = false
    try store.delete()
    #expect(try synced.load() == nil)
    #expect(try local.load() == nil)
    synced.failing = true
    #expect(throws: (any Error).self) { try store.load() }
}

@Test func nycklarnaSkrivsInteUt() {
    let a = HouseholdCredentials(householdId: "a", householdKey: Data([1]), participantId: "p", participantSecret: "hemlig")
    #expect(!"\(a) \(String(reflecting: a))".contains("hemlig"))
}

@Test func vantetidenVaxerTillTrettioSekunder() {
    #expect([0, 1, 2, 3, 4, 5, 6, 7, 1000].map(RelayBackoff.delay) == [1, 1, 2, 4, 8, 16, 30, 30, 30].map { .seconds($0) })
}

// MARK: Nycklarna på flera enheter

/// En telefon med en egen kopia av nycklarna och en iCloud-nyckelring som delas med andra.
private func layered(_ synced: InMemoryCredentialStore, _ local: InMemoryCredentialStore = InMemoryCredentialStore()) -> LayeredCredentialStore {
    LayeredCredentialStore(synced: synced, local: local)
}

@Test func annanDeltagareISammaHushallBytsInteIn() throws {
    let mine = HouseholdCredentials(householdId: "h", householdKey: Data([1]), participantId: "agare", participantSecret: "s")
    let other = HouseholdCredentials(householdId: "h", householdKey: Data([1]), participantId: "medlem", participantSecret: "t")
    let synced = InMemoryCredentialStore(), local = InMemoryCredentialStore()
    let store = layered(synced, local)
    try store.save(mine)
    // En annan av mina enheter gick med som en ny deltagare, och dess nycklar vann i iCloud-nyckelringen.
    try synced.save(other)
    #expect(try store.load() == mine)
    #expect(try local.load() == mine)
}

@Test func synkadeNycklarSkrivsInteOverISammaHushall() throws {
    let mine = HouseholdCredentials(householdId: "h", householdKey: Data([1]), participantId: "agare", participantSecret: "s")
    let other = HouseholdCredentials(householdId: "h", householdKey: Data([1]), participantId: "medlem", participantSecret: "t")
    let synced = InMemoryCredentialStore(mine)
    let local = InMemoryCredentialStore()
    try layered(synced, local).save(other)
    #expect(try synced.load() == mine)
    #expect(try local.load() == other)
    // Bara lokalt rör aldrig iCloud-nyckelringen.
    let empty = InMemoryCredentialStore()
    try layered(empty, local).saveLocally(mine)
    #expect(try empty.load() == nil)
}

@Test func iCloudNyckelringenBehoverInteFungera() throws {
    let a = HouseholdCredentials(householdId: "a", householdKey: Data([1]), participantId: "p", participantSecret: "s")
    let synced = InMemoryCredentialStore(), local = InMemoryCredentialStore()
    synced.failing = true
    let store = layered(synced, local)
    try store.save(a)
    #expect(try store.load() == a)
    try store.delete(a)
    #expect(try local.load() == nil)
}

@Test func borttagningRorInteNycklarTillEttAnnatHushall() throws {
    let a = HouseholdCredentials(householdId: "a", householdKey: Data([1]), participantId: "p", participantSecret: "s")
    let b = HouseholdCredentials(householdId: "b", householdKey: Data([2]), participantId: "q", participantSecret: "t")
    let synced = InMemoryCredentialStore(b), local = InMemoryCredentialStore(a)
    try layered(synced, local).delete(a)
    #expect(try synced.load() == b)
    #expect(try local.load() == nil)
}

/// Fokus 5 i planen: en ny iPhone som återställs från en säkerhetskopia innan nycklarna har kommit.
@Test func aterstalldUtanNycklarHarInteLamnat() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.mode = .offline
    try await jesper.sync.mark(entry)
    server.mode = .normal
    let keys = try jesper.keys()
    let empty = InMemoryCredentialStore()
    let restored = RelayPhone(server, credentials: empty, directory: jesper.directory, deviceId: "ny")
    #expect(await restored.state()?.status == .failed)
    await restored.sync.fetchChanges()
    let state = try #require(await restored.state())
    #expect(state.status == .failed)
    #expect(state.role == .owner)
    #expect(state.addresses.count == 1)
    #expect(restored.sync.hasHousehold)
    #expect(restored.sync.pendingCount == 1)
    // När nycklarna kommer är allt kvar, också det som väntade.
    try empty.save(keys)
    await restored.sync.fetchChanges()
    #expect(await restored.state()?.status == .synced)
    #expect(await restored.state()?.marks.map(\.isPending) == [false])
}

@Test func utanNycklarGarDetAttLamnaPaTelefonen() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let restored = RelayPhone(server, credentials: InMemoryCredentialStore(), directory: jesper.directory)
    try await restored.sync.leave()
    #expect(await restored.state() == .empty)
    #expect(!restored.sync.hasHousehold)
    // Hushållet rörs inte på servern.
    #expect(server.household(try jesper.keys().householdId)?.ended == false)
}

@Test func nyaNycklarISammaHushallBehallerKon() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    server.mode = .offline
    try await sofie.sync.mark(entry)
    server.mode = .normal
    var seen: [HouseholdState] = []
    try sofie.credentials.save(try jesper.keys())
    await sofie.sync.fetchChanges()
    if let state = await sofie.state() { seen.append(state) }
    #expect(seen.last?.marks.map(\.placedOut) == [entry])
    #expect(sofie.sync.pendingCount == 0)
}

@Test func nyaNycklarRegistrerarEnheten() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let kim = try await owner(server, name: "Kim")
    await jesper.sync.registerDevice(token: "aa", environment: "production")
    try jesper.credentials.save(try kim.keys())
    await jesper.sync.fetchChanges()
    #expect(server.household(try kim.keys().householdId)?.devices.count == 1)
}

// MARK: Byta hushåll

@Test func ogiltigLankBehallerDetGamlaHushallet() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    let kim = try await owner(server, name: "Kim")
    let link = try #require(HouseholdInviteLink(url: try await kim.sync.invite()))
    try await kim.sync.revokeInvites()
    await #expect(throws: HouseholdMembershipError.inviteInvalid) { try await jesper.sync.join(link, myName: "Jesper", replacing: true) }
    #expect(await jesper.state()?.role == .owner)
    #expect(server.household(try jesper.keys().householdId)?.ended == false)
}

@Test func bytetLamnarDetGamlaForstNarDetNyaFinns() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    let sofie = try await member(server, of: jesper)
    let kim = try await owner(server, name: "Kim")
    let link = try #require(HouseholdInviteLink(url: try await kim.sync.invite()))
    // Det gamla går inte att lämna: jag är kvar där, och inte med i det nya.
    server.change { $0.failing["DELETE /households/\(try! jesper.keys().householdId)/participants"] = 500 }
    await #expect(throws: HouseholdMembershipError.failed) { try await sofie.sync.join(link, myName: "Sofie", replacing: true) }
    #expect(sofie.sync.isCurrent(link) == false)
    #expect(await sofie.state()?.role == .member)
    let kimId = try kim.keys().householdId
    #expect(server.household(kimId)?.participants.filter { !$0.removed }.count == 1)
    server.change { $0.failing = [:] }
    try await sofie.sync.join(link, myName: "Sofie", replacing: true)
    #expect(await sofie.state()?.participants.map(\.name) == ["Kim", "Sofie"])
    #expect(server.household(try jesper.keys().householdId)?.participants.filter { !$0.removed }.count == 1)
}

// MARK: Svar som inte är som väntat

@Test func konstigtSvarTarInteBortPosten() async throws {
    let server = FakeRelayServer()
    let jesper = try await owner(server)
    try await jesper.sync.share(saved())
    server.change { $0.failing["PUT"] = 200 }
    try await jesper.sync.mark(entry)
    server.change { $0.failing = [:] }
    // Svaret var inte en post, så bocken är inte bekräftad utan väntar.
    #expect(await jesper.state()?.marks.map(\.isPending) == [true])
    #expect(await jesper.state()?.addresses.count == 1)
    await jesper.sync.fetchChanges()
    #expect(await jesper.state()?.marks.map(\.isPending) == [false])
}

/// En läsning av nycklarna som kan hållas kvar mitt i.
private final class HeldStore: HouseholdCredentialStore {
    private let base = InMemoryCredentialStore()
    private let holding = Mutex(false)
    private let reached = Mutex(false)
    var isHeld: Bool { reached.withLock { $0 } }
    let release = DispatchSemaphore(value: 0)

    func holdNext() { holding.withLock { $0 = true } }

    func load() throws -> HouseholdCredentials? {
        let value = try base.load()
        let hold = holding.withLock { holding in
            defer { holding = false }
            return holding
        }
        if hold {
            reached.withLock { $0 = true }
            release.wait()
        }
        return value
    }

    func save(_ credentials: HouseholdCredentials) throws { try base.save(credentials) }
    func delete() throws { try base.delete() }
}

@Test func gammalLasningAvNycklarnaSkriverInteOver() async throws {
    let server = FakeRelayServer()
    let kim = try await owner(server, name: "Kim")
    let link = try #require(HouseholdInviteLink(url: try await kim.sync.invite()))
    let held = HeldStore()
    let sync = RelayHouseholdSync(transport: server, credentials: held, store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)), deviceId: { "e" })
    try await sync.create(myName: "Jesper")

    // Ett tryck börjar läsa nycklarna till det gamla hushållet, och under tiden byter jag till ett nytt.
    held.holdNext()
    let tap = Task.detached { try? await sync.mark(entry) }
    while !held.isHeld { try await Task.sleep(for: .milliseconds(5)) }
    server.change { $0.failing["PUT"] = 500 }
    try await sync.join(link, myName: "Jesper", replacing: true)
    held.release.signal()
    _ = await tap.value
    #expect(sync.isCurrent(link))
    #expect(sync.pendingCount >= 1)
    server.change { $0.failing = [:] }
    await sync.fetchChanges()
    #expect(sync.lastState?.participants.map(\.name) == ["Kim", "Jesper"])
}
