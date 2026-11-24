import Foundation
import Synchronization
import Testing
@testable import SophamtningKit

private let homeKey = AddressKey(source: "avesta-vatten", id: "12")
private let cabinKey = AddressKey(source: "vafab", id: "77")
private let start = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18
private let future = PlacedOut(key: homeKey, date: DayDate("2026-11-27")!)
private let past = PlacedOut(key: homeKey, date: DayDate("2026-11-10")!)
private let markedAt = Date(timeIntervalSince1970: 1_794_900_000)

private func saved(_ key: AddressKey) -> SavedAddress {
    SavedAddress(
        key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adresser/\(key.source)/\(key.id)")!, street: "G", locality: "", kommun: "K",
        detail: nil, selection: "address", displayName: "Hemma", isPrimary: false, addedAt: Date(timeIntervalSinceReferenceDate: 785_000_000)
    )
}

/// Hushållet i iCloud, i minnet.
final class FakeLegacyHousehold: LegacyHousehold {
    let base: InMemoryHouseholdSync
    let cloud: Cloud
    private let failing = Mutex(false)
    private let removals = Mutex<[String]>([])
    private let linkHook = Mutex<(@Sendable () -> Void)?>(nil)
    private let current: Mutex<HouseholdState>

    /// Det som delas mellan telefonerna i samma zon.
    final class Cloud: Sendable {
        let link = Mutex<URL?>(nil)
        let removed = Mutex(false)
    }

    init(_ state: HouseholdState, cloud: Cloud = Cloud()) {
        base = InMemoryHouseholdSync(state: state)
        self.cloud = cloud
        current = Mutex(state)
    }

    var linkFails: Bool {
        get { failing.withLock { $0 } }
        set { failing.withLock { $0 = newValue } }
    }

    var removedIds: [String] { removals.withLock { $0 } }
    var afterLink: (@Sendable () -> Void)? {
        get { linkHook.withLock { $0 } }
        set { linkHook.withLock { $0 = newValue } }
    }

    var isReliablyEmpty: Bool { current.withLock { $0.role == .none && $0.status == .synced } }
    func removeParticipants(_ ids: [String]) async throws { removals.withLock { $0 += ids } }

    func set(_ state: HouseholdState) {
        current.withLock { $0 = state }
        base.simulateRemote { $0 = state }
    }

    func states() -> AsyncStream<HouseholdState> { base.states() }
    func share(_ address: SavedAddress) async throws { try await base.share(address) }
    func unshare(_ key: AddressKey) async throws { try await base.unshare(key) }
    func mark(_ placedOut: PlacedOut) async throws { try await base.mark(placedOut) }
    func unmark(_ placedOut: PlacedOut) async throws { try await base.unmark(placedOut) }
    func leave() async throws { set(.empty) }
    func removeExpired(today: DayDate) async {}
    func setMyName(_ name: String) async throws { try await base.setMyName(name) }
    func fetchChanges() async {}

    var legacyMyId: String? { current.withLock { $0.myId } }
    func legacySnapshot() async -> HouseholdState? {
        let state = current.withLock { $0 }
        return state.role != .none && state.status == .synced ? state : nil
    }
    func migrationLink() async -> URL? { cloud.link.withLock { $0 } }
    func writeMigrationLink(_ url: URL) async throws {
        if linkFails { throw URLError(.notConnectedToInternet) }
        cloud.link.withLock { $0 = url }
        afterLink?()
    }
    func removeShare() async throws {
        cloud.removed.withLock { $0 = true }
        set(.empty)
    }
}

func legacyState(me: String, owner: Bool, name: String? = "Jag") -> HouseholdState {
    HouseholdState(
        role: owner ? .owner : .member, myId: me,
        participants: [
            HouseholdParticipant(id: "_jesper", name: "Jesper", isOwner: true),
            HouseholdParticipant(id: "_sofie", name: "Sofie", isOwner: false),
        ],
        addresses: [HouseholdAddress(address: saved(homeKey), addedBy: "_jesper"), HouseholdAddress(address: saved(cabinKey), addedBy: "_sofie")],
        marks: [HouseholdMark(placedOut: future, by: "_sofie", at: markedAt, isPending: false), HouseholdMark(placedOut: past, by: "_jesper", at: markedAt, isPending: false)],
        status: .synced, myName: name
    )
}

