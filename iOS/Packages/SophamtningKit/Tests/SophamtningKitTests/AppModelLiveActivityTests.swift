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
    func deliverNow(identifier: String, body: String) async {}
    var dates: [String] { lock.withLock { store.values.map(\.pickupDate.iso).sorted() } }
    /// Den väntande notisen för tömningen, om det finns någon.
    func notification(_ iso: String) -> PlannedNotification? { lock.withLock { store.values.first { $0.pickupDate.iso == iso } } }
    /// Sant när notisen är reservnotisen: efter aktivitetens start, med reservens rubrik.
    func isFallback(_ iso: String) -> Bool { notification(iso)?.title == "Har du ställt ut kärlen?" }
}

private struct StartFailed: Error {}

/// Söndag 8 november vid givna minuter efter midnatt, svensk tid.
private func sundayAt(_ minutes: Int) -> Date { StockholmClock.date(on: DayDate("2026-11-08")!, minutes: minutes) }

private func pickupContent(_ name: String = "Hemma") -> PickupActivityContent {
    PickupActivityContent(addressName: name, dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")], estimated: false, warning: nil)
}

/// Systemets aktiviteter i minnet.
private final class FakeActivities: LiveActivityScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [SystemActivity] = []
    private var counter = 0
    private var failing = false
    private var failure: any Error = StartFailed()
    private var enabled: Bool
    /// Systemet listar en aktivitet en stund till efter att appen avslutat den.
    var keepsRemoved = false
    private(set) var starts: [PlannedLiveActivity] = []
    private(set) var updates: [String] = []
    /// Aktiviteter som avslutats med bocken för Utställt.
    private(set) var endedWithPlacedOut: [String] = []
    let log: Log

    init(log: Log, enabled: Bool = true) { self.log = log; self.enabled = enabled }

    func areEnabled() async -> Bool { lock.withLock { enabled } }
    func current() async -> [SystemActivity] { lock.withLock { list } }
    func start(_ activity: PlannedLiveActivity) async throws {
        try lock.withLock {
            if failing { throw failure }
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
        lock.withLock {
            if keepsRemoved {
                list = list.map { $0.activity.id == id ? SystemActivity(activity: $0.activity, phase: .dismissed) : $0 }
            } else {
                list.removeAll { $0.activity.id == id }
            }
        }
        log.add("remove \(id)")
    }
    func end(id: String, showing content: PickupActivityContent) async {
        lock.withLock {
            if content.placedOut { endedWithPlacedOut.append(id) }
            list.removeAll { $0.activity.id == id }
        }
        log.add("end \(id)")
    }

    func setFailing(_ on: Bool, with error: any Error = StartFailed()) { lock.withLock { failing = on; failure = error } }
    /// Användaren sveper bort aktiviteten, eller systemet avslutar den.
    func setPhase(_ phase: LiveActivityPhase, id: String) {
        lock.withLock { list = list.map { $0.activity.id == id ? SystemActivity(activity: $0.activity, phase: phase) : $0 } }
    }
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
/// Fredag 6 november 12:00. Tömning måndag 9 och torsdag 12 november. `sundayEvening` är söndag 8 november 19:00.
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

    init(now: Date = friday, liveOn: Bool = true, systemEnabled: Bool = true, notificationStatus: NotificationAuthorization = .authorized, dates: [DayDate] = [monday, thursday], writeHomeSchedule: Bool = true, homeNotifications: Bool = true) throws {
        clock = Clock(now)
        notifications = FakeNotifications(log: log, status: notificationStatus)
        activities = FakeActivities(log: log, enabled: systemEnabled)
        store = LocalStore(directory: temp.url)
        try store.setAddresses([saved(homeKey, name: "Hemma", primary: true, notifications: homeNotifications), saved(otherKey, name: "Stugan", primary: false, notifications: false)])
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

@Test @MainActor func valetPaStartarOchErsatterNotisenForTomningenMedReserv() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    #expect(f.activities.starts.first?.startsImmediately == false)
    // En enda notis för måndagen, och det är reserven 45 minuter efter starten. Torsdagen har en vanlig.
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60 + 45))
    #expect(!f.notifications.isFallback("2026-11-12"))
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
    // Notisen ersätts av reserven först när aktiviteten faktiskt finns. Samma identifierare, så ingen tas bort.
    #expect(f.log.all == ["start 2026-11-09", "notis+ 2026-11-09"])
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
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
    // Misslyckad `request`: den vanliga notisen på ordinarie tid, inte reserven.
    #expect(!f.notifications.isFallback("2026-11-09"))
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60))
    #expect(model.liveActivityError != nil)
    #expect(model.currentLiveActivity == nil)
    // Nästa försök lyckas, och felet försvinner. Notisen blir reserven.
    f.activities.setFailing(false)
    await apply(model)
    #expect(f.activities.starts.count == 1)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
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
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.activities.promote()
    let id = try #require(f.activities.ids.first)
    f.log.clear()
    model.setPrimary(otherKey)
    await model.settleReminders()
    let log = f.log.all
    let added = try #require(log.firstIndex(of: "notis+ 2026-11-09"))
    let removed = try #require(log.firstIndex(of: "remove \(id)"))
    #expect(added < removed)
    #expect(!f.activities.activities.contains { $0.key == homeKey })
    #expect(f.activities.activities.contains { $0.key == otherKey })
    #expect(f.notifications.dates.contains("2026-11-09"))
}

