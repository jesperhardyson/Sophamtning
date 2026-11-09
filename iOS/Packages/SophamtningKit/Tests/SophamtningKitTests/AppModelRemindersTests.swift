import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-reminders-\(UUID().uuidString)", isDirectory: true)
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

/// Ett notiscenter i minnet. `pending()` ger också en notis som inte är appens egen, som aldrig ska röras.
private final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var status: NotificationAuthorization
    private let answer: Bool
    private var store: [String: PlannedNotification] = [:]
    private(set) var requests = 0
    private(set) var cancelled: [String] = []
    private(set) var scheduleCalls = 0
    private var failing: Set<String> = []
    let foreign = "annan-app-notis"

    init(status: NotificationAuthorization, answer: Bool = true) {
        self.status = status
        self.answer = answer
    }

    func authorization() async -> NotificationAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool {
        lock.withLock {
            requests += 1
            status = answer ? .authorized : .denied
            return answer
        }
    }
    func pending() async -> [PendingNotification] {
        lock.withLock {
            store.values.map { PendingNotification(identifier: $0.identifier, fireDate: $0.fireDate, body: $0.body) }
                + [PendingNotification(identifier: foreign, fireDate: nil, body: "Annat")]
        }
    }
    func schedule(_ notifications: [PlannedNotification]) async -> [String] {
        lock.withLock {
            scheduleCalls += 1
            var failed: [String] = []
            for n in notifications {
                if failing.contains(n.identifier) { failed.append(n.identifier) } else { store[n.identifier] = n }
            }
            return failed
        }
    }
    func cancel(identifiers: [String]) async {
        lock.withLock {
            cancelled += identifiers
            for id in identifiers { store[id] = nil }
        }
    }
    func setStatus(_ new: NotificationAuthorization) { lock.withLock { status = new } }
    func failAll(_ on: Bool, ids: [String]) { lock.withLock { failing = on ? Set(ids) : [] } }
    func resetCalls() { lock.withLock { cancelled = []; scheduleCalls = 0 } }
    var planned: [PlannedNotification] { lock.withLock { store.values.sorted { $0.fireDate < $1.fireDate } } }
}

private let key = AddressKey(source: "orebro", id: "1")
/// Fredag 6 november 2026 12:00 svensk tid. Schemat i fixturen har hämtningar från 11 november.
private let now = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

private func hit() -> SearchHit {
    SearchHit(id: "1", street: "Storgatan 1", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!)
}

private func fixtureResponse(events: [String]? = nil) throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    let base = try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
    guard let events else { return base }
    return AddressResponse(today: base.today, address: base.address, next: [], summary: "", events: events.map {
        PickupEvent(date: DayDate($0)!, fractions: ["rest"], estimated: false, deviation: nil, warning: nil, labels: [:])
    }, bins: [], fractions: base.fractions, links: base.links, updatedAt: base.updatedAt)
}

extension SavedAddress {
    static func fixtureForReminders(key: AddressKey) -> SavedAddress {
        SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!, street: "Storgatan 1", locality: "Örebro", kommun: "Örebro", detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
    }
}

@MainActor
private func makeModel(_ scheduler: FakeScheduler, directory: URL) async throws -> AppModel {
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: directory), now: { now }, scheduler: scheduler)
    model.add(hit())
    await model.refreshAll(manual: false)
    await model.settleReminders()
    return model
}

@Test @MainActor func inteSchemalagtForstNarNotisenSlasPa() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .notDetermined)
    let model = try await makeModel(scheduler, directory: temp.url)
    #expect(scheduler.requests == 0)
    #expect(scheduler.planned.isEmpty)
    #expect(model.addresses[0].notificationsOn == false)
}

@Test @MainActor func paslagFragarSchemalaggerOchStangerAvTarBortAlltIgen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .notDetermined)
    let model = try await makeModel(scheduler, directory: temp.url)

    let result = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(result == .granted)
    #expect(scheduler.requests == 1)
    #expect(model.addresses[0].notificationsOn)
    #expect(!scheduler.planned.isEmpty)
    #expect(scheduler.planned.allSatisfy { NotificationDiff.isOwn(identifier: $0.identifier) })

    let off = await model.setNotifications(false, for: key)
    await model.settleReminders()
    #expect(off == .granted)
    #expect(scheduler.planned.isEmpty)
    #expect(model.addresses[0].notificationsOn == false)
}