final class TestTime: Sendable {
    private let value = Mutex(start)
    var now: Date { value.withLock { $0 } }
    func set(_ change: (inout Date) -> Void) { value.withLock { change(&$0) } }
}

/// En telefon med både iCloud och brevlådan.
private final class MigratingPhone: Sendable {
    let relay: RelayHouseholdSync
    let legacy: FakeLegacyHousehold
    let migrator: HouseholdMigrator
    let routing: RoutingHouseholdSync
    let store: LocalStore
    let migration: HouseholdMigrationStore
    let clock = TestTime()

    let directory: URL
    let credentials: any HouseholdCredentialStore

    init(_ server: FakeRelayServer, _ state: HouseholdState, cloud: FakeLegacyHousehold.Cloud, credentials: any HouseholdCredentialStore = InMemoryCredentialStore(), directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        self.credentials = credentials
        store = LocalStore(directory: self.directory)
        relay = RelayHouseholdSync(transport: server, credentials: credentials, store: store, deviceId: { "enhet" }, now: { start })
        legacy = FakeLegacyHousehold(state, cloud: cloud)
        migration = HouseholdMigrationStore(store: store)
        routing = RoutingHouseholdSync(relay: relay, legacy: legacy, migration: migration, store: store)
        migrator = HouseholdMigrator(relay: relay, legacy: legacy, transport: server, migration: migration, now: { [clock] in clock.now }, onChange: { [routing] in routing.migrationDidChange() })
    }

    func state() async throws -> HouseholdState {
        try await Task.sleep(for: .milliseconds(40))
        return try #require(routing.lastState)
    }
}

private func pair(_ server: FakeRelayServer = FakeRelayServer(), migration: Bool = true) -> (FakeRelayServer, MigratingPhone, MigratingPhone, FakeLegacyHousehold.Cloud) {
    server.change { $0.migration = migration }
    let cloud = FakeLegacyHousehold.Cloud()
    return (server, MigratingPhone(server, legacyState(me: "_jesper", owner: true, name: "Jesper"), cloud: cloud), MigratingPhone(server, legacyState(me: "_sofie", owner: false, name: "Sofie"), cloud: cloud), cloud)
}

@Test func flyttenStartarBaraNarConfigSagerDet() async throws {
    let (server, jesper, _, cloud) = pair(migration: false)
    await jesper.migrator.run()
    #expect(server.requests == ["GET /config"])
    #expect(cloud.link.withLock { $0 } == nil)
    #expect(try await jesper.state().myId == "_jesper")
    server.mode = .status(500)
    await jesper.migrator.run()
    server.mode = .offline
    await jesper.migrator.run()
    #expect(!jesper.relay.hasHousehold)
}

@Test func agarenFlyttarAllt() async throws {
    let (server, jesper, _, cloud) = pair()
    await jesper.migrator.run()
    let url = try #require(cloud.link.withLock { $0 })
    let link = try #require(HouseholdInviteLink(url: url))
    let household = try #require(server.household(link.householdId))
    let expires = try #require(household.invites[link.inviteToken]).expires
    #expect(abs(expires.timeIntervalSince(server.inner.withLock(\.now)) - 90 * 86_400) < 1)
    // Den förbrukade bocken flyttas inte.
    #expect(household.records.count == 3)

    let state = try await jesper.state()
    #expect(state.role == .owner)
    #expect(Set(state.addresses.map(\.address.key)) == [homeKey, cabinKey])
    #expect(state.participants.map(\.name) == ["Jesper"])
    #expect(state.participants[0].legacyIds == ["_jesper"])
    #expect(state.marks.map(\.by) == ["_sofie"])
    #expect(state.marks.map(\.at) == [markedAt])
    #expect(state.addresses.first { $0.address.key == homeKey }?.addedBy == state.myId)
    #expect(jesper.routing.managesMembers)
}

