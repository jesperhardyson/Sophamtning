import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-live-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Händelser i ordning, gemensam för notiser och aktiviteter, så att testerna kan se vad som kom först.
private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var all: [String] { lock.withLock { items } }
    func clear() { lock.withLock { items = [] } }
}

private final class FakeNotifications: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: PlannedNotification] = [:]
    private var status: NotificationAuthorization
    let log: Log
    init(log: Log, status: NotificationAuthorization = .authorized) { self.log = log; self.status = status }
    func authorization() async -> NotificationAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool { lock.withLock { status == .authorized } }
    func pending() async -> [PendingNotification] {
        lock.withLock { store.values.map { PendingNotification(identifier: $0.identifier, fireDate: $0.fireDate, body: $0.body) } }
    }
    func schedule(_ notifications: [PlannedNotification]) async -> [String] {
        lock.withLock { for n in notifications { store[n.identifier] = n } }
        for n in notifications { log.add("notis+ \(n.pickupDate.iso)") }
        return []
    }
    func cancel(identifiers: [String]) async {
        lock.withLock { for id in identifiers { store[id] = nil } }
        for id in identifiers { log.add("notis- \(id.suffix(10))") }
    }
    var dates: [String] { lock.withLock { store.values.map(\.pickupDate.iso).sorted() } }
}

private struct StartFailed: Error {}

/// Systemets aktiviteter i minnet.
private final class FakeActivities: LiveActivityScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [SystemActivity] = []
    private var counter = 0
    private var failing = false
    private var enabled: Bool
    private(set) var starts: [PlannedLiveActivity] = []
    private(set) var updates: [String] = []
    let log: Log

    init(log: Log, enabled: Bool = true) { self.log = log; self.enabled = enabled }

    func areEnabled() async -> Bool { lock.withLock { enabled } }
    func current() async -> [SystemActivity] { lock.withLock { list } }
    func start(_ activity: PlannedLiveActivity) async throws {
        try lock.withLock {
            if failing { throw StartFailed() }
            counter += 1
            starts.append(activity)
            list.append(SystemActivity(
                activity: ExistingActivity(id: "a\(counter)", key: activity.key, pickupDate: activity.pickupDate, content: activity.content, isPending: !activity.startsImmediately, start: activity.start),
                phase: activity.startsImmediately ? .active : .pending
            ))
        }
        log.add("start \(activity.pickupDate.iso)")
    }
    func update(id: String, content: PickupActivityContent) async {
        lock.withLock {
            updates.append(id)
            list = list.map { item in
                guard item.activity.id == id else { return item }
                let a = item.activity
                return SystemActivity(activity: ExistingActivity(id: a.id, key: a.key, pickupDate: a.pickupDate, content: content, isPending: a.isPending, start: a.start), phase: item.phase)
            }
        }
        log.add("update \(id)")
    }
    func remove(id: String) async {
        lock.withLock { list.removeAll { $0.activity.id == id } }
        log.add("remove \(id)")
    }

    func setFailing(_ on: Bool) { lock.withLock { failing = on } }
    func setEnabled(_ on: Bool) { lock.withLock { enabled = on } }
    func insert(_ item: SystemActivity) { lock.withLock { list.append(item) } }
    func clearAll() { lock.withLock { list = [] } }
    /// Systemet startar den väntande aktiviteten.
    func promote() {
        lock.withLock {
            list = list.map { item in
                let a = item.activity
                return SystemActivity(activity: ExistingActivity(id: a.id, key: a.key, pickupDate: a.pickupDate, content: a.content, isPending: false, start: a.start), phase: .active)
            }
        }
    }
    var ids: [String] { lock.withLock { list.map(\.activity.id) } }
    var activities: [ExistingActivity] { lock.withLock { list.map(\.activity) } }
}

private let homeKey = AddressKey(source: "orebro", id: "1")
private let otherKey = AddressKey(source: "orebro", id: "2")
private let monday = DayDate("2026-11-09")!
private let thursday = DayDate("2026-11-12")!
/// Fredag 6 november 12:00. Tömning måndag 9 och torsdag 12 november.
private let friday = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)
private let sundayEvening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)