@Test @MainActor func namnbytePaVantandeErsatterDenMedNyttNamn() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let old = try #require(f.activities.ids.first)
    f.log.clear()
    model.rename(homeKey, to: "Stugan")
    await model.settleReminders()
    #expect(!f.activities.ids.contains(old))
    #expect(f.activities.activities.map(\.content.addressName) == ["Stugan"])
    #expect(f.activities.starts.count == 2)
}

// MARK: Ersätta en väntande

@Test @MainActor func nyStartasForeBorttagningenAvGamla() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let old = try #require(f.activities.ids.first)
    f.log.clear()
    model.rename(homeKey, to: "Stugan")
    await model.settleReminders()
    let log = f.log.all
    let started = try #require(log.firstIndex(of: "start 2026-11-09"))
    let removed = try #require(log.firstIndex(of: "remove \(old)"))
    #expect(started < removed)
}

@Test @MainActor func misslyckadErsattningLamnarDenGamlaKvar() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let old = try #require(f.activities.ids.first)
    f.activities.setFailing(true)
    model.rename(homeKey, to: "Stugan")
    await model.settleReminders()
    #expect(f.activities.ids == [old])
    #expect(model.liveActivityError != nil)
    // Den gamla aviserar, och reserven ligger kvar bakom den.
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
    #expect(model.currentLiveActivity?.id == old)
}

@Test @MainActor func utanForgrundGerStartenIngetFelmeddelande() async throws {
    let f = try Fixture()
    f.activities.setFailing(true, with: LiveActivityNotInForeground())
    let model = f.model()
    await apply(model)
    #expect(model.liveActivityError == nil)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
}

// MARK: Väntande vars start har passerat

/// Söndag 18:10. Aktiviteten för måndag skulle ha startat 18:00, alltså mer än marginalen sedan, och är fortfarande väntande.
/// Reservnotisen 18:45 ligger framåt, så fallet går att se med riktiga tider.
private let sundayPastStart = sundayAt(18 * 60 + 10)

private func overdue(_ f: Fixture) {
    f.activities.insert(SystemActivity(activity: ExistingActivity(id: "gammal", key: homeKey, pickupDate: monday, content: pickupContent(), isPending: true, start: sundayAt(18 * 60)), phase: .pending))
}

@Test @MainActor func passeradVantandeErsattsMedAppenOppen() async throws {
    let f = try Fixture(now: sundayPastStart)
    overdue(f)
    await apply(f.model())
    #expect(!f.activities.ids.contains("gammal"))
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    // Den nya syns direkt, och då behövs ingen reserv för måndagen.
    #expect(f.notifications.notification("2026-11-09") == nil)
}

@Test @MainActor func passeradVantandeTackasAvReservnotisenIBakgrunden() async throws {
    let f = try Fixture(now: sundayPastStart)
    overdue(f)
    let model = f.model()
    await apply(model, startingActivities: false)
    #expect(f.activities.ids == ["gammal"])
    // Den vanliga tiden 18:00 har passerat, och reserven 18:45 är den riktiga notisen.
    #expect(f.notifications.isFallback("2026-11-09"))
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60 + 45))
    // Kortet lovar ingen tid som redan passerat.
    #expect(model.currentLiveActivity == nil)
}