@Test func avbrutenFlyttFortsatterISammaHushall() async throws {
    for step in ["PUT", "invites", "länk"] {
        let (server, jesper, _, cloud) = pair()
        if step == "länk" { jesper.legacy.linkFails = true } else { server.change { $0.failing[step] = 500 } }
        await jesper.migrator.run()
        #expect(cloud.link.withLock { $0 } == nil, "\(step)")
        // Till dess gäller hushållet i iCloud.
        #expect(try await jesper.state().myId == "_jesper", "\(step)")
        #expect(!jesper.routing.managesMembers)
        server.change { $0.failing = [:] }
        jesper.legacy.linkFails = false
        await jesper.migrator.run()
        #expect(server.inner.withLock { $0.households.count } == 1, "\(step)")
        let link = try #require(cloud.link.withLock { $0 }.flatMap { HouseholdInviteLink(url: $0) })
        #expect(server.household(link.householdId)?.records.count == 3)
        #expect(server.household(link.householdId)?.invites[link.inviteToken] != nil)
        #expect(try await jesper.state().addresses.count == 2, "\(step)")
        #expect(jesper.routing.managesMembers)
    }
}

@Test func avbrutenFlyttVantarNarFlyttenStangsAv() async throws {
    let (server, jesper, _, _) = pair()
    jesper.legacy.linkFails = true
    await jesper.migrator.run()
    server.change { $0.migration = false }
    jesper.legacy.linkFails = false
    await jesper.migrator.run()
    #expect(try await jesper.state().myId == "_jesper")
}

@Test func flyttadFlyttasInteTillbaka() async throws {
    let (server, jesper, _, _) = pair()
    await jesper.migrator.run()
    server.change { $0.migration = false }
    await jesper.migrator.run()
    #expect(jesper.routing.managesMembers)
}

@Test func forloradFlyttinbjudanErsattsAvEnVanlig() async throws {
    let (server, jesper, _, cloud) = pair()
    // Servern skapade inbjudan, men svaret kom aldrig fram.
    server.change { $0.failing["invites"] = 500 }
    await jesper.migrator.run()
    server.change { inner in
        inner.failing = [:]
        for id in inner.households.keys { inner.households[id]!.migrationInvited = true }
    }
    await jesper.migrator.run()
    let first = try #require(cloud.link.withLock { $0 })
    // Den vanliga går ut efter sju dagar och förnyas innan.
    jesper.clock.set { $0 = start.addingTimeInterval(6 * 86_400) }
    server.change { $0.now = start.addingTimeInterval(6 * 86_400) }
    await jesper.migrator.run()
    let second = try #require(cloud.link.withLock { $0 })
    #expect(first != second)
    #expect(HouseholdInviteLink(url: first)?.householdId == HouseholdInviteLink(url: second)?.householdId)
}

@Test func medlemmenGarMedTyst() async throws {
    let (server, jesper, sofie, _) = pair()
    await jesper.migrator.run()
    let before = server.requests.filter { $0.contains("records") }.count
    // Medlemmen går med också när flytten har stängts av för nya.
    server.change { $0.migration = false }
    await sofie.migrator.run()
    let state = try await sofie.state()
    #expect(state.role == .member)
    #expect(state.participants.map(\.name) == ["Jesper", "Sofie"])
    #expect(state.participants.map(\.legacyIds) == [["_jesper"], ["_sofie"]])
    #expect(state.marks.map(\.by) == [state.myId])
    #expect(server.requests.filter { $0.contains("records") }.count == before)
    #expect(sofie.routing.managesMembers)
}

@Test func medlemUtanLankStarKvarIICloud() async throws {
    let (server, _, sofie, cloud) = pair()
    await sofie.migrator.run()
    #expect(server.inner.withLock { $0.households.isEmpty })
    cloud.link.withLock { $0 = URL(string: "https://example.com/annat") }
    await sofie.migrator.run()
    #expect(try await sofie.state().myId == "_sofie")
}

@Test func medlemMedUtgangenLankStarKvarIICloud() async throws {
    let (server, jesper, sofie, _) = pair()
    await jesper.migrator.run()
    server.change { $0.now = start.addingTimeInterval(91 * 86_400) }
    await sofie.migrator.run()
    #expect(try await sofie.state().myId == "_sofie")
    #expect(try await sofie.state().addresses.count == 2)
}

