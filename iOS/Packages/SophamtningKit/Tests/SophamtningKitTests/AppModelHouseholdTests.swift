import Testing
import Foundation
@testable import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-hushall-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private struct FixedAPI: SoporAPI {
    let response: AddressResponse
    func address(url: URL) async throws -> AddressResponse { response }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

/// En klocka som testet kan flytta fram.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

/// Ett notiscenter i minnet som också minns notiser som visats direkt.
private final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: PlannedNotification] = [:]
    private var calls = 0
    private var deliveries: [(identifier: String, body: String)] = []

    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> Bool { true }
    func pending() async -> [PendingNotification] {
        lock.withLock { store.values.map { PendingNotification(identifier: $0.identifier, fireDate: $0.fireDate, body: $0.body) } }
    }
    func schedule(_ notifications: [PlannedNotification]) async -> [String] {
        lock.withLock {
            calls += 1
            for n in notifications { store[n.identifier] = n }
            return []
        }
    }
    func cancel(identifiers: [String]) async {
        lock.withLock { for id in identifiers { store[id] = nil } }
    }
    func deliverNow(identifier: String, body: String) async {
        lock.withLock { deliveries.append((identifier, body)) }
    }
    func resetCalls() { lock.withLock { calls = 0; deliveries = [] } }
    var scheduleCalls: Int { lock.withLock { calls } }
    var delivered: [(identifier: String, body: String)] { lock.withLock { deliveries } }
    func hasPending(for date: String) -> Bool { lock.withLock { store.values.contains { $0.pickupDate.iso == date } } }
}

/// Hushållet i minnet, som räknar hur ofta en bock skickas.
private final class CountingHousehold: HouseholdSync, @unchecked Sendable {
    let inner: InMemoryHouseholdSync
    private let lock = NSLock()
    private var marks = 0
    init(_ inner: InMemoryHouseholdSync) { self.inner = inner }
    var markCalls: Int { lock.withLock { marks } }

    func states() -> AsyncStream<HouseholdState> { inner.states() }
    func share(_ address: SavedAddress) async throws { try await inner.share(address) }
    func unshare(_ key: AddressKey) async throws { try await inner.unshare(key) }
    func mark(_ placedOut: PlacedOut) async throws {
        lock.withLock { marks += 1 }
        try await inner.mark(placedOut)
    }
    func unmark(_ placedOut: PlacedOut) async throws { try await inner.unmark(placedOut) }
    func leave() async throws { try await inner.leave() }
    func removeExpired(today: DayDate) async { await inner.removeExpired(today: today) }
    func fetchChanges() async { await inner.fetchChanges() }
}

private let home = AddressKey(source: "orebro", id: "1")
private let storgatan = AddressKey(source: "orebro", id: "3")
private let tomorrow = DayDate("2026-11-11")!
/// Tisdag 10 november 2026 12:00 svensk tid. Påminnelsen för onsdagens tömning kommer 18:00.
private let noon = StockholmClock.date(on: DayDate("2026-11-10")!, minutes: 12 * 60)
private let evening = StockholmClock.date(on: DayDate("2026-11-10")!, minutes: 19 * 60)

private func hit() -> SearchHit {
    SearchHit(id: "1", street: "Storgatan 1", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!)
}

private func fixtureResponse() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private func address(_ key: AddressKey, name: String, notificationsOn: Bool = false) -> SavedAddress {
    SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/\(key.source)/\(key.id)")!, street: name, locality: "Örebro", kommun: "Örebro", detail: nil, selection: "address", displayName: name, isPrimary: true, notificationsOn: notificationsOn, addedAt: Date(timeIntervalSince1970: 0))
}

private func householdState(addresses: [HouseholdAddress] = [], marks: [HouseholdMark] = []) -> HouseholdState {
    HouseholdState(
        role: .member,
        myId: "jag",
        participants: [HouseholdParticipant(id: "jag", name: "Jesper", isOwner: false), HouseholdParticipant(id: "kim", name: "Kim", isOwner: true)],
        addresses: addresses,
        marks: marks,
        status: .synced
    )
}