@Test @MainActor func passeradVantandeNarReserventidenOckssaPasseratGerIngenNotis() async throws {
    let f = try Fixture(now: sundayAt(18 * 60 + 50))
    overdue(f)
    await apply(f.model(), startingActivities: false)
    #expect(f.notifications.notification("2026-11-09") == nil)
}

// MARK: Bortsvept

@Test @MainActor func bortsveptStartasInteOmForSammaTomning() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    f.activities.setPhase(.dismissed, id: id)
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
    #expect(model.handledPickup(key: homeKey, date: monday))
}

@Test @MainActor func avslutadOchBortaUrListanStartasInteOmNarDenSetts() async throws {
    // Sedd som pågående av en tidigare körning, och sedan borta utan spår hos systemet.
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.activities.promote()
    await apply(model)
    f.activities.clearAll()
    await apply(f.model())
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
}

@Test @MainActor func direktstartRaknasSomVisad() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.clearAll()
    await apply(f.model())
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
}

@Test @MainActor func utanBevisStartasDenIgen() async throws {
    // Väntande som försvunnit utan att ha setts som pågående: säkra riktningen är att starta.
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.activities.clearAll()
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday, monday])
}

@Test @MainActor func avslutadVantandeForeStarttidenStopparInte() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    f.activities.setPhase(.ended, id: id)
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday, monday])
}

@Test @MainActor func egenBorttagningRaknasInteSomBortsvept() async throws {
    let f = try Fixture(now: sundayEvening)
    f.activities.keepsRemoved = true
    let model = f.model()
    await apply(model)
    model.setLiveActivity(false)
    await model.settleReminders()
    model.setLiveActivity(true)
    await model.settleReminders()
    // Valet stängdes av och på igen. Det är inget svep, så samma tömning startas på nytt.
    #expect(f.activities.starts.map(\.pickupDate) == [monday, monday])
}

@Test @MainActor func bortsveptBehallerNotisenOmDenLiggerFramfor() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.activities.promote()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    f.activities.setPhase(.dismissed, id: id)
    await apply(model)
    // Bara omstarten stoppas. Notisen får aldrig försvinna tyst.
    #expect(f.notifications.dates.contains("2026-11-09"))
}

// MARK: Dagens innehåll

@Test @MainActor func dagensPagaendeFarNyttNamn() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    f.activities.promote()
    let id = try #require(f.activities.ids.first)
    f.clock.set(StockholmClock.date(on: monday, minutes: 8 * 60))
    await apply(model)
    model.rename(homeKey, to: "Stugan")
    await model.settleReminders()
    #expect(f.activities.activities.first { $0.id == id }?.content.addressName == "Stugan")
}

// MARK: Passerad påminnelse

@Test @MainActor func passeradPaminnelseVisasInteNarAktivitetenVisas() async throws {
    let evening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)
    let f = try Fixture(now: evening)
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.first?.startsImmediately == true)
    #expect(model.missedReminderText == nil)
    #expect(model.missedReminderApplies(to: try #require(model.addresses.first { $0.key == homeKey })) == false)
}

@Test @MainActor func passeradPaminnelseVisasInteEfterUtstallt() async throws {
    let evening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)
    let f = try Fixture(now: evening, liveOn: false)
    try f.store.setPlacedOut([PlacedOut(key: homeKey, date: monday)])
    let model = f.model()
    await apply(model)
    #expect(model.missedReminderText == nil)
}

@Test @MainActor func misslyckadDirektstartMedNotiserVisarFelOchPasseradPaminnelse() async throws {
    let f = try Fixture(now: sundayEvening)
    f.activities.setFailing(true)
    let model = f.model()
    await apply(model)
    let home = try #require(model.addresses.first { $0.key == homeKey })
    #expect(f.activities.ids.isEmpty)
    #expect(!f.notifications.dates.contains("2026-11-09"))
    #expect(model.liveActivityError != nil)
    #expect(model.missedReminderText(for: home) != nil)
    let content = HomeContent.make(addresses: model.addresses, schedules: model.cachedSchedules, settings: model.settings, now: model.currentDate, remindersAllowed: true, liveActivity: model.currentLiveActivity, liveActivitiesEnabled: model.liveActivitiesEnabled, liveActivityError: model.liveActivityError, missedReminder: model.missedReminderText(for: home))
    #expect(try #require(content.primary).reminder?.detail == model.liveActivityError)
}