@Test @MainActor func nekatTillstandLamnarReglagetAvOchIngetSchemalaggs() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .notDetermined, answer: false)
    let model = try await makeModel(scheduler, directory: temp.url)

    let result = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(result == .denied)
    #expect(model.addresses[0].notificationsOn == false)
    #expect(model.notificationAuthorization == .denied)
    #expect(scheduler.planned.isEmpty)
    // Ett nytt försök frågar inte igen, systemet svarar redan nej.
    #expect(await model.setNotifications(true, for: key) == .denied)
    #expect(scheduler.requests == 1)
}

@Test @MainActor func tillstandSomDragitsTillbakaBehallerValetOchNotiserna() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    #expect(!before.isEmpty)

    scheduler.setStatus(.denied)
    model.applyReminders()
    await model.settleReminders()
    #expect(model.notificationAuthorization == .denied)
    // Valet är kvar, men det visade läget är av.
    #expect(model.addresses[0].notificationsOn)
    #expect(!model.remindersOn(for: model.addresses[0]))
    #expect(LocalStore(directory: temp.url).addresses()[0].notificationsOn)
    #expect(scheduler.planned == before)

    // Kommer tillståndet tillbaka planeras notiserna igen, även om de försvunnit under tiden.
    await scheduler.cancel(identifiers: before.map(\.identifier))
    scheduler.setStatus(.authorized)
    model.applyReminders()
    await model.settleReminders()
    #expect(scheduler.planned == before)
    #expect(model.remindersOn(for: model.addresses[0]))
}

@Test @MainActor func valAvMedOavgjortTillstandVisasSomAvOchFragarVidPaslag() async throws {
    let temp = TempDir()
    // Valet är sparat som på, men iOS har inte fått frågan.
    let store = LocalStore(directory: temp.url)
    var saved = SavedAddress.fixtureForReminders(key: key)
    saved.notificationsOn = true
    try store.setAddresses([saved])
    let scheduler = FakeScheduler(status: .notDetermined)
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: store, now: { now }, scheduler: scheduler)
    model.applyReminders()
    await model.settleReminders()
    #expect(model.notificationAuthorization == .notDetermined)
    #expect(!model.remindersOn(for: model.addresses[0]))
    #expect(scheduler.planned.isEmpty)
    #expect(scheduler.cancelled.isEmpty)

    #expect(await model.setNotifications(true, for: key) == .granted)
    #expect(scheduler.requests == 1)
    #expect(model.remindersOn(for: model.addresses[0]))
}

@Test @MainActor func framlingsnotiserRorsAldrig() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    _ = await model.setNotifications(false, for: key)
    await model.settleReminders()
    #expect(scheduler.planned.isEmpty)
    #expect(!scheduler.cancelled.contains(scheduler.foreign))
    model.remove(key)
    await model.settleReminders()
    #expect(!scheduler.cancelled.contains(scheduler.foreign))
}

@Test @MainActor func omkorningUtanAndringGerVarkenAddEllerCancel() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    scheduler.resetCalls()
    model.applyReminders()
    await model.settleReminders()
    model.applyReminders()
    await model.settleReminders()
    #expect(scheduler.scheduleCalls == 0)
    #expect(scheduler.cancelled.isEmpty)
}

@Test @MainActor func ersattNotisTasInteBortForstOchNyaFelenSynsOchForsoks() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    scheduler.resetCalls()

    // Den nya tiden går inte att lägga in: den gamla notisen står kvar, och felet visas.
    scheduler.failAll(true, ids: before.map(\.identifier))
    #expect(model.setReminderMinutes(19 * 60))
    await model.settleReminders()
    #expect(scheduler.cancelled.isEmpty)
    #expect(scheduler.planned == before)
    #expect(model.reminderError != nil)

    scheduler.failAll(false, ids: [])
    model.applyReminders()
    await model.settleReminders()
    #expect(model.reminderError == nil)
    #expect(scheduler.planned.map(\.identifier) == before.map(\.identifier))
    #expect(scheduler.planned.allSatisfy { Calendar(identifier: .gregorian).dateComponents(in: StockholmClock.timeZone, from: $0.fireDate).hour == 19 })
}

