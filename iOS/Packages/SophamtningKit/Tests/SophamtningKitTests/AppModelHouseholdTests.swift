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
    private var deliveredTitles: [String] = []

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
    func deliverNow(identifier: String, title: String, body: String) async {
        lock.withLock { deliveries.append((identifier, body)); deliveredTitles.append(title) }
    }
    func resetCalls() { lock.withLock { calls = 0; deliveries = []; deliveredTitles = [] } }
    var titles: [String] { lock.withLock { deliveredTitles } }
    var scheduleCalls: Int { lock.withLock { calls } }
    var delivered: [(identifier: String, body: String)] { lock.withLock { deliveries } }
    func hasPending(for date: String) -> Bool { lock.withLock { store.values.contains { $0.pickupDate.iso == date } } }
}

/// Hushållet i minnet, som räknar hur ofta en bock skickas.
private final class CountingHousehold: HouseholdSync, @unchecked Sendable {
    let inner: InMemoryHouseholdSync
    private let lock = NSLock()
    private var marks = 0
    private var expiredCalls = 0
    /// En post som inte går att ta bort: synken skickar läget igen men tar inte bort något.
    let removalFails: Bool
    init(_ inner: InMemoryHouseholdSync, removalFails: Bool = false) { self.inner = inner; self.removalFails = removalFails }
    var markCalls: Int { lock.withLock { marks } }
    var removeExpiredCalls: Int { lock.withLock { expiredCalls } }

    func states() -> AsyncStream<HouseholdState> { inner.states() }
    func share(_ address: SavedAddress) async throws { try await inner.share(address) }
    func unshare(_ key: AddressKey) async throws { try await inner.unshare(key) }
    func mark(_ placedOut: PlacedOut) async throws {
        lock.withLock { marks += 1 }
        try await inner.mark(placedOut)
    }
    func unmark(_ placedOut: PlacedOut) async throws { try await inner.unmark(placedOut) }
    func leave() async throws { try await inner.leave() }
    func removeExpired(today: DayDate) async {
        lock.withLock { expiredCalls += 1 }
        if removalFails { await inner.fetchChanges() } else { await inner.removeExpired(today: today) }
    }
    func fetchChanges() async { await inner.fetchChanges() }
    func setMyName(_ name: String) async throws { try await inner.setMyName(name) }
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

/// Räknar hur ofta widgeten laddas om.
@MainActor
private final class WidgetReloads {
    var count = 0
}

/// Hemmaadressen sparad och hämtad, med notiser på. Hushållet är inte startat än.
@MainActor
private func makeModel(_ sync: some HouseholdSync, scheduler: FakeScheduler, clock: TestClock, directory: URL, widget: WidgetReloads? = nil) async throws -> AppModel {
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: directory), now: { clock.now }, scheduler: scheduler, widgetReloader: { widget?.count += 1 }, household: sync)
    model.add(hit())
    await model.refreshAll(manual: false)
    _ = await model.setNotifications(true, for: home)
    await model.settleReminders()
    return model
}