@Test @MainActor func passeradPaminnelseVisasUtanAktivitet() async throws {
    let evening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)
    let f = try Fixture(now: evening, liveOn: false)
    let model = f.model()
    await apply(model)
    #expect(model.missedReminderText != nil)
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
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
    let background = f.model()
    await apply(background, startingActivities: false)
    // Bakgrunden får planera reserven, eftersom den bara är en notis.
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
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

@Test @MainActor func avslutadMenFortfarandeVisadAktivitetOmstartasInteOchRorInteReserven() async throws {
    let f = try Fixture(now: sundayEvening)
    let model = f.model()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    f.activities.promote()
    await apply(model)
    // Utställt trycks: valet sparas, och aktiviteten avslutas men visas med bock i tre sekunder till.
    try f.store.markPlacedOut(PlacedOut(key: homeKey, date: monday), today: DayDate("2026-11-08")!)
    f.activities.setPhase(.ended, id: id)
    f.log.clear()
    for _ in 0..<2 {
        await apply(model)
        await apply(f.model())
    }
    // Den räknas inte som befintlig, startas inte om, tas inte bort eller uppdateras, och ingen reserv läggs tillbaka.
    #expect(model.currentLiveActivity?.pickupDate != monday)
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
    #expect(!f.log.all.contains { $0.hasPrefix("remove") || $0.hasPrefix("update") })
    #expect(!f.log.all.contains { $0.hasPrefix("start \(monday.iso)") })
    #expect(!f.notifications.dates.contains("2026-11-09"))
}

/// Sparandet av Utställt misslyckades (posten finns inte i lagret), men aktiviteten är avslutad och visas med bock en stund till.
@Test @MainActor func utstalltUtanSparadPostStartarInteOmOchReserventFolierBeviset() async throws {
    // Aldrig sedd som visad: reserven ligger kvar, och samma tömning startas inte om.
    let unseen = try Fixture()
    let unseenModel = try await withReserve(unseen)
    let unseenID = try #require(unseen.activities.ids.first)
    unseen.activities.setPhase(.ended, id: unseenID)
    unseen.log.clear()
    for _ in 0..<2 { await apply(unseenModel); await apply(unseen.model()) }
    #expect(unseen.store.placedOut().isEmpty)
    #expect(unseen.activities.starts.map(\.pickupDate) == [monday, thursday])
    #expect(!unseen.log.all.contains { $0.hasPrefix("start \(monday.iso)") })
    reserveKvar(unseen)

    // Sedd som visad innan: den bevisat visade aktiviteten släcker reserven, men startas ändå inte om.
    let seen = try Fixture(now: sundayEvening)
    let seenModel = seen.model()
    await apply(seenModel)
    let seenID = try #require(seen.activities.ids.first)
    seen.activities.promote()
    await apply(seenModel)
    seen.activities.setPhase(.ended, id: seenID)
    seen.log.clear()
    for _ in 0..<2 { await apply(seenModel); await apply(seen.model()) }
    #expect(seen.store.placedOut().isEmpty)
    #expect(!seen.log.all.contains { $0.hasPrefix("start \(monday.iso)") })
    #expect(!seen.notifications.dates.contains("2026-11-09"))
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

// MARK: Reservnotis

@Test @MainActor func reserventasBortNarAktivitetenVisats() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.notifications.isFallback("2026-11-09"))
    // Systemet startar aktiviteten kl. 18:00, och appen ser den vid nästa planering.
    f.clock.set(sundayAt(18 * 60 + 1))
    f.activities.promote()
    await apply(model)
    #expect(f.notifications.dates == ["2026-11-12"])
    #expect(model.handledPickup(key: homeKey, date: monday))
}

@Test @MainActor func reserventKommerInteTillbakaEfterAttAktivitetenSettsPagaende() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    f.clock.set(sundayAt(18 * 60 + 20))
    f.activities.promote()
    await apply(model)
    let id = try #require(f.activities.ids.first)
    // Användaren sveper bort den. Den har visats, och reserven kommer inte tillbaka.
    f.activities.setPhase(.dismissed, id: id)
    await apply(model)
    #expect(f.notifications.notification("2026-11-09") == nil)
}

/// Reserven väntar 18:45. Klockan är sedan 18:10: ordinarie tid 18:00 har passerat, och en ny planering ger ingen vanlig notis.
@MainActor private func withReserve(_ f: Fixture) async throws -> AppModel {
    let model = f.model()
    await apply(model)
    #expect(f.notifications.isFallback("2026-11-09"))
    f.clock.set(sundayAt(18 * 60 + 10))
    return model
}