private func response(_ key: AddressKey, _ dates: [DayDate], warning: String? = nil) -> AddressResponse {
    AddressResponse(
        today: DayDate("2026-11-06")!,
        address: Address(id: key.id, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", source: key.source, detail: nil, selection: "address", notice: nil),
        next: [], summary: "",
        events: dates.map { PickupEvent(date: $0, fractions: ["rest"], estimated: false, deviation: nil, warning: warning, labels: [:]) },
        bins: [],
        fractions: ["rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")],
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: DayDate("2026-11-06")!
    )
}

private func saved(_ key: AddressKey, name: String, primary: Bool, notifications: Bool = true) -> SavedAddress {
    SavedAddress(key: key, url: URL(string: "https://example.com/\(key.id)")!, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", detail: nil, selection: "address", displayName: name, isPrimary: primary, notificationsOn: notifications, addedAt: Date(timeIntervalSince1970: 0))
}

private struct UnusedAPI: SoporAPI {
    func address(url: URL) async throws -> AddressResponse { throw APIError.network }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

/// Två adresser med sparade scheman och sparade val. Testerna styr tiden med `clock`.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var now: Date { lock.withLock { value } }
    func set(_ date: Date) { lock.withLock { value = date } }
}

private struct Fixture {
    let temp = TempDir()
    let log = Log()
    let notifications: FakeNotifications
    let activities: FakeActivities
    let clock: Clock
    let store: LocalStore

    init(now: Date = friday, liveOn: Bool = true, systemEnabled: Bool = true, notificationStatus: NotificationAuthorization = .authorized, dates: [DayDate] = [monday, thursday], writeHomeSchedule: Bool = true) throws {
        clock = Clock(now)
        notifications = FakeNotifications(log: log, status: notificationStatus)
        activities = FakeActivities(log: log, enabled: systemEnabled)
        store = LocalStore(directory: temp.url)
        try store.setAddresses([saved(homeKey, name: "Hemma", primary: true), saved(otherKey, name: "Stugan", primary: false, notifications: false)])
        if writeHomeSchedule {
            try store.setSchedule(CachedSchedule(response: response(homeKey, dates), fetchedAt: now), for: homeKey)
        }
        try store.setSchedule(CachedSchedule(response: response(otherKey, [thursday]), fetchedAt: now), for: otherKey)
        try store.setSettings(ReminderSettings(reminderMinutes: 1080, liveActivityOn: liveOn))
    }

    @MainActor func model() -> AppModel {
        let clock = clock
        return AppModel(api: UnusedAPI(), store: store, now: { clock.now }, scheduler: notifications, activities: activities)
    }
}

@MainActor private func apply(_ model: AppModel, startingActivities: Bool = true) async {
    model.applyReminders(startingActivities: startingActivities)
    await model.settleReminders()
}

// MARK: Opt-in

@Test @MainActor func ingetSchemalaggsForranValetArPa() async throws {
    let f = try Fixture(liveOn: false)
    await apply(f.model())
    #expect(f.activities.starts.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
}

@Test @MainActor func valetPaStartarOchTarBortNotisenForTomningen() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    #expect(f.activities.starts.first?.startsImmediately == false)
    #expect(f.notifications.dates == ["2026-11-12"])
    #expect(model.currentLiveActivity?.pickupDate == monday)
    #expect(model.liveActivityError == nil)
}

@Test @MainActor func ordningenMedAppenOppen() async throws {
    let f = try Fixture(liveOn: false)
    let model = f.model()
    await apply(model)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    f.log.clear()
    model.setLiveActivity(true)
    await model.settleReminders()
    // Notisen tas bort först när aktiviteten faktiskt finns.
    #expect(f.log.all == ["start 2026-11-09", "notis- 2026-11-09"])
}