/// Kör `action`, som ska ge minst ett nytt läge, och väntar tills räknaren passerat läget före och sedan stått still en stund.
/// Därefter väntar den på påminnelserna.
@MainActor
private func settle(_ model: AppModel, _ action: () async -> Void) async {
    let baseline = model.handledHouseholdStates
    await action()
    var last = baseline
    var quiet = 0
    for _ in 0..<1000 {
        let count = model.handledHouseholdStates
        if count > baseline, count == last {
            quiet += 1
            if quiet >= 5 { break }
        } else {
            quiet = 0
            last = count
        }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(model.handledHouseholdStates > baseline, "inget nytt läge behandlades")
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
    await settle(model) { model.startHousehold() }

    await settle(model) { sync.simulateRemote { $0.addresses.append(HouseholdAddress(address: address(storgatan, name: "Storgatan 3", notificationsOn: true), addedBy: "kim")) } }

    let added = try #require(model.addresses.first { $0.key == storgatan })
    #expect(added.notificationsOn == false)
    #expect(model.householdPreferences.receivedKeys == [storgatan])
}

@Test @MainActor func andrasBockTystarPaminnelsen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(scheduler.hasPending(for: "2026-11-11"))

    await settle(model) { sync.simulateRemote { $0.marks.append(kimsMark()) } }

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
    await settle(model) { model.startHousehold() }

    await settle(model) { sync.simulateRemote { $0.marks.append(kimsMark()) } }

    #expect(model.household.marks.contains { $0.by == "kim" })
    #expect(scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func andrasBockTystarMorgonpaminnelsen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(model.setReminderTiming(.sameMorning))
    await settle(model) { model.startHousehold() }
    let morning = StockholmClock.date(on: tomorrow, minutes: 6 * 60)
    #expect(await scheduler.pending().contains { $0.fireDate == morning })

    // Kim ställer ut. Tysta är på från början, så morgonens påminnelse tas bort.
    await settle(model) { sync.simulateRemote { $0.marks.append(kimsMark()) } }
    #expect(!scheduler.hasPending(for: "2026-11-11"))
    #expect(!(await scheduler.pending().contains { $0.fireDate == morning }))

    // Kim ångrar innan morgonens tid, så påminnelsen kommer tillbaka.
    await settle(model) { sync.simulateRemote { $0.marks.removeAll() } }
    #expect(await scheduler.pending().contains { $0.fireDate == morning })
}

@Test @MainActor func egenBockSparasLokaltOchIHushallet() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]), now: { noon })
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    await settle(model) { await model.placeOut(home) }

    let entry = PlacedOut(key: home, date: tomorrow)
    #expect(LocalStore(directory: temp.url).placedOut() == [entry])
    #expect(await currentState(sync).marks == [HouseholdMark(placedOut: entry, by: "jag", at: noon, isPending: false)])
}

@Test @MainActor func angraLaggerTillbakaPaminnelsen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    await settle(model) { await model.placeOut(home) }
    #expect(!scheduler.hasPending(for: "2026-11-11"))

    await settle(model) { await model.undoPlaceOut(home) }
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
    await settle(model) { model.startHousehold() }

    await settle(model) { await model.placeOut(home) }
    clock.set(evening)
    model.applyReminders()
    await model.settleReminders()
    scheduler.resetCalls()

    await settle(model) { await model.undoPlaceOut(home) }
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
    await settle(model) { model.startHousehold() }
    await settle(model) {
        await sync.fetchChanges()
        await sync.fetchChanges()
    }
    #expect(model.household.marks.contains { $0.placedOut == entry })
    #expect(sync.markCalls == 1)
    #expect(await currentState(sync).marks.map(\.placedOut) == [entry])

    // Finns bocken redan i hushållet skickas inget.
    let otherTemp = TempDir()
    let already = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: shared, marks: [kimsMark()])))
    let other = try await makeModel(already, scheduler: FakeScheduler(), clock: TestClock(noon), directory: otherTemp.url)
    try LocalStore(directory: otherTemp.url).markPlacedOut(entry, today: DayDate("2026-11-10")!)
    await settle(other) { other.startHousehold() }
    #expect(other.household.marks.contains { $0.by == "kim" })
    await settle(other) { await already.fetchChanges() }
    #expect(already.markCalls == 0)
}

@Test @MainActor func notisNarNagonAnnanStallerUt() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(await model.setNotifyWhenOthersPlaceOut(true) == .granted)
    await settle(model) { model.startHousehold() }

    await settle(model) {
        sync.simulateRemote { state in
            state.addresses.append(HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim"))
            state.marks.append(kimsMark(storgatan))
        }
    }

    #expect(scheduler.delivered.map(\.body) == ["Kim ställde ut kärlen för Storgatan 3"])
    #expect(scheduler.titles == ["Kärlen är utställda"])
    #expect(scheduler.delivered.map(\.identifier) == ["hushall.\(storgatan.fileName).2026-11-11"])
    #expect(model.householdPreferences.notifiedMarks == [PlacedOut(key: storgatan, date: tomorrow)])

    #expect(model.household.marks.contains { $0.by == "kim" })
    await settle(model) { await sync.fetchChanges() }
    #expect(scheduler.delivered.count == 1)
}