@Test func medlemUtanNamnBehallerKopplingen() async throws {
    let (server, jesper, _, cloud) = pair()
    await jesper.migrator.run()
    let sofie = MigratingPhone(server, legacyState(me: "_sofie", owner: false, name: nil), cloud: cloud)
    await sofie.migrator.run()
    let state = try await sofie.state()
    #expect(state.participants.last?.name == "Någon")
    #expect(state.participants.last?.legacyIds == ["_sofie"])
    #expect(state.marks.map(\.by) == [state.myId])
}

@Test func agarensAndraEnhetVantarPaNycklarna() async throws {
    let (server, jesper, _, cloud) = pair()
    let synced = InMemoryCredentialStore()
    await jesper.migrator.run()
    let keys = try #require(try jesper.credentials.load())
    let other = MigratingPhone(server, legacyState(me: "_jesper", owner: true, name: "Jesper"), cloud: cloud, credentials: LayeredCredentialStore(synced: synced, local: InMemoryCredentialStore()))
    await other.migrator.run()
    // Den går inte med som en ny deltagare, och inget nytt hushåll skapas.
    #expect(server.household(keys.householdId)?.participants.count == 1)
    #expect(server.inner.withLock { $0.households.count } == 1)
    #expect(try await other.state().myId == "_jesper")
    // När iCloud-nyckelringen har hunnit är det samma ägare.
    try synced.save(keys)
    await other.routing.fetchChanges()
    await other.migrator.run()
    let state = try await other.state()
    #expect(state.role == .owner)
    #expect(state.addresses.count == 2)
    #expect(other.routing.managesMembers)
}

@Test func agarensAndraEnhetUtanNyckelringGarMedEfterEttDygn() async throws {
    let (server, jesper, _, cloud) = pair()
    let synced = InMemoryCredentialStore()
    await jesper.migrator.run()
    let other = MigratingPhone(server, legacyState(me: "_jesper", owner: true, name: "Jesper"), cloud: cloud, credentials: LayeredCredentialStore(synced: synced, local: InMemoryCredentialStore()))
    await other.migrator.run()
    other.clock.set { $0 = start.addingTimeInterval(25 * 3600) }
    await other.migrator.run()
    #expect(try await other.state().role == .member)
    // Nycklarna stannar på den telefonen, så att ägarens egna aldrig skrivs över.
    #expect(try synced.load() == nil)
}

@Test func osakertLageFlyttasInte() async throws {
    let (server, jesper, _, _) = pair()
    var state = legacyState(me: "_jesper", owner: true)
    state.status = .failed
    jesper.legacy.set(state)
    await jesper.migrator.run()
    #expect(server.inner.withLock { $0.households.isEmpty })
}

@Test func efter90DagarTasDelningenBort() async throws {
    let (_, jesper, _, cloud) = pair()
    await jesper.migrator.run()
    jesper.clock.set { $0 = start.addingTimeInterval(89 * 86_400) }
    await jesper.migrator.run()
    #expect(!cloud.removed.withLock { $0 })
    jesper.clock.set { $0 = start.addingTimeInterval(91 * 86_400) }
    await jesper.migrator.run()
    #expect(cloud.removed.withLock { $0 })
    #expect(try await jesper.state().addresses.count == 2)
}

@Test func avslutatHushallKommerInteTillbakaFranICloud() async throws {
    let (_, jesper, sofie, cloud) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    try await jesper.routing.leave()
    await jesper.migrator.run()
    #expect(try await jesper.state().role == HouseholdRole.none)
    // Delningen i iCloud tas bort direkt, så att de som inte har flyttat också ser att hushållet är slut.
    #expect(cloud.removed.withLock { $0 })
    await sofie.routing.fetchChanges()
    #expect(try await sofie.state().status == .removed)
    await sofie.migrator.run()
    #expect(try await sofie.state().role == HouseholdRole.none)
}

// MARK: Valet av synk

@Test func utanHushallNagonstansArLagetTomt() async throws {
    let phone = MigratingPhone(FakeRelayServer(), .empty, cloud: .init())
    #expect(try await phone.state() == .empty)
    #expect(phone.routing.managesMembers)
}