@Test @MainActor func skadadSchemafilTarInteBortNotiserMedValetPa() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    #expect(before.count > 1)

    // Appen startas om och schemafilen går inte att läsa.
    let schedulesDir = temp.url.appendingPathComponent("schedules")
    for file in try FileManager.default.contentsOfDirectory(at: schedulesDir, includingPropertiesForKeys: nil) {
        try Data("skräp".utf8).write(to: file)
    }
    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    restarted.applyReminders()
    await restarted.settleReminders()
    #expect(scheduler.planned == before)
    #expect(scheduler.cancelled.isEmpty)
    #expect(restarted.addresses[0].notificationsOn)
}

@Test @MainActor func skadadAdressfilTarInteBortNotiserOchSkrivsInteOver() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    let file = temp.url.appendingPathComponent("addresses.json")
    let good = try Data(contentsOf: file)
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.addresses.isEmpty)
    restarted.applyReminders()
    await restarted.settleReminders()
    #expect(scheduler.planned == before)
    #expect(scheduler.cancelled.isEmpty)
    // Att lägga till en adress skriver inte över filen.
    #expect(!restarted.add(hit()))
    #expect(restarted.lastStorageError != nil)
    #expect(try Data(contentsOf: file) == Data("skräp".utf8))

    // När filen går att läsa igen läses den om, och notiserna är kvar.
    try good.write(to: file)
    restarted.applyReminders()
    await restarted.settleReminders()
    #expect(restarted.addresses.count == 1)
    #expect(restarted.addresses[0].notificationsOn)
    #expect(scheduler.cancelled.isEmpty)
}

@Test @MainActor func skadadInstallningsfilTarInteBortNotiserOchSkrivsInteOver() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    #expect(model.setReminderMinutes(19 * 60))
    await model.settleReminders()
    let before = scheduler.planned
    let file = temp.url.appendingPathComponent("settings.json")
    let good = try Data(contentsOf: file)
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    restarted.applyReminders()
    await restarted.settleReminders()
    #expect(scheduler.planned == before)
    #expect(!restarted.setReminderMinutes(20 * 60))
    #expect(try Data(contentsOf: file) == Data("skräp".utf8))

    try good.write(to: file)
    restarted.applyReminders()
    await restarted.settleReminders()
    #expect(restarted.settings.reminderMinutes == 19 * 60)
    #expect(scheduler.planned == before)
}

@Test @MainActor func sparfelVidPaslagOchOkandAdressGerFailed() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .authorized), directory: temp.url)
    #expect(await model.setNotifications(true, for: AddressKey(source: "x", id: "y")) == .failed)
    #expect(await model.setNotifications(false, for: AddressKey(source: "x", id: "y")) == .failed)

    let blocked = TempDir()
    try Data().write(to: blocked.url)
    let store = LocalStore(directory: temp.url)
    let failing = AppModel(api: FixedAPI(response: try fixtureResponse()), store: store, now: { now }, scheduler: FakeScheduler(status: .authorized))
    // Katalogen blir en fil efter att adressen lästs in, så att sparandet misslyckas.
    try FileManager.default.removeItem(at: temp.url)
    try Data().write(to: temp.url)
    #expect(await failing.setNotifications(true, for: key) == .failed)
    #expect(failing.lastStorageError != nil)
    #expect(failing.addresses[0].notificationsOn == false)
}