@Test @MainActor func egenBockGerIngenNotis() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    _ = await model.setNotifyWhenOthersPlaceOut(true)
    await settle(model) { model.startHousehold() }

    // Min bock från en annan enhet med samma id.
    await settle(model) { sync.simulateRemote { $0.marks.append(HouseholdMark(placedOut: PlacedOut(key: home, date: tomorrow), by: "jag", at: noon, isPending: false)) } }

    #expect(model.household.marks.contains { $0.by == "jag" })
    #expect(scheduler.delivered.isEmpty)
}

@Test @MainActor func lamnaBehallerAdresserna() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.householdPreferences.receivedKeys == [storgatan])

    await settle(model) { await model.leaveHousehold() }

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
    await settle(model) { model.startHousehold() }
    #expect(model.addresses.contains { $0.key == storgatan })

    await settle(model) {
        sync.simulateRemote { state in
            state.status = .notSignedIn
            state.addresses = []
        }
    }

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
    await settle(model) { model.startHousehold() }
    await settle(model) { await model.placeOut(home) }

    // Kim trycker Ångra på min bock.
    await settle(model) { sync.simulateRemote { $0.marks = [] } }

    #expect(LocalStore(directory: temp.url).placedOut().isEmpty)
    #expect(scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func avstangtHushallAndrarInget() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let model = try await makeModel(DisabledHousehold(), scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.addresses.map(\.key) == [home])
    #expect(model.householdNotice == nil)
    #expect(scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func egenBockFranAnnanEnhetTystarAlltid() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    model.setSilenceWhenOthersPlaceOut(false)
    await settle(model) { model.startHousehold() }
    #expect(scheduler.hasPending(for: "2026-11-11"))

    // Min bock från en annan enhet tystar även när valet för andras bockar är av.
    await settle(model) { sync.simulateRemote { $0.marks.append(HouseholdMark(placedOut: PlacedOut(key: home, date: tomorrow), by: "jag", at: noon, isPending: false)) } }

    #expect(model.household.marks.contains { $0.by == "jag" })
    #expect(!scheduler.hasPending(for: "2026-11-11"))
    #expect(LocalStore(directory: temp.url).placedOut().isEmpty)
}

@Test @MainActor func felLageBehallerBockarna() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let entry = PlacedOut(key: home, date: tomorrow)
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")], marks: [kimsMark()])))
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.household.marks.contains { $0.by == "kim" })
    #expect(!scheduler.hasPending(for: "2026-11-11"))

    // Min egen utställda finns lokalt, och Kims bock för samma tömning finns redan i hushållet.
    try LocalStore(directory: temp.url).markPlacedOut(entry, today: DayDate("2026-11-10")!)
    await settle(model) {
        sync.inner.simulateRemote { state in
            state.status = .failed
            state.marks = []
        }
    }

    #expect(model.household.status == .failed)
    #expect(model.household.marks.contains { $0.by == "kim" })
    #expect(model.household.participants.contains { $0.id == "kim" })
    #expect(sync.markCalls == 0)
    // Felet är inget Ångra, så min egen utställda står kvar.
    #expect(LocalStore(directory: temp.url).placedOut() == [entry])
    try LocalStore(directory: temp.url).unmarkPlacedOut(entry)
    model.applyReminders()
    await model.settleReminders()
    #expect(!scheduler.hasPending(for: "2026-11-11"))
}

@Test @MainActor func forbrukadBockTasBortEnGangPerDag() async throws {
    let temp = TempDir()
    let old = kimsMark(date: DayDate("2026-11-09")!)
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")], marks: [old])), removalFails: true)
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    await settle(model) {
        await sync.fetchChanges()
        await sync.fetchChanges()
    }

    #expect(model.household.marks == [old])
    #expect(sync.removeExpiredCalls == 1)
}

