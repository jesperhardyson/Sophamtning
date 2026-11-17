import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-kallmeddelanden-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Ett API vars meddelanden går att byta mellan hämtningarna.
private final class MessagesAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private let base: AddressResponse
    private var current: [SourceMessage]
    init(base: AddressResponse, messages: [SourceMessage]) { self.base = base; current = messages }
    func setMessages(_ messages: [SourceMessage]) { lock.withLock { current = messages } }
    func address(url: URL) async throws -> AddressResponse {
        let messages = lock.withLock { current }
        return AddressResponse(today: base.today, address: base.address, next: base.next, summary: base.summary, events: base.events, bins: base.bins,
                               fractions: base.fractions, links: base.links, updatedAt: base.updatedAt, schedule: base.schedule, messages: messages)
    }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

/// Ett notiscenter som minns notiserna som visats direkt.
private final class DeliveringScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var status: NotificationAuthorization
    private var shown: [(id: String, title: String, body: String)] = []
    private(set) var requests = 0
    init(status: NotificationAuthorization) { self.status = status }
    var delivered: [(id: String, title: String, body: String)] { lock.withLock { shown } }
    func authorization() async -> NotificationAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool { lock.withLock { requests += 1 }; return false }
    func pending() async -> [PendingNotification] { [] }
    func schedule(_ notifications: [PlannedNotification]) async -> [String] { [] }
    func cancel(identifiers: [String]) async {}
    func deliverNow(identifier: String, title: String, body: String) async { lock.withLock { shown.append((identifier, title, body)) } }
}

/// Fredag 20 november 2026 12:00 svensk tid.
private let now = StockholmClock.date(on: DayDate("2026-11-20")!, minutes: 12 * 60)
/// En timme och lite till senare, så att `RefreshPolicy` hämtar igen.
private let later = now.addingTimeInterval(3700)

private let rutter = SourceMessage(id: "nya-rutter-2026", title: "Hämtrutterna läggs om", text: "Schemat kan bli fel.", url: nil,
                                   validFrom: DayDate("2026-11-17")!, validTo: DayDate("2027-03-31")!)

private func base() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private func hit(_ id: String, source: String = "avesta") -> SearchHit {
    SearchHit(id: id, street: "Storgatan \(id)", locality: "Avesta", kommun: "Avesta", source: source, detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/\(source)/\(id)")!)
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = now
    var date: Date { lock.withLock { value } }
    func set(_ new: Date) { lock.withLock { value = new } }
}

@MainActor
private struct Setup {
    let model: AppModel
    let api: MessagesAPI
    let scheduler: DeliveringScheduler
    let clock: Clock
    let store: LocalStore
}

@MainActor
private func setup(_ temp: TempDir, status: NotificationAuthorization = .authorized, messages: [SourceMessage] = [rutter], hits: [SearchHit] = [hit("1")]) throws -> Setup {
    let api = MessagesAPI(base: try base(), messages: messages)
    let scheduler = DeliveringScheduler(status: status)
    let clock = Clock()
    let store = LocalStore(directory: temp.url)
    let model = AppModel(api: api, store: store, now: { clock.date }, scheduler: scheduler)
    for h in hits { model.add(h) }
    return Setup(model: model, api: api, scheduler: scheduler, clock: clock, store: store)
}

@Test @MainActor func nyttIForgrundenVisarKortetUtanNotis() async throws {
    let temp = TempDir()
    let s = try setup(temp)
    await s.model.refreshAll(manual: false)
    #expect(s.model.visibleSourceMessages.map(\.message.id) == ["nya-rutter-2026"])
    #expect(s.scheduler.delivered.isEmpty)
    // Räknas som sett: en senare bakgrundskörning ger ingen notis.
    s.clock.set(later)
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.isEmpty)
    #expect(s.scheduler.requests == 0)
}

@Test @MainActor func nyttIBakgrundenGerEnNotisEnGang() async throws {
    let temp = TempDir()
    let s = try setup(temp, messages: [])
    await s.model.refreshAll(manual: false)
    s.api.setMessages([rutter])
    s.clock.set(later)
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.map(\.id) == ["kalla.avesta.nya-rutter-2026"])
    #expect(s.scheduler.delivered.first?.body == "Hämtrutterna läggs om")
    // Utan källistan är rubriken appens namn.
    #expect(s.scheduler.delivered.first?.title == "Sophämtning")
    // Kortet visas också.
    #expect(s.model.visibleSourceMessages.count == 1)
    s.clock.set(later.addingTimeInterval(3700))
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.count == 1)
}