@Test @MainActor func ersattAdressBehallerNamnHuvudadressOchNotisval() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(!scheduler.planned.isEmpty)

    model.add(SearchHit(id: "2", street: "Ny gata 1", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil, url: hit().url))
    let new = AddressKey(source: "orebro", id: "2")
    #expect(model.replace(key, with: new))
    await model.settleReminders()
    #expect(model.addresses.map(\.key) == [new])
    #expect(model.addresses[0].displayName == "Hemma")
    #expect(model.addresses[0].isPrimary)
    #expect(model.addresses[0].notificationsOn)
    // Den gamla adressens notiser är borta, och den nya har inget schema än.
    #expect(scheduler.planned.isEmpty)
    #expect(!model.replace(key, with: new))
}

@Test @MainActor func missadPaminnelseVisasBaraMedNotiserPa() async throws {
    let temp = TempDir()
    // Fredag 6 nov 19:00, och schemat har tömning lördag 7 nov.
    let late = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 19 * 60)
    let scheduler = FakeScheduler(status: .authorized)
    let api = FixedAPI(response: try fixtureResponse(events: ["2026-11-07"]))
    let model = AppModel(api: api, store: LocalStore(directory: temp.url), now: { late }, scheduler: scheduler)
    model.add(hit())
    await model.refreshAll(manual: false)
    await model.settleReminders()
    #expect(model.missedReminderText == nil)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(model.missedReminderText == "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
    // Passerad tid skickar ingen ersättningsnotis.
    #expect(!scheduler.planned.contains { $0.pickupDate == DayDate("2026-11-07")! })
}

@Test @MainActor func andradTidErsatterNotiserna() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    #expect(!before.isEmpty)

    #expect(model.setReminderMinutes(20 * 60 + 15))
    await model.settleReminders()
    let after = scheduler.planned
    #expect(after.map(\.identifier) == before.map(\.identifier))
    #expect(zip(before, after).allSatisfy { $1.fireDate.timeIntervalSince($0.fireDate) == 2 * 3600 + 15 * 60 })
    #expect(LocalStore(directory: temp.url).settings().reminderMinutes == 20 * 60 + 15)
}

@Test @MainActor func ogiltigTidSparasInte() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .authorized), directory: temp.url)
    #expect(!model.setReminderMinutes(14 * 60 + 45))
    #expect(!model.setReminderMinutes(23 * 60 + 15))
    #expect(!model.setReminderMinutes(17 * 60 + 5))
    #expect(model.settings.reminderMinutes == 1080)
}

@Test @MainActor func sparfelPaTidenLamnarVardetOchVisarFel() async throws {
    let blocked = TempDir()
    try Data().write(to: blocked.url)
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: blocked.url), now: { now }, scheduler: FakeScheduler(status: .authorized))
    #expect(!model.setReminderMinutes(19 * 60))
    #expect(model.settings.reminderMinutes == 1080)
    #expect(model.lastStorageError != nil)
}

@Test @MainActor func valetForLiveActivitySparasOchNotisenStarKvarUtanSystemetsAktiviteter() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned

    model.setLiveActivity(true)
    await model.settleReminders()
    #expect(model.settings.liveActivityOn)
    #expect(LocalStore(directory: temp.url).settings().liveActivityOn)
    // Här finns inga aktiviteter hos systemet, så notiserna står kvar.
    #expect(scheduler.planned == before)
}

@Test @MainActor func nyttNamnUppdaterarVantandeNotiser() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(scheduler.planned.allSatisfy { $0.body.hasPrefix("Hemma:") })

    #expect(model.rename(key, to: " Stugan "))
    await model.settleReminders()
    #expect(model.addresses[0].displayName == "Stugan")
    #expect(scheduler.planned.allSatisfy { $0.body.hasPrefix("Stugan:") })
    #expect(!model.rename(key, to: "   "))
    #expect(model.addresses[0].displayName == "Stugan")
}

@Test @MainActor func borttagenAdressTarBortSinaNotiser() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(!scheduler.planned.isEmpty)

    model.remove(key)
    await model.settleReminders()
    #expect(scheduler.planned.isEmpty)
}