@Test @MainActor func bockSomForsvannMedAdressenArInteAngra() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    await settle(model) { await model.placeOut(home) }
    #expect(model.household.marks.contains { $0.by == "jag" })

    // Adressen slutar delas, och bocken försvinner med den. Min egen utställda står kvar.
    await settle(model) {
        sync.simulateRemote { state in
            state.addresses = []
            state.marks = []
        }
    }

    #expect(LocalStore(directory: temp.url).placedOut() == [PlacedOut(key: home, date: tomorrow)])
}

// MARK: Slutgranskningen

@Test @MainActor func utstalltFranLiveActivitySkickasNarLagetArOforandrat() async throws {
    let entry = PlacedOut(key: home, date: tomorrow)
    let shared = [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]
    let temp = TempDir()
    // Som CloudKit: ett oförändrat läge skickas inte igen, så en hämtning utan ändringar ger inget nytt läge.
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: shared), resendsUnchanged: false))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    // Knappen i Live Activity skriver i lagringen medan appen inte körs.
    try LocalStore(directory: temp.url).markPlacedOut(entry, today: DayDate("2026-11-10")!)
    await settle(model) { await model.fetchHouseholdChanges() }

    #expect(sync.markCalls == 1)
    #expect(await currentState(sync).marks.map(\.placedOut) == [entry])
    await model.fetchHouseholdChanges()
    #expect(sync.markCalls == 1)
}

@Test @MainActor func widgetenLaddasOmNarBockarAndras() async throws {
    let temp = TempDir()
    let widget = WidgetReloads()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url, widget: widget)
    await settle(model) { model.startHousehold() }

    // Ett oförändrat läge laddar inte om widgeten.
    widget.count = 0
    await settle(model) { await sync.fetchChanges() }
    #expect(widget.count == 0)

    // Kims bock från en annan telefon.
    await settle(model) { sync.simulateRemote { $0.marks.append(kimsMark()) } }
    #expect(widget.count >= 1)

    widget.count = 0
    await settle(model) { await model.undoPlaceOut(home) }
    #expect(widget.count >= 1)
    // Widgeten läser hushållet från lagringen, där Ångra syns.
    if case .value(let saved) = LocalStore(directory: temp.url).householdState() {
        #expect(!saved.marks.contains { $0.by == "kim" })
    } else {
        Issue.record("Hushållet ska vara sparat")
    }

    widget.count = 0
    await settle(model) { await model.placeOut(home) }
    #expect(widget.count >= 1)

    // Ett nytt läge för hushållet, till exempel utloggat.
    widget.count = 0
    await settle(model) { sync.simulateRemote { $0.status = .notSignedIn } }
    #expect(widget.count >= 1)
}

@Test @MainActor func felLageVisarMinNyaBock() async throws {
    let temp = TempDir()
    let entry = PlacedOut(key: home, date: tomorrow)
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")])))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    // Utan nät: min bock väntar på att skickas, och synken säger att något inte fungerar.
    let mine = HouseholdMark(placedOut: entry, by: "jag", at: noon, isPending: true)
    await settle(model) {
        sync.inner.simulateRemote { state in
            state.status = .failed
            state.marks = [mine]
        }
    }

    #expect(model.household.status == .failed)
    #expect(model.household.marks == [mine])
    let line = try #require(HouseholdLine.make(household: model.household, key: home, nextPickup: tomorrow, today: DayDate("2026-11-10")!))
    #expect(!line.showsButton)
    #expect(line.isPending)
}