@Test @MainActor func notisensRubrikArKallansNamn() async throws {
    let temp = TempDir()
    let s = try setup(temp)
    let source = Source(id: "avesta", name: "Avesta Vatten och Avfall", url: URL(string: "https://www.avestavatten.se")!, kommuner: [], testData: false)
    try s.store.setSources(CachedSources(response: SourcesResponse(sources: [source], fractions: [:]), fetchedAt: now))
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.first?.title == "Avesta Vatten och Avfall")
    #expect(s.model.sourceName(for: "avesta") == "Avesta Vatten och Avfall")
    #expect(s.model.sourceName(for: "sater") == nil)
}

@Test @MainActor func tvaAdresserHosSammaKallaGerEnNotis() async throws {
    let temp = TempDir()
    let s = try setup(temp, hits: [hit("1"), hit("2")])
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.count == 1)
    #expect(s.model.visibleSourceMessages.count == 1)
}

@Test @MainActor func reglagetAvGerIngenNotisMenRaknasSomSett() async throws {
    let temp = TempDir()
    let s = try setup(temp)
    #expect(s.model.setSourceMessages(false))
    #expect(!s.model.settings.sourceMessagesOn)
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.isEmpty)
    #expect(s.model.visibleSourceMessages.count == 1)
    // Slås reglaget på igen kommer ingen notis i efterhand.
    #expect(s.model.setSourceMessages(true))
    s.clock.set(later)
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.isEmpty)
}

@Test @MainActor func nekadeNotiserGerIngenNotisOchIngenFraga() async throws {
    for status in [NotificationAuthorization.denied, .notDetermined] {
        let temp = TempDir()
        let s = try setup(temp, status: status)
        await s.model.refreshAll(manual: false, context: .background)
        #expect(s.scheduler.delivered.isEmpty)
        #expect(s.scheduler.requests == 0)
    }
}

@Test @MainActor func oslasligtMinneGerIngenNotisOchSkrivsInteOver() async throws {
    let temp = TempDir()
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    let file = temp.url.appendingPathComponent("source-messages.json")
    try Data("{trasig".utf8).write(to: file)
    let s = try setup(temp)
    await s.model.refreshAll(manual: false, context: .background)
    #expect(s.scheduler.delivered.isEmpty)
    #expect(try Data(contentsOf: file) == Data("{trasig".utf8))
    // Korten visas ändå.
    #expect(s.model.visibleSourceMessages.count == 1)
}

@Test @MainActor func stangtKortVisasInteMenAndraStarKvar() async throws {
    let temp = TempDir()
    let other = SourceMessage(id: "helgdagar", title: "Helgdagar", text: "Ändrade dagar.", url: nil, validFrom: DayDate("2026-11-01")!, validTo: DayDate("2026-12-31")!)
    let s = try setup(temp, messages: [rutter, other])
    await s.model.refreshAll(manual: false)
    #expect(s.model.visibleSourceMessages.map(\.message.id) == ["helgdagar", "nya-rutter-2026"])
    let first = try #require(s.model.visibleSourceMessages.first)
    s.model.dismissSourceMessage(first)
    #expect(s.model.visibleSourceMessages.map(\.message.id) == ["nya-rutter-2026"])
    // Minnet sparas: en ny modell från samma lagring visar inte det stängda.
    let again = AppModel(api: s.api, store: LocalStore(directory: temp.url), now: { now })
    #expect(again.visibleSourceMessages.map(\.message.id) == ["nya-rutter-2026"])
}

@Test @MainActor func utgangetMeddelandeISparatSvarVisasInte() async throws {
    let temp = TempDir()
    let s = try setup(temp)
    await s.model.refreshAll(manual: false)
    let afterEnd = StockholmClock.date(on: DayDate("2027-04-01")!, minutes: 12 * 60)
    let model = AppModel(api: s.api, store: LocalStore(directory: temp.url), now: { afterEnd })
    #expect(model.visibleSourceMessages.isEmpty)
}

@Test @MainActor func bakgrundskorningenRaknasSomBakgrund() async throws {
    let temp = TempDir()
    let s = try setup(temp)
    let run = BackgroundRefreshRun(model: s.model, reloadWidgets: {}, scheduleNext: {}, complete: { _ in })
    run.start()
    await run.waitUntilFinished()
    #expect(s.scheduler.delivered.map(\.id) == ["kalla.avesta.nya-rutter-2026"])
}