@Test @MainActor func nyHuvudadressSparas() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .authorized), directory: temp.url)
    var second = hit()
    second = SearchHit(id: "2", street: "Storgatan 2", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil, url: second.url)
    model.add(second)
    let other = AddressKey(source: "orebro", id: "2")
    model.setPrimary(other)
    #expect(model.addresses.first(where: \.isPrimary)?.key == other)
    #expect(LocalStore(directory: temp.url).addresses().first(where: \.isPrimary)?.key == other)
    // Byte av huvudadress ändrar inga väntande notiser, eftersom de gäller per adress.
}

@Test @MainActor func trycketMedIndragetTillstandRorInteValetOchNotiserna() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    #expect(before.count > 1)

    scheduler.setStatus(.denied)
    model.applyReminders()
    await model.settleReminders()
    // Ett tryck på reglaget medan tillståndet är indraget ändrar ingenting, och ingen ny fråga ställs.
    #expect(await model.setNotifications(true, for: key) == .denied)
    await model.settleReminders()
    #expect(scheduler.requests == 0)
    #expect(model.addresses[0].notificationsOn)
    #expect(LocalStore(directory: temp.url).addresses()[0].notificationsOn)
    #expect(scheduler.planned == before)

    scheduler.setStatus(.authorized)
    model.applyReminders()
    await model.settleReminders()
    #expect(scheduler.planned == before)
    #expect(scheduler.cancelled.isEmpty)
    #expect(model.remindersOn(for: model.addresses[0]))
}

@Test @MainActor func skadadAdressfilGerEgetLageDarForsokIgenLaserOm() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    let file = temp.url.appendingPathComponent("addresses.json")
    let good = try Data(contentsOf: file)
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.storageProblem == .addressesUnreadable)
    restarted.retryStorage()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == .addressesUnreadable)
    #expect(try Data(contentsOf: file) == Data("skräp".utf8))

    try good.write(to: file)
    restarted.retryStorage()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == nil)
    #expect(restarted.addresses.count == 1)
    #expect(scheduler.planned == before)
}

@Test @MainActor func borjaOmFlyttarSkadadFilTarBortEgnaNotiserOchLaterAnvandarenLaggaTill() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(!scheduler.planned.isEmpty)
    let file = temp.url.appendingPathComponent("addresses.json")
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.storageProblem == .addressesUnreadable)
    await restarted.startOver()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == nil)
    #expect(restarted.addresses.isEmpty)
    // Den skadade filen finns kvar åt sidan, och den ursprungliga platsen är ledig.
    let files = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
    let aside = try #require(files.first { $0.hasPrefix("addresses.json.skadad-") })
    #expect(try Data(contentsOf: temp.url.appendingPathComponent(aside)) == Data("skräp".utf8))
    #expect(!FileManager.default.fileExists(atPath: file.path))
    // Appens notiser är borta, främmande notiser rördes inte.
    #expect(scheduler.planned.isEmpty)
    #expect(!scheduler.cancelled.contains(scheduler.foreign))
    // Nu går det att lägga till en adress igen.
    #expect(restarted.add(hit()))
    #expect(restarted.addresses.count == 1)
}

@Test @MainActor func borjaOmMedSkadadeInstallningarAnvanderStandardOchBehallerAdresserna() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    #expect(model.setReminderMinutes(19 * 60))
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let file = temp.url.appendingPathComponent("settings.json")
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.storageProblem == .settingsUnreadable)
    await restarted.startOver()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == nil)
    #expect(restarted.settings == ReminderSettings())
    #expect(restarted.addresses.count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: temp.url.path).contains { $0.hasPrefix("settings.json.skadad-") })
    #expect(restarted.setReminderMinutes(20 * 60))
}

@Test @MainActor func borjaOmFlyttarInteEnFilSomRepareratsSedanFlaggan() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    let file = temp.url.appendingPathComponent("addresses.json")
    let good = try Data(contentsOf: file)
    try Data("skräp".utf8).write(to: file)

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.storageProblem == .addressesUnreadable)
    // Filen blir läsbar igen, men appen har inte läst om den. Börja om läser om först och flyttar inget.
    try good.write(to: file)
    await restarted.startOver()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == nil)
    #expect(restarted.addresses.count == 1)
    #expect(try Data(contentsOf: file) == good)
    #expect(!(try FileManager.default.contentsOfDirectory(atPath: temp.url.path)).contains { $0.contains(".skadad-") })
    #expect(scheduler.planned == before)
    #expect(scheduler.cancelled.isEmpty)
}