@Test @MainActor func misslyckadStartLamnarNotisenKvar() async throws {
    let f = try Fixture(liveOn: false)
    let model = f.model()
    await apply(model)
    f.activities.setFailing(true)
    f.log.clear()
    model.setLiveActivity(true)
    await model.settleReminders()
    #expect(f.activities.starts.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(!f.log.all.contains("notis- 2026-11-09"))
    #expect(model.liveActivityError != nil)
    #expect(model.currentLiveActivity == nil)
    // Nästa försök lyckas, och felet försvinner.
    f.activities.setFailing(false)
    await apply(model)
    #expect(f.activities.starts.count == 1)
    #expect(f.notifications.dates == ["2026-11-12"])
    #expect(model.liveActivityError == nil)
}

@Test @MainActor func samkorningGerIngenDubbelstart() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.log.clear()
    await apply(model)
    #expect(f.activities.starts.count == 1)
    #expect(f.log.all.isEmpty)
}

// MARK: Lägen

@Test @MainActor func avslutadeAktiviteterRaknasInte() async throws {
    for phase in [LiveActivityPhase.ended, .dismissed, .stale] {
        let f = try Fixture(liveOn: true)
        // Aktiviteten för måndag finns i listan men gäller inte längre. Notisen får inte försvinna tyst.
        f.activities.setFailing(true)
        f.activities.insert(SystemActivity(activity: ExistingActivity(id: "x", key: homeKey, pickupDate: monday, content: PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [], estimated: false, warning: nil), isPending: false, start: friday), phase: phase))
        let model = f.model()
        await apply(model)
        #expect(f.notifications.dates.contains("2026-11-09"), "\(phase)")
        #expect(model.currentLiveActivity == nil, "\(phase)")
        // Bara en inaktuell aktivitet behöver tas bort, en avslutad är redan borta.
        #expect(f.log.all.contains("remove x") == (phase == .stale), "\(phase)")
    }
}

// MARK: Valet av

@Test @MainActor func avstangtValLaggerInNotisenForeBorttagningen() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    f.log.clear()
    model.setLiveActivity(false)
    await model.settleReminders()
    let log = f.log.all
    let added = try #require(log.firstIndex(of: "notis+ 2026-11-09"))
    let removed = try #require(log.firstIndex(of: "remove \(id)"))
    #expect(added < removed)
    #expect(f.activities.ids.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(model.currentLiveActivity == nil)
}

@Test @MainActor func avstangtValTarBortPagaendeForIDag() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.promote()
    f.clock.set(StockholmClock.date(on: monday, minutes: 8 * 60))
    await apply(model)
    #expect(f.activities.ids.count == 2) // Dagens lever kvar, och nästa är schemalagd.
    model.setLiveActivity(false)
    await model.settleReminders()
    #expect(f.activities.ids.isEmpty)
}

@Test @MainActor func bytHuvudadressTarBortPagaendeOchLaggerInNotisForst() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.promote()
    #expect(f.activities.activities.first?.key == homeKey)
    f.log.clear()
    model.setPrimary(otherKey)
    await model.settleReminders()
    #expect(!f.activities.activities.contains { $0.key == homeKey })
    #expect(f.activities.activities.contains { $0.key == otherKey })
}

// MARK: Bakgrund

@Test @MainActor func bakgrundenStartarAldrigOchLaggerNotisen() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model, startingActivities: false)
    #expect(f.activities.starts.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
}

@Test @MainActor func bakgrundenFarTaBortOchUppdatera() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.promote()
    let id = try #require(f.activities.ids.first)
    // Ny varning från källan: en pågående aktivitet uppdateras även i bakgrunden.
    try f.store.setSchedule(CachedSchedule(response: response(homeKey, [monday, thursday], warning: "Helgdag"), fetchedAt: sundayEvening), for: homeKey)
    let background = f.model()
    await apply(background, startingActivities: false)
    #expect(f.activities.updates == [id])
    // Tömningen försvinner ur schemat: aktiviteten tas bort, ingen ny startas och notisen för nästa tömning läggs in.
    try f.store.setSchedule(CachedSchedule(response: response(homeKey, [thursday]), fetchedAt: sundayEvening), for: homeKey)
    let later = f.model()
    await apply(later, startingActivities: false)
    #expect(f.activities.ids.isEmpty)
    #expect(f.activities.starts.count == 1)
    #expect(f.notifications.dates == ["2026-11-12"])
}