@Test func nyttHushallSkapasIBrevladan() async throws {
    let server = FakeRelayServer()
    let phone = MigratingPhone(server, .empty, cloud: .init())
    try await phone.routing.create(myName: "Jesper")
    #expect(server.inner.withLock { $0.households.count } == 1)
    #expect(try await phone.state().role == .owner)
}

@Test func utloggadFranICloudHindrarInteEttNyttHushall() async throws {
    let server = FakeRelayServer()
    var signedOut = HouseholdState.empty
    signedOut.status = .notSignedIn
    let phone = MigratingPhone(server, signedOut, cloud: .init())
    #expect(try await phone.state() == .empty)
    try await phone.routing.create(myName: "Jesper")
    #expect(try await phone.state().status == .synced)
}

@Test func vantarPaICloudInnanHushalletRaknasSomBorta() async throws {
    let server = FakeRelayServer()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = LocalStore(directory: directory)
    try store.setHouseholdState(legacyState(me: "_sofie", owner: false))
    let relay = RelayHouseholdSync(transport: server, credentials: InMemoryCredentialStore(), store: store, deviceId: { "e" })
    var failed = HouseholdState.empty
    failed.status = .failed
    let legacy = FakeLegacyHousehold(failed)
    let routing = RoutingHouseholdSync(relay: relay, legacy: legacy, migration: HouseholdMigrationStore(store: store), store: store)
    try await Task.sleep(for: .milliseconds(40))
    // Brevlådan är tom, men det är iCloud som vet. Ett fel där får aldrig se ut som att jag lämnat.
    #expect(routing.lastState?.status == .failed)
    legacy.set(legacyState(me: "_sofie", owner: false))
    try await Task.sleep(for: .milliseconds(40))
    #expect(routing.lastState?.addresses.count == 2)
    var removed = HouseholdState.empty
    removed.status = .removed
    legacy.set(removed)
    try await Task.sleep(for: .milliseconds(40))
    #expect(routing.lastState?.status == .removed)
}

@Test func hushallIICloudHanterasDar() async throws {
    let (server, jesper, _, _) = pair(migration: false)
    _ = try await jesper.state()
    #expect(!jesper.routing.managesMembers)
    await #expect(throws: HouseholdMembershipError.unsupported) { _ = try await jesper.routing.invite() }
    await #expect(throws: HouseholdMembershipError.unsupported) { try await jesper.routing.create(myName: "x") }
    try await jesper.routing.mark(PlacedOut(key: cabinKey, date: DayDate("2026-11-30")!))
    #expect(server.requests.isEmpty)
    #expect(try await jesper.state().marks.count == 3)
}

@Test func pushTokenGarTillBrevladan() async throws {
    let (server, jesper, _, _) = pair()
    await jesper.routing.registerDevice(token: "aa", environment: "production")
    await jesper.migrator.run()
    let id = try #require(server.inner.withLock { $0.households.keys.first })
    #expect(server.household(id)?.devices.count == 1)
}

@Test func nyInbjudanFranICloudEfterFlyttenGaller() async throws {
    let (_, jesper, sofie, _) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    try await sofie.routing.leave()
    sofie.legacy.set(.empty)
    #expect(try await sofie.state().role == HouseholdRole.none)
    // En ägare med en gammal version bjuder in via iCloud.
    sofie.routing.legacyInvitationAccepted()
    sofie.legacy.set(legacyState(me: "_sofie", owner: false))
    #expect(try await sofie.state().role == .member)
}

// MARK: Efter granskningen

@Test func aterstalldUtanNycklarTarInteBortDelningen() async throws {
    let (server, jesper, _, cloud) = pair()
    await jesper.migrator.run()
    _ = try await jesper.state()
    // En ny iPhone från en säkerhetskopia: allt utom nycklarna.
    let restored = MigratingPhone(server, legacyState(me: "_jesper", owner: true), cloud: cloud, directory: jesper.directory)
    await restored.migrator.run()
    #expect(!cloud.removed.withLock { $0 })
    #expect(try await restored.state().status == .failed)
    #expect(try await restored.state().addresses.count == 2)
}