@Test @MainActor func kortetForBorttagenVisasEnGang() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(storgatan, name: "Storgatan 3"), addedBy: "kim")]))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    // Ägaren tar bort mig ur hushållet.
    await settle(model) { sync.simulateRemote { $0 = .empty; $0.status = .removed } }
    #expect(model.householdNotice == HouseholdTexts.leftNote)

    // Arket har visat raden och stängts.
    model.clearHouseholdNotice()
    #expect(HouseholdTexts.status(model.household.status) == nil)
    guard case .value(let saved) = LocalStore(directory: temp.url).householdState() else {
        Issue.record("Hushållet ska vara sparat")
        return
    }
    #expect(HouseholdTexts.status(saved.status) == nil)

    // Samma läge en gång till visar ingenting.
    await settle(model) { sync.simulateRemote { $0.participants = [] } }
    #expect(model.householdNotice == nil)
    #expect(HouseholdTexts.status(model.household.status) == nil)
}

// MARK: Nya deltagare

private let sofie = HouseholdParticipant(id: "sofie", name: "Sofie", isOwner: false)

@Test @MainActor func nyDeltagareGerRadOchNotis() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(await model.setNotifyWhenOthersPlaceOut(true) == .granted)
    await settle(model) { model.startHousehold() }
    // Kim fanns redan när hushållet sågs första gången.
    #expect(model.householdMembersText == nil)
    #expect(scheduler.delivered.isEmpty)

    await settle(model) { sync.simulateRemote { $0.participants.append(sofie) } }

    #expect(model.householdMembersText == "Sofie gick med i hushållet")
    #expect(scheduler.delivered.map(\.body) == ["Sofie gick med i hushållet"])
    #expect(scheduler.delivered.map(\.identifier) == ["hushall.deltagare.sofie"])

    // Samma läge igen ger ingen ny notis, och raden står kvar tills den har setts.
    await settle(model) { await sync.fetchChanges() }
    #expect(scheduler.delivered.count == 1)
    #expect(model.householdMembersText == "Sofie gick med i hushållet")

    // Raden finns kvar efter en omstart.
    #expect(LocalStore(directory: temp.url).householdPreferences().joinedNames == ["Sofie"])

    model.clearMembersNotice()
    #expect(model.householdMembersText == nil)
    await settle(model) { await sync.fetchChanges() }
    #expect(model.householdMembersText == nil)
    #expect(scheduler.delivered.count == 1)
}

@Test @MainActor func nyDeltagareUtanValGerBaraRaden() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    await settle(model) { sync.simulateRemote { $0.participants.append(sofie) } }

    #expect(model.householdMembersText == "Sofie gick med i hushållet")
    #expect(scheduler.delivered.isEmpty)
}

@Test @MainActor func lamnaGlommerDeKandaDeltagarna() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    await settle(model) { sync.simulateRemote { $0.participants.append(sofie) } }
    #expect(model.householdPreferences.knownParticipants == ["jag", "kim", "sofie"])

    await model.leaveHousehold()

    #expect(model.householdPreferences.knownParticipants == nil)
    #expect(model.householdMembersText == nil)
}

@Test @MainActor func inbjudanOpnarArketMedValkomst() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: .empty)
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(!model.householdSheetRequested)

    model.expectHouseholdWelcome(ownerName: "Kim")
    await settle(model) { sync.simulateRemote { $0 = householdState() } }

    #expect(model.householdSheetRequested)
    #expect(model.householdNotice == "Du är med i Kims hushåll. Adresser som delas visas på hemskärmen.")
    // Kim var med redan när jag gick med och är inte ny.
    #expect(model.householdMembersText == nil)

    model.householdSheetShown()
    #expect(!model.householdSheetRequested)
}

@Test @MainActor func bockFranLiveActivitySkickasDirekt() async throws {
    let temp = TempDir()
    let sync = CountingHousehold(InMemoryHouseholdSync(state: householdState(addresses: [HouseholdAddress(address: address(home, name: "Hemma"), addedBy: "jag")])))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(sync.markCalls == 0)

    // Knappen i Live Activity skriver bara i lagringen, som intenten gör.
    try LocalStore(directory: temp.url).markPlacedOut(PlacedOut(key: home, date: tomorrow), today: DayDate("2026-11-10")!)
    await settle(model) { await model.sendLiveActivityMarks() }

    #expect(sync.markCalls == 1)
    #expect(await currentState(sync).marks.contains { $0.placedOut == PlacedOut(key: home, date: tomorrow) && $0.by == "jag" })
}