private func reserveKvar(_ f: Fixture, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(f.notifications.isFallback("2026-11-09"), sourceLocation: sourceLocation)
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60 + 45), sourceLocation: sourceLocation)
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"], sourceLocation: sourceLocation)
}

@Test @MainActor func reserventStarKvarNarAktivitetenForsvunnitIBakgrunden() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    f.activities.clearAll()
    await apply(model, startingActivities: false)
    reserveKvar(f)
    #expect(!f.log.all.contains("notis- 2026-11-09"))
}

@Test @MainActor func reserventStarKvarNarLiveActivityStangsAv() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    await apply(model, startingActivities: false)
    model.setLiveActivity(false)
    await model.settleReminders()
    #expect(f.activities.ids.isEmpty)
    reserveKvar(f)
}

@Test @MainActor func reserventStarKvarNarAktivitetenForsvunnitOchStartenMisslyckas() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    f.activities.clearAll()
    f.activities.setFailing(true)
    await apply(model)
    #expect(f.activities.ids.isEmpty)
    reserveKvar(f)
}

@Test @MainActor func reserventStarKvarNarErsattningenMisslyckasIForgrunden() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    f.activities.setFailing(true)
    await apply(model)
    #expect(f.activities.ids.count == 1)
    reserveKvar(f)
}

@Test @MainActor func ingenNyReservSkapasNarIngenVantar() async throws {
    // Ordinarie tid har passerat och inget väntar: den som inte fick någon notis får ingen reserv heller.
    let f = try Fixture(now: sundayAt(18 * 60 + 10))
    f.activities.setFailing(true)
    await apply(f.model())
    #expect(f.notifications.notification("2026-11-09") == nil)
    #expect(f.notifications.dates == ["2026-11-12"])
}

@Test @MainActor func avstangdaNotiserTarBortReserventAvenEfterOrdinarieTid() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    _ = await model.setNotifications(false, for: homeKey)
    await model.settleReminders()
    #expect(f.notifications.dates.isEmpty)
}

@Test @MainActor func utstalldTarBortReserventAvenEfterOrdinarieTid() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    try f.store.markPlacedOut(PlacedOut(key: homeKey, date: monday), today: DayDate("2026-11-06")!)
    await apply(model)
    #expect(f.notifications.dates == ["2026-11-12"])
}

@Test @MainActor func avslutadUtanBevisStoppasOmstartMenInteReserven() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    let id = try #require(f.activities.ids.first)
    // Systemet har startat och avslutat aktiviteten, men appen har aldrig sett den pågå.
    f.activities.setPhase(.dismissed, id: id)
    await apply(model)
    #expect(f.store.shownActivities().isEmpty)
    #expect(f.store.endedActivities() == [PlacedOut(key: homeKey, date: monday)])
    // Ingen omstart för måndagen, och reserven står kvar.
    #expect(f.activities.starts.map(\.pickupDate) == [monday, thursday])
    reserveKvar(f)
    // Efter en omstart av appen är det fortfarande så.
    await apply(f.model())
    #expect(f.store.shownActivities().isEmpty)
    reserveKvar(f)
}

@Test @MainActor func ersattAktivitetMarkerarInteTomningenSomVisadEfterOmstart() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    f.activities.keepsRemoved = true
    model.rename(homeKey, to: "Stugan")
    await model.settleReminders()
    // Den nya aktiviteten är pågående direkt (starttiden har passerat), och den gamla ligger kvar som avslutad hos systemet.
    await apply(f.model())
    #expect(f.store.shownActivities() == [PlacedOut(key: homeKey, date: monday)])
    f.activities.clearAll()
    try f.store.clearShown()
    await apply(f.model(), startingActivities: false)
    #expect(f.store.shownActivities().isEmpty)
}

@Test @MainActor func hemkortetNamnerReserventNarDenLiggerFramfor() async throws {
    let f = try Fixture()
    let model = try await withReserve(f)
    f.activities.clearAll()
    await apply(model, startingActivities: false)
    let home = try #require(model.addresses.first { $0.key == homeKey })
    #expect(model.reserveNotificationDate(for: home) == sundayAt(18 * 60 + 45))
    // "Påminnelsen har passerat" gäller inte när en reserv ligger framför.
    #expect(model.missedReminderText(for: home) == nil)
    let content = HomeContent.make(addresses: model.addresses, schedules: model.cachedSchedules, settings: model.settings, now: model.currentDate, remindersAllowed: true, liveActivity: nil, liveActivitiesEnabled: true, liveActivityError: nil, missedReminder: nil, reserveAt: model.reserveNotificationDate(for: home))
    #expect(try #require(content.primary).reminder?.detail == "Reservpåminnelse kl. 18:45")
}