@Test @MainActor func bakgrundenBehandlarBefintligAktivitetSomBefintlig() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.notifications.dates == ["2026-11-12"])
    let background = f.model()
    await apply(background, startingActivities: false)
    #expect(f.notifications.dates == ["2026-11-12"])
    #expect(f.activities.starts.count == 1)
}

@Test @MainActor func bakgrundskorningenStartarAldrig() async throws {
    let f = try Fixture()
    let model = f.model()
    let run = BackgroundRefreshRun(model: model, reloadWidgets: {}, scheduleNext: {}, complete: { _ in })
    run.start()
    await run.waitUntilFinished()
    await model.settleReminders()
    #expect(f.activities.starts.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
}

// MARK: Utställt

@Test @MainActor func utstalltStartasInteIgen() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.first?.startsImmediately == true)
    // Knappen trycks: posten sparas och aktiviteten avslutas utanför appens process.
    try LocalStore(directory: f.temp.url).markPlacedOut(PlacedOut(key: homeKey, date: monday), today: DayDate("2026-11-08")!)
    f.activities.clearAll()
    await apply(model)
    // Nästa tömning schemaläggs, och den utställda startas inte igen.
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
    #expect(!f.notifications.dates.contains("2026-11-09"))
}

@Test @MainActor func gamlaPosterRensasVidPlanering() async throws {
    let f = try Fixture()
    try f.store.setPlacedOut([PlacedOut(key: homeKey, date: DayDate("2026-11-01")!), PlacedOut(key: homeKey, date: monday)])
    await apply(f.model())
    #expect(f.store.placedOut() == [PlacedOut(key: homeKey, date: monday)])
}

// MARK: Dagens aktivitet

@Test @MainActor func dagensAktivitetLeverKvarNarNastaPlaneras() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.promote()
    let id = try #require(f.activities.ids.first)
    f.clock.set(StockholmClock.date(on: monday, minutes: 8 * 60))
    await apply(model)
    #expect(f.activities.ids.first == id)
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
    // Pågående visas före den väntande.
    #expect(model.currentLiveActivity?.id == id)
}

// MARK: Systemets val

@Test @MainActor func avstangtIIosBehallerValetOchNotisen() async throws {
    let f = try Fixture(systemEnabled: false)
    let model = f.model()
    await apply(model)
    #expect(model.liveActivitiesEnabled == false)
    #expect(model.settings.liveActivityOn)
    #expect(f.activities.starts.isEmpty)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    // Slås det på igen och appen blir aktiv tas notisen över av aktiviteten.
    f.activities.setEnabled(true)
    await apply(model)
    #expect(model.liveActivitiesEnabled)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    #expect(f.notifications.dates == ["2026-11-12"])
}

@Test @MainActor func avstangtIIosNarAktivitetVantarLaggerInNotisen() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.activities.setEnabled(false)
    f.log.clear()
    await apply(model)
    let log = f.log.all
    let added = try #require(log.firstIndex(of: "notis+ 2026-11-09"))
    let removed = try #require(log.firstIndex { $0.hasPrefix("remove") })
    #expect(added < removed)
    #expect(f.notifications.dates.contains("2026-11-09"))
}

@Test @MainActor func nekadeNotiserHindrarInteAktiviteten() async throws {
    let f = try Fixture(notificationStatus: .denied)
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    #expect(f.notifications.dates.isEmpty)
}

// MARK: Läsbarhet

@Test @MainActor func olasbartSchemaTarInteBortAktiviteten() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    // Schemat går inte att läsa. Då finns inget att planera en ny påminnelse från, och aktiviteten får inte försvinna.
    try f.store.removeSchedule(for: homeKey)
    let reopened = f.model()
    await apply(reopened)
    #expect(f.activities.ids == [id])
}

@Test @MainActor func olasbaraInstallningarRorInteAktiviteter() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    try Data("inte json".utf8).write(to: f.temp.url.appendingPathComponent("settings.json"))
    let broken = f.model()
    await apply(broken)
    #expect(f.activities.ids == [id])
}