@Test @MainActor func bockFranLiveActivityUtanHushallSkickasInte() async throws {
    let temp = TempDir()
    let sync = CountingHousehold(InMemoryHouseholdSync(state: .empty))
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    try LocalStore(directory: temp.url).markPlacedOut(PlacedOut(key: home, date: tomorrow), today: DayDate("2026-11-10")!)
    await model.sendLiveActivityMarks()

    #expect(sync.markCalls == 0)
}

// MARK: Utställt för alla adresser

@Test @MainActor func egenMarkeringVisasForAdressSomInteDelas() throws {
    let next = DayDate("2026-11-11")!
    let empty = HouseholdLine.make(household: .empty, key: home, nextPickup: next, today: DayDate("2026-11-10")!)
    #expect(empty == nil)
    let line = try #require(HouseholdLine.make(household: .empty, key: home, nextPickup: next, today: DayDate("2026-11-10")!, ownPlacedOut: [PlacedOut(key: home, date: next)]))
    #expect(line.placedOutTitle == "Kärlen är utställda")
    #expect(line.placedOutText == "Kärlen är utställda")
    #expect(!line.isShared && !line.showsButton && line.sharedText == nil)
    // En markering för en annan tömning visas inte.
    #expect(HouseholdLine.make(household: .empty, key: home, nextPickup: next, today: DayDate("2026-11-10")!, ownPlacedOut: [PlacedOut(key: home, date: DayDate("2026-11-18")!)]) == nil)
}

@Test @MainActor func angraLaterLiveActivityStartaIgen() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: .empty)
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    let store = LocalStore(directory: temp.url)
    let entry = PlacedOut(key: home, date: tomorrow)
    // Klart i Live Activity: markerad och aktiviteten avslutad.
    try store.markPlacedOut(entry, today: DayDate("2026-11-10")!)
    try store.markEnded([entry], today: DayDate("2026-11-10")!)
    try store.markShown([entry], today: DayDate("2026-11-10")!)

    await model.undoPlaceOut(home)

    guard case .value(let left) = store.placedOutState() else { Issue.record("placed-out.json gick inte att läsa"); return }
    #expect(left.isEmpty)
    #expect(store.endedActivities().isEmpty)
    #expect(store.shownActivities().isEmpty)
}

@Test @MainActor func nyPaminnelsetidLaterBortsveptAktivitetStartaIgen() async throws {
    let temp = TempDir()
    let model = try await makeModel(InMemoryHouseholdSync(state: .empty), scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    let store = LocalStore(directory: temp.url)
    let entry = PlacedOut(key: home, date: tomorrow)
    try store.markEnded([entry], today: DayDate("2026-11-10")!)
    try store.markPlacedOut(PlacedOut(key: storgatan, date: tomorrow), today: DayDate("2026-11-10")!)

    #expect(model.setReminderMinutes(19 * 60))

    #expect(store.endedActivities().isEmpty)
    // En markering som utställd ändras inte av en ny tid.
    guard case .value(let kept) = store.placedOutState() else { Issue.record("placed-out.json gick inte att läsa"); return }
    #expect(kept == [PlacedOut(key: storgatan, date: tomorrow)])
}

// MARK: Mitt namn

@Test @MainActor func namnetSkickasTillHushalletOchSparas() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.householdNameMissing)

    await settle(model) { #expect(await model.setHouseholdName("  Sofie ")) }

    #expect(!model.householdNameMissing)
    #expect(model.householdName == "Sofie")
    #expect(model.household.myName == "Sofie")
    #expect(model.household.participants.first { $0.id == "jag" }?.name == "Sofie")
    #expect(LocalStore(directory: temp.url).householdPreferences().myName == "Sofie")
}