@Test @MainActor func tillfalligtOtillgangligFilFlyttasAldrigAvBorjaOm() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    let before = scheduler.planned
    let file = temp.url.appendingPathComponent("addresses.json")
    let good = try Data(contentsOf: file)
    // Filen finns och är hel men går inte att läsa just nu, som skyddad data före upplåsning.
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

    let restarted = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(restarted.storageProblem == .addressesUnavailable)
    await restarted.startOver()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == .addressesUnavailable)
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(!(try FileManager.default.contentsOfDirectory(atPath: temp.url.path)).contains { $0.contains(".skadad-") })
    #expect(scheduler.planned == before)
    #expect(scheduler.cancelled.isEmpty)

    // Efter upplåsning går det att läsa, och allt är kvar.
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    restarted.retryStorage()
    await restarted.settleReminders()
    #expect(restarted.storageProblem == nil)
    #expect(restarted.addresses.count == 1)
    #expect(try Data(contentsOf: file) == good)
}

// MARK: Förslaget om påminnelse

@Test @MainActor func forslagetVisasEfterForstaAdressen() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .notDetermined), directory: temp.url)
    #expect(model.showsReminderOffer)
}

@Test @MainActor func forslagetVisasInteUtanAdress() async throws {
    let temp = TempDir()
    let model = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: FakeScheduler(status: .notDetermined))
    #expect(!model.showsReminderOffer)
}

@Test @MainActor func forslagetForsvinnerNarPaminnelsenSlasPaOchKommerInteTillbaka() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .notDetermined), directory: temp.url)
    #expect(await model.setNotifications(true, for: key) == .granted)
    #expect(!model.showsReminderOffer)
    _ = await model.setNotifications(false, for: key)
    #expect(!model.showsReminderOffer, "Förslaget visas bara en gång")
}

@Test @MainActor func inteNuDoljerForslagetAvenEfterOmstart() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .notDetermined)
    let model = try await makeModel(scheduler, directory: temp.url)
    model.dismissReminderOffer()
    #expect(!model.showsReminderOffer)
    #expect(scheduler.requests == 0, "Inte nu frågar aldrig om tillstånd")
    let again = AppModel(api: FixedAPI(response: try fixtureResponse()), store: LocalStore(directory: temp.url), now: { now }, scheduler: scheduler)
    #expect(!again.showsReminderOffer)
}

@Test @MainActor func forslagetVisasInteNarNotiserArNekade() async throws {
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .denied), directory: temp.url)
    #expect(!model.showsReminderOffer)
}

@Test @MainActor func forslagetVisasInteUtanKommandeHamtning() async throws {
    // Huvudkortet har bara reglaget för påminnelsen när en hämtning kommer. Utan det kan förslaget inte visa vad som hände.
    let temp = TempDir()
    let model = AppModel(api: FixedAPI(response: try fixtureResponse(events: ["2026-11-02"])), store: LocalStore(directory: temp.url), now: { now }, scheduler: FakeScheduler(status: .notDetermined))
    model.add(hit())
    await model.refreshAll(manual: false)
    await model.settleReminders()
    #expect(!model.showsReminderOffer)
}

@Test @MainActor func paslagenPaminnelseGerIngetFelNarForslagetInteKanSparas() async throws {
    // Påminnelsen är sparad även om inställningsfilen inte går att skriva. Då ska inget fel säga att inget ändrats.
    let temp = TempDir()
    let model = try await makeModel(FakeScheduler(status: .notDetermined), directory: temp.url)
    try? FileManager.default.removeItem(at: temp.url.appendingPathComponent("settings.json"))
    try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("settings.json"), withIntermediateDirectories: true)
    #expect(await model.setNotifications(true, for: key) == .granted)
    #expect(model.addresses[0].notificationsOn)
    #expect(model.lastStorageError == nil)
    #expect(!model.showsReminderOffer)
}