private func kimsMark(_ key: AddressKey = home, date: DayDate = tomorrow) -> HouseholdMark {
    HouseholdMark(placedOut: PlacedOut(key: key, date: date), by: "kim", at: noon, isPending: false)
}

/// Hemmaadressen sparad och hämtad, med notiser på. Hushållet är inte startat än.
@MainActor
private func makeModel(_ sync: some HouseholdSync, scheduler: FakeScheduler, clock: TestClock, directory: URL) async throws -> AppModel {
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: directory), now: { clock.now }, scheduler: scheduler, household: sync)
    model.add(hit())
    await model.refreshAll(manual: false)
    _ = await model.setNotifications(true, for: home)
    await model.settleReminders()
    return model
}

/// Väntar tills hushållets lägen är behandlade och inget nytt har kommit på en stund, och sedan på påminnelserna.
@MainActor
private func settle(_ model: AppModel) async {
    var last = -1
    var quiet = 0
    for _ in 0..<500 {
        let count = model.handledHouseholdStates
        if count == last, count > 0 {
            quiet += 1
            if quiet >= 5 { break }
        } else {
            quiet = 0
            last = count
        }
        try? await Task.sleep(for: .milliseconds(2))
    }
    await model.settleReminders()
}

private func currentState(_ sync: some HouseholdSync) async -> HouseholdState {
    var iterator = sync.states().makeAsyncIterator()
    return await iterator.next() ?? .empty
}

@Test @MainActor func deladAdressFranAndraLaggsTill() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)

    sync.simulateRemote { $0.addresses.append(HouseholdAddress(address: address(storgatan, name: "Storgatan 3", notificationsOn: true), addedBy: "kim")) }
    await settle(model)

    let added = try #require(model.addresses.first { $0.key == storgatan })
    #expect(added.notificationsOn == false)
    #expect(model.householdPreferences.receivedKeys == [storgatan])
}

@Test @MainActor func andrasBockTystarPaminnelsen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)
    #expect(scheduler.hasPending(for: "2026-11-11"))

    sync.simulateRemote { $0.marks.append(kimsMark()) }
    await settle(model)

    #expect(!scheduler.hasPending(for: "2026-11-11"))
    // Andras bock skrivs aldrig i mina egna utställda.
    #expect(LocalStore(directory: temp.url).placedOut().isEmpty)
}

@Test @MainActor func andrasBockTystarInteNarValetArAv() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.setSilenceWhenOthersPlaceOut(false)
    model.startHousehold()
    await settle(model)

    sync.simulateRemote { $0.marks.append(kimsMark()) }
    await settle(model)

    #expect(scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func egenBockSparasLokaltOchIHushallet() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]), now: { noon })
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)

    await model.placeOut(home)
    await settle(model)

    let entry = PlacedOut(key: home, date: tomorrow)
    #expect(LocalStore(directory: temp.url).placedOut() == [entry])
    #expect(await currentState(sync).marks == [HouseholdMark(placedOut: entry, by: "jag", at: noon, isPending: false)])
}

@Test @MainActor func angraLaggerTillbakaPaminnelsen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)

    await model.placeOut(home)
    await settle(model)
    #expect(!scheduler.hasPending(for: "2026-11-11"))

    await model.undoPlaceOut(home)
    await settle(model)
    #expect(scheduler.hasPending(for: "2026-11-11"))
    #expect(LocalStore(directory: temp.url).placedOut().isEmpty)
    #expect(await currentState(sync).marks.isEmpty)
}