@Test @MainActor func tomtNamnSparasInte() async throws {
    let temp = TempDir()
    let model = try await makeModel(InMemoryHouseholdSync(state: householdState()), scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    #expect(await model.setHouseholdName("   ") == false)
    #expect(model.householdPreferences.myName == nil)
}

@Test @MainActor func namnetFranInnanJagGickMedSkickasNarHushalletKommer() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: .empty)
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    // Namnet skrivs innan Bjud in, när det ännu inte finns något hushåll.
    #expect(await model.setHouseholdName("Jesper"))
    #expect(model.household.myName == nil)

    await settle(model) { sync.simulateRemote { $0 = householdState() } }
    await settle(model) { await sync.fetchChanges() }

    #expect(await currentState(sync).myName == "Jesper")
}

@Test @MainActor func namnetFranEnAnnanEnhetAnvands() async throws {
    let temp = TempDir()
    var state = householdState()
    state.myName = "Jesper"
    let model = try await makeModel(InMemoryHouseholdSync(state: state), scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.householdPreferences.myName == "Jesper")
    #expect(!model.householdNameMissing)
}

@Test @MainActor func forslagetFranAppleKontotFyllerFaltet() async throws {
    let temp = TempDir()
    var state = householdState()
    state.suggestedName = "Jesper"
    let model = try await makeModel(InMemoryHouseholdSync(state: state), scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }
    #expect(model.householdName == "Jesper")
    // Ett förslag är inget sparat namn.
    #expect(model.householdNameMissing)
}

// MARK: Deltagare som inte längre är med

@Test @MainActor func deltagareSomLamnarGerRadOchNotis() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(await model.setNotifyWhenOthersPlaceOut(true) == .granted)
    await settle(model) { model.startHousehold() }

    await settle(model) { sync.simulateRemote { $0.participants.removeAll { $0.id == "kim" } } }

    #expect(model.householdMembersText == "Kim är inte längre med i hushållet")
    #expect(scheduler.delivered.map(\.body) == ["Kim är inte längre med i hushållet"])
    #expect(scheduler.titles == ["Hushållet"])

    // Raden finns kvar efter en omstart, och försvinner när den har setts.
    #expect(LocalStore(directory: temp.url).householdPreferences().leftNames == ["Kim"])
    model.clearMembersNotice()
    #expect(model.householdMembersText == nil)
}

@Test @MainActor func nyOchLamnadVisasEfterVarandra() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    await settle(model) { sync.simulateRemote { state in
        state.participants.removeAll { $0.id == "kim" }
        state.participants.append(sofie)
    } }

    #expect(model.householdMembersText == "Sofie gick med i hushållet. Kim är inte längre med i hushållet")
}

@Test @MainActor func deltagarlistanUtanMigGerIngenRad() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: scheduler, clock: TestClock(noon), directory: temp.url)
    #expect(await model.setNotifyWhenOthersPlaceOut(true) == .granted)
    await settle(model) { model.startHousehold() }

    // Delningen är inte hämtad, så listan är tom. Ingen har lämnat.
    await settle(model) { sync.simulateRemote { $0.participants = [] } }
    #expect(model.householdMembersText == nil)
    #expect(scheduler.delivered.isEmpty)

    // När listan kommer tillbaka är ingen ny heller.
    await settle(model) { sync.simulateRemote { $0 = householdState() } }
    #expect(model.householdMembersText == nil)
}

@Test @MainActor func jagSjalvLamnarGerIngenRad() async throws {
    let temp = TempDir()
    let sync = InMemoryHouseholdSync(state: householdState())
    let model = try await makeModel(sync, scheduler: FakeScheduler(), clock: TestClock(noon), directory: temp.url)
    await settle(model) { model.startHousehold() }

    await model.leaveHousehold()

    #expect(model.householdMembersText == nil)
    #expect(model.householdPreferences.leftNames.isEmpty)
}

