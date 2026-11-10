import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-background-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Ett API som dröjer, så att en körning hinner få sin tid ute innan svaret kommer.
private final class SlowAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let delay: Duration
    private let response: AddressResponse
    init(response: AddressResponse, delay: Duration) { self.response = response; self.delay = delay }
    var callCount: Int { lock.withLock { calls } }
    func address(url: URL) async throws -> AddressResponse {
        lock.withLock { calls += 1 }
        try await Task.sleep(for: delay)
        return response
    }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

/// Ett notiscenter som räknar hur ofta planeraren läser tillståndet, alltså hur ofta `applyReminders` körs.
private final class CountingScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var authorizationReads: Int { lock.withLock { reads } }
    func authorization() async -> NotificationAuthorization { lock.withLock { reads += 1 }; return .denied }
    func requestAuthorization() async -> Bool { false }
    func pending() async -> [PendingNotification] { [] }
    func schedule(_ notifications: [PlannedNotification]) async -> [String] { [] }
    func cancel(identifiers: [String]) async {}
    func deliverNow(identifier: String, title: String, body: String) async {}
}

@MainActor
private final class Recorder {
    var scheduled = 0
    var reloaded = 0
    var completions: [Bool] = []
    var order: [String] = []
}

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

private func response() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private func hit() -> SearchHit {
    SearchHit(id: "1", street: "Storgatan 1", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!)
}

@MainActor
private func makeRun(api: SlowAPI, scheduler: CountingScheduler, recorder: Recorder, directory: URL) -> (BackgroundRefreshRun, AppModel) {
    let model = AppModel(api: api, store: LocalStore(directory: directory), now: { fixedNow }, scheduler: scheduler)
    model.add(hit())
    let run = BackgroundRefreshRun(
        model: model,
        reloadWidgets: { recorder.reloaded += 1; recorder.order.append("reload") },
        scheduleNext: { recorder.scheduled += 1; recorder.order.append("schedule") },
        complete: { recorder.completions.append($0); recorder.order.append("complete") }
    )
    return (run, model)
}

@Test func nastaKorningFarTidigastOmEnTimme() {
    #expect(BackgroundRefreshRun.identifier == "se.hardyson.sophamtning.refresh")
    #expect(BackgroundRefreshRun.earliestBeginDate(now: fixedNow) == fixedNow.addingTimeInterval(3600))
}

@Test @MainActor func korningenHamtarOmplanerarLaddarOmOchAvslutarEnGang() async throws {
    let temp = TempDir()
    let api = SlowAPI(response: try response(), delay: .milliseconds(10))
    let scheduler = CountingScheduler()
    let recorder = Recorder()
    let (run, model) = makeRun(api: api, scheduler: scheduler, recorder: recorder, directory: temp.url)
    let readsBefore = scheduler.authorizationReads

    run.start()
    await run.waitUntilFinished()
    await model.settleReminders()

    #expect(api.callCount == 1)
    #expect(model.schedule(for: AddressKey(source: "orebro", id: "1"))?.response != nil)
    // `applyReminders` har körts, och inget har startat en Live Activity (planeraren har inga aktiviteter att starta).
    #expect(scheduler.authorizationReads > readsBefore)
    #expect(recorder.completions == [true])
    #expect(recorder.scheduled == 1)
    #expect(recorder.reloaded >= 1)
    // Nästa körning bokas först, så att den finns kvar även om den här avbryts. Widgeten laddas om innan uppgiften avslutas.
    #expect(recorder.order.first == "schedule")
    #expect(recorder.order.last == "complete")
    #expect(recorder.order.dropLast().last == "reload")
}

@Test @MainActor func tidenUteAvslutarMedMisslyckadesOchBaraEnGang() async throws {
    let temp = TempDir()
    let api = SlowAPI(response: try response(), delay: .milliseconds(200))
    let scheduler = CountingScheduler()
    let recorder = Recorder()
    let (run, _) = makeRun(api: api, scheduler: scheduler, recorder: recorder, directory: temp.url)

    run.start()
    run.expire()
    #expect(recorder.completions == [false])
    // Arbetet fortsätter inte att avsluta uppgiften en andra gång när det väl är klart.
    await run.waitUntilFinished()
    try await Task.sleep(for: .milliseconds(400))
    #expect(recorder.completions == [false])
    run.expire()
    #expect(recorder.completions == [false])
}

@Test @MainActor func tidenUteEfterAvslutatAndrarInget() async throws {
    let temp = TempDir()
    let api = SlowAPI(response: try response(), delay: .milliseconds(10))
    let recorder = Recorder()
    let (run, _) = makeRun(api: api, scheduler: CountingScheduler(), recorder: recorder, directory: temp.url)
    run.start()
    await run.waitUntilFinished()
    run.expire()
    #expect(recorder.completions == [true])
}

@Test @MainActor func startaTvaGangerKorBaraEnGang() async throws {
    let temp = TempDir()
    let api = SlowAPI(response: try response(), delay: .milliseconds(10))
    let recorder = Recorder()
    let (run, _) = makeRun(api: api, scheduler: CountingScheduler(), recorder: recorder, directory: temp.url)
    run.start()
    run.start()
    await run.waitUntilFinished()
    #expect(recorder.completions == [true])
    #expect(recorder.scheduled == 1)
    #expect(api.callCount == 1)
}