@Test @MainActor func angraEfterPaminnelsetidLaggerInteTillbaka() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let clock = TestClock(noon)
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: clock, directory: temp.url)
    model.startHousehold()
    await settle(model)

    await model.placeOut(home)
    await settle(model)
    clock.set(evening)
    model.applyReminders()
    await settle(model)
    scheduler.resetCalls()

    await model.undoPlaceOut(home)
    await settle(model)
    #expect(scheduler.scheduleCalls == 0)
    #expect(scheduler.delivered.isEmpty)
    #expect(!scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func utstalltFranLiveActivitySkickasEnGang() async throws {
    let entry = PlacedOut(key: home, date: tomorrow)
    let shared = [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]

    // Knappen i Live Activity skriver bara i lagringen. Appen skickar bocken en gång.
    let temp = TempDir()
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: shared)))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    try LocalStore(directory: temp.url).markPlacedOut(entry, today: DayDate("2026-11-10")!)
    model.startHousehold()
    await settle(model)
    await sync.fetchChanges()
    await sync.fetchChanges()
    await settle(model)
    #expect(sync.markCalls == 1)
    #expect(await currentState(sync).marks.map(\.placedOut) == [entry])

    // Finns bocken redan i hushållet skickas inget.
    let otherTemp = TempDir()
    let already = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: shared, marks: [kimsMark()])))
    let other = try await makeModel(already, scheduler: FakeScheduler(), clock: TestClock(noon), directory: otherTemp.url)
    try LocalStore(directory: otherTemp.url).markPlacedOut(entry, today: DayDate("2026-11-10")!)
    other.startHousehold()
    await settle(other)
    await already.fetchChanges()
    await settle(other)
    #expect(already.markCalls == 0)
}

@Test @MainActor func notisNarNagonAnnanStallerUt() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(await model.setNotifyWhenOthersPlaceOut(true) == .granted)
    model.startHousehold()
    await settle(model)

    sync.simulateRemote { state in
        state.addresses.append(HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim"))
        state.marks.append(kimsMark(storgatan))
    }
    await settle(model)

    #expect(scheduler.delivered.map(\.body) == ["Kim ställde ut kärlen för Storgatan 3"])
    #expect(scheduler.delivered.map(\.identifier) == ["hushall.\(storgatan.fileName).2026-11-11"])
    #expect(model.householdPreferences.notifiedMarks == [PlacedOut(key: storgatan, date: tomorrow)])

    await sync.fetchChanges()
    await settle(model)
    #expect(scheduler.delivered.count == 1)
}

@Test @MainActor func egenBockGerIngenNotis() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    _ = await model.setNotifyWhenOthersPlaceOut(true)
    model.startHousehold()
    await settle(model)

    // Min bock från en annan enhet med samma id.
    sync.simulateRemote { $0.marks.append(HouseholdMark(placedOut: PlacedOut(key: home, date: tomorrow), by: "jag", at: noon, isPending: false)) }
    await settle(model)

    #expect(scheduler.delivered.isEmpty)
}

@Test @MainActor func lamnaBehallerAdresserna() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)
    #expect(model.householdPreferences.receivedKeys == [storgatan])

    await model.leaveHousehold()
    await settle(model)

    #expect(model.addresses.contains { $0.key == storgatan })
    #expect(model.householdPreferences.receivedKeys.isEmpty)
    #expect(model.household.role == .none)
    #expect(model.householdNotice == HouseholdTexts.leftNote)
    model.clearHouseholdNotice()
    #expect(model.householdNotice == nil)
}

@Test @MainActor func utloggadBehallerAdresser() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)
    #expect(model.addresses.contains { $0.key == storgatan })

    sync.simulateRemote { state in
        state.status = .notSignedIn
        state.addresses = []
    }
    await settle(model)

    #expect(model.addresses.contains { $0.key == storgatan })
    #expect(model.householdPreferences.receivedKeys == [storgatan])
    #expect(model.household.status == .notSignedIn)
    #expect(model.isShared(storgatan))
}

@Test @MainActor func andrasAngraTarBortMinBock() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)
    await model.placeOut(home)
    await settle(model)

    // Kim trycker Ångra på min bock.
    sync.simulateRemote { $0.marks = [] }
    await settle(model)

    #expect(LocalStore(directory: temp.url).placedOut().isEmpty)
    #expect(scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func avstangtHushallAndrarInget() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let model = try await makeModel(DisabledHousehold(), scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.startHousehold()
    await settle(model)
    #expect(model.addresses.map(\.key) == [home])
    #expect(model.householdNotice == nil)
    #expect(scheduler.hasPending(for: "2026-11-11"))
}