@Test @MainActor func utstalltTarBortReserventVidNastaPlanering() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.notifications.isFallback("2026-11-09"))
    try f.store.markPlacedOut(PlacedOut(key: homeKey, date: monday), today: DayDate("2026-11-06")!)
    await apply(model)
    #expect(f.notifications.dates == ["2026-11-12"])
    #expect(f.log.all.contains("notis- 2026-11-09"))
}

@Test @MainActor func bastaLiveActivityUtanNotiserGerIngenNotis() async throws {
    let f = try Fixture(homeNotifications: false)
    let model = f.model()
    await apply(model)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    // Den andra adressen har notiser av, så ingen notis alls.
    #expect(f.notifications.dates.isEmpty)
}

@Test @MainActor func reserventasBortNarNotiserSlasAv() async throws {
    let f = try Fixture()
    let model = f.model()
    await apply(model)
    #expect(f.notifications.isFallback("2026-11-09"))
    _ = await model.setNotifications(false, for: homeKey)
    await model.settleReminders()
    #expect(f.notifications.dates.isEmpty)
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
    // Avstängt i iOS: den vanliga notisen tillbaka på ordinarie tid.
    #expect(!f.notifications.isFallback("2026-11-09"))
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60))
    // Slås det på igen och appen blir aktiv tas notisen över av aktiviteten.
    f.activities.setEnabled(true)
    await apply(model)
    #expect(model.liveActivitiesEnabled)
    #expect(f.activities.starts.map(\.pickupDate) == [monday])
    #expect(f.notifications.dates == ["2026-11-09", "2026-11-12"])
    #expect(f.notifications.isFallback("2026-11-09"))
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
    // Den vanliga notisen ersätter reserven, med samma identifierare.
    #expect(!f.notifications.isFallback("2026-11-09"))
    #expect(f.notifications.notification("2026-11-09")?.fireDate == sundayAt(18 * 60))
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

// MARK: Hushållets bockar

/// Hemma delas med Kim, som har ställt ut kärlen för måndagens tömning.
private func kimHasPlacedOut(_ store: LocalStore, silence: Bool) throws {
    try store.setHouseholdState(HouseholdState(
        role: .member,
        myId: "jag",
        participants: [HouseholdParticipant(id: "jag", name: "Jesper", isOwner: false), HouseholdParticipant(id: "kim", name: "Kim", isOwner: true)],
        addresses: [HouseholdAddress(address: saved(homeKey, name: "Hemma", primary: false), addedBy: "kim")],
        marks: [HouseholdMark(placedOut: PlacedOut(key: homeKey, date: monday), by: "kim", at: sundayEvening, isPending: false)],
        status: .synced
    ))
    try store.setHouseholdPreferences(HouseholdPreferences(silenceWhenOthersPlaceOut: silence))
}

@Test @MainActor func kvallenForeVisarAndrasBockMedTystaAv() async throws {
    let f = try Fixture(now: sundayEvening)
    await apply(f.model())
    let id = try #require(f.activities.ids.first)
    #expect(f.activities.activities.first?.content.placedOut == false)

    // Kim ställer ut. Appen öppnas igen och läser hushållet.
    try kimHasPlacedOut(f.store, silence: false)
    await apply(f.model())

    #expect(f.activities.ids == [id])
    #expect(f.activities.activities.first?.content.placedOut == true)
}

@Test @MainActor func kvallenForeVisarAndrasBockInnanDenForsvinnerMedTystaPa() async throws {
    let f = try Fixture(now: sundayEvening)
    await apply(f.model())
    let id = try #require(f.activities.ids.first)
    f.log.clear()

    try kimHasPlacedOut(f.store, silence: true)
    await apply(f.model())

    // Bocken visas först, som när knappen trycks, och sedan avslutas aktiviteten.
    #expect(f.activities.endedWithPlacedOut == [id])
    #expect(!f.activities.ids.contains(id))
    #expect(f.notifications.notification("2026-11-09") == nil)
}
