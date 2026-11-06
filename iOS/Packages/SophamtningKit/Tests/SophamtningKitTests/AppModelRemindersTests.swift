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

/// Ett notiscenter i minnet. Håller också en notis som inte är appens egen, som aldrig ska röras.
private final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var status: NotificationAuthorization
    private let answer: Bool
    private var store: [String: PlannedNotification] = [:]
    private(set) var requests = 0
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
        lock.withLock { store.values.map { PendingNotification(identifier: $0.identifier, fireDate: $0.fireDate, body: $0.body) } }
    }
    func schedule(_ notifications: [PlannedNotification]) async {
        lock.withLock { for n in notifications { store[n.identifier] = n } }
    }
    func cancel(identifiers: [String]) async {
        lock.withLock { for id in identifiers { store[id] = nil } }
    }
    func setStatus(_ new: NotificationAuthorization) { lock.withLock { status = new } }
    var planned: [PlannedNotification] { lock.withLock { store.values.sorted { $0.fireDate < $1.fireDate } } }
}

private let key = AddressKey(source: "orebro", id: "1")
/// Fredag 6 november 2026 12:00 svensk tid. Schemat i fixturen har hämtningar från 11 november.
private let now = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

private func hit() -> SearchHit {
    SearchHit(id: "1", street: "Storgatan 1", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!)
}

private func fixtureResponse() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
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

@Test @MainActor func tillstandSomTagitsBortISystemetStangerAvReglagen() async throws {
    let temp = TempDir()
    let scheduler = FakeScheduler(status: .authorized)
    let model = try await makeModel(scheduler, directory: temp.url)
    _ = await model.setNotifications(true, for: key)
    await model.settleReminders()
    #expect(!scheduler.planned.isEmpty)

    scheduler.setStatus(.denied)
    model.applyReminders()
    await model.settleReminders()
    #expect(model.notificationAuthorization == .denied)
    #expect(model.addresses[0].notificationsOn == false)
    #expect(LocalStore(directory: temp.url).addresses()[0].notificationsOn == false)
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

@Test @MainActor func valetForLiveActivitySparasMenPlanerarInteNagot() async throws {
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
    // Notiserna står kvar tills Live Activity kopplas.
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
}