@Test func avslutatPaEnAnnanEnhetTarBortDelningen() async throws {
    let (server, jesper, _, cloud) = pair()
    await jesper.migrator.run()
    let keys = try #require(try jesper.credentials.load())
    let other = RelayPhone(server, credentials: InMemoryCredentialStore(keys))
    await other.sync.fetchChanges()
    try await other.sync.end()
    await jesper.routing.fetchChanges()
    _ = try await jesper.state()
    await jesper.migrator.run()
    #expect(cloud.removed.withLock { $0 })
}

@Test func borttagenSynsAvenNarICloudInteFungerar() async throws {
    for status in [HouseholdStatus.notSignedIn, .failed] {
        let server = FakeRelayServer()
        var broken = HouseholdState.empty
        broken.status = status
        let phone = MigratingPhone(server, broken, cloud: .init())
        let owner = RelayPhone(server)
        try await owner.sync.create(myName: "Kim")
        let link = try #require(HouseholdInviteLink(url: try await owner.sync.invite()))
        try await phone.routing.join(link, myName: "Jag")
        let state = try await phone.state()
        #expect(state.role == .member)
        // Appens modell sparar läget.
        try phone.store.setHouseholdState(state)
        try await owner.sync.remove(participantId: try #require(state.myId))
        await phone.routing.fetchChanges()
        #expect(try await phone.state().status == .removed, "\(status)")
    }
}

@Test func borttagenMedlemKommerInteTillbakaMedFlyttlanken() async throws {
    let (server, jesper, sofie, cloud) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    let old = try #require(cloud.link.withLock { $0 })
    let id = try #require(try await sofie.state().myId)
    await jesper.routing.fetchChanges()
    try await jesper.routing.remove(participantId: id)
    #expect(jesper.legacy.removedIds == ["_sofie"])
    // Länken i zonen är ny, och den gamla fungerar inte, så att de som inte har flyttat fortfarande kan gå med.
    let new = try #require(cloud.link.withLock { $0 })
    #expect(new != old)
    let again = MigratingPhone(server, legacyState(me: "_sofie", owner: false), cloud: .init())
    again.legacy.cloud.link.withLock { $0 = old }
    await again.migrator.run()
    #expect(!again.relay.hasHousehold)
    let kim = MigratingPhone(server, legacyState(me: "_kim", owner: false, name: "Kim"), cloud: cloud)
    await kim.migrator.run()
    #expect(try await kim.state().role == .member)
}

@Test func flyttlankenGorsOmNarDetInteGickDirekt() async throws {
    let (server, jesper, sofie, cloud) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    let old = try #require(cloud.link.withLock { $0 })
    await jesper.routing.fetchChanges()
    jesper.legacy.linkFails = true
    try await jesper.routing.remove(participantId: try #require(try await sofie.state().myId))
    #expect(cloud.link.withLock { $0 } == old)
    jesper.legacy.linkFails = false
    await jesper.migrator.run()
    let new = try #require(cloud.link.withLock { $0 }.flatMap { HouseholdInviteLink(url: $0) })
    #expect(server.household(new.householdId)?.invites[new.inviteToken] != nil)
}

@Test func denSomLamnarLamnarOcksaDelningenIICloud() async throws {
    let (server, jesper, sofie, cloud) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    _ = try await sofie.state()
    try await sofie.routing.leave()
    #expect(await sofie.legacy.legacySnapshot() == nil)
    _ = (server, cloud)
}

@Test func angradBockKommerInteTillbakaEfterAvbrottet() async throws {
    let (server, jesper, _, cloud) = pair()
    jesper.legacy.linkFails = true
    await jesper.migrator.run()
    // Under tiden ångras bocken, och en adress slutar delas i iCloud.
    var state = legacyState(me: "_jesper", owner: true, name: "Jesper")
    state.marks = []
    state.addresses.removeAll { $0.address.key == cabinKey }
    jesper.legacy.set(state)
    jesper.legacy.linkFails = false
    await jesper.migrator.run()
    let moved = try await jesper.state()
    #expect(moved.marks.isEmpty)
    #expect(moved.addresses.map(\.address.key) == [homeKey])
    let id = try #require(cloud.link.withLock { $0 }.flatMap { HouseholdInviteLink(url: $0) }).householdId
    #expect(server.household(id)?.records.count == 1)
}

@Test func avslutatUnderFlyttenLaserInteUteNagon() async throws {
    let (server, jesper, _, _) = pair()
    jesper.legacy.linkFails = true
    await jesper.migrator.run()
    jesper.legacy.set(.empty)
    try jesper.store.setHouseholdState(.empty)
    await jesper.migrator.run()
    let half = try #require(server.inner.withLock { $0.households.values.first })
    #expect(half.ended)
    #expect(!jesper.relay.hasHousehold)
    try await jesper.routing.create(myName: "Jesper")
    #expect(try await jesper.state().addresses.isEmpty)
    #expect(try await jesper.state().role == .owner)
}

@Test func halvtHushallVisasInteEfterEnInbjudanViaICloud() async throws {
    let (_, jesper, _, _) = pair()
    jesper.legacy.linkFails = true
    await jesper.migrator.run()
    jesper.routing.legacyInvitationAccepted()
    jesper.legacy.set(legacyState(me: "_jesper", owner: false))
    #expect(try await jesper.state().role == .member)
    #expect(try await jesper.state().myId == "_jesper")
    await jesper.migrator.run()
    #expect(!jesper.relay.hasHousehold)
    #expect(try await jesper.state().role == .member)
}

@Test func lankenSparasInteILasbarText() async throws {
    let (_, jesper, _, cloud) = pair()
    jesper.legacy.linkFails = true
    await jesper.migrator.run()
    func text() throws -> String {
        try FileManager.default.contentsOfDirectory(at: jesper.directory, includingPropertiesForKeys: nil).map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }.joined()
    }
    let key = try #require(try jesper.credentials.load()).householdKey.base64URL
    #expect(try !text().contains(key))
    jesper.legacy.linkFails = false
    await jesper.migrator.run()
    #expect(cloud.link.withLock { $0 } != nil)
    #expect(try !text().contains(key))
}

@Test func ettAnnatHushallIBrevladanRaknasInteSomFlyttat() async throws {
    let (server, _, _, cloud) = pair()
    let phone = MigratingPhone(server, .empty, cloud: cloud)
    _ = try await phone.state()
    try await phone.routing.create(myName: "Jesper")
    // iCloud svarar först nu: jag äger ett hushåll där, som andra är med i.
    phone.legacy.set(legacyState(me: "_jesper", owner: true))
    await phone.migrator.run()
    #expect(phone.migration.current?.moved == false)
    // När det nya avslutas syns det i iCloud igen.
    try await phone.routing.leave()
    #expect(try await phone.state().addresses.count == 2)
}

@Test func skrivenLankGorFlyttenKlarAvenOmDenStangsAv() async throws {
    let (server, jesper, sofie, _) = pair()
    // Avbrott precis efter att länken skrevs.
    jesper.legacy.afterLink = { server.mode = .offline }
    await jesper.migrator.run()
    server.mode = .normal
    server.change { $0.migration = false }
    jesper.legacy.afterLink = nil
    await sofie.migrator.run()
    await jesper.migrator.run()
    await jesper.routing.fetchChanges()
    #expect(jesper.routing.managesMembers)
    #expect(try await jesper.state().participants.count == 2)
}

@Test func byteAvHushallEfterFlyttenLamnarInteKvarDelningen() async throws {
    let (server, jesper, sofie, cloud) = pair()
    await jesper.migrator.run()
    await sofie.migrator.run()
    let kim = RelayPhone(server)
    try await kim.sync.create(myName: "Kim")
    let link = try #require(HouseholdInviteLink(url: try await kim.sync.invite()))
    _ = try await sofie.state()
    try await sofie.routing.join(link, myName: "Sofie", replacing: true)
    #expect(await sofie.legacy.legacySnapshot() == nil)
    _ = try await jesper.state()
    try await jesper.routing.join(link, myName: "Jesper", replacing: true)
    await jesper.migrator.run()
    #expect(cloud.removed.withLock { $0 })
    #expect(try await jesper.state().participants.map(\.name).contains("Kim"))
}
