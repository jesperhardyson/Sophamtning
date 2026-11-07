import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-refresh-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Ett API som svarar med en förbestämd utgång och räknar anropen.
private final class StubAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private let result: Result<AddressResponse, Error>

    init(_ result: Result<AddressResponse, Error>) { self.result = result }

    var calls: Int { lock.withLock { _calls } }

    func address(url: URL) async throws -> AddressResponse {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

private func response() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let address = SavedAddress.fixture()

private func makeStore() -> (LocalStore, TempDir) {
    let temp = TempDir()
    return (LocalStore(directory: temp.url), temp)
}

@Test func lyckatSvarSparasOchRapporterasSomFetched() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let fresh = try response()
    let api = StubAPI(.success(fresh))
    let outcome = await ScheduleRefresher(api: api, store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .fetched)
    #expect(store.schedule(for: address.key) == CachedSchedule(response: fresh, fetchedAt: now, lastAttemptAt: now, lastError: nil))
}

@Test func lyckatSvarNollstallerFel() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let old = now.addingTimeInterval(-7200)
    try store.setSchedule(CachedSchedule(response: nil, fetchedAt: old, lastAttemptAt: old, lastError: .network), for: address.key)
    let fresh = try response()
    let outcome = await ScheduleRefresher(api: StubAPI(.success(fresh)), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .fetched)
    let saved = try #require(store.schedule(for: address.key))
    #expect(saved.lastError == nil)
    #expect(saved.response == fresh)
    #expect(saved.fetchedAt == now)
}

@Test func misslyckandeBehallerSparatSvar() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let kept = try response()
    let fetched = now.addingTimeInterval(-7200)
    try store.setSchedule(CachedSchedule(response: kept, fetchedAt: fetched, lastAttemptAt: fetched, lastError: nil), for: address.key)
    let outcome = await ScheduleRefresher(api: StubAPI(.failure(APIError.sourceUnavailable)), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .failed(.sourceUnavailable))
    let saved = try #require(store.schedule(for: address.key))
    #expect(saved.response == kept)
    #expect(saved.fetchedAt == fetched)
    #expect(saved.lastAttemptAt == now)
    #expect(saved.lastError == .sourceUnavailable)
}

@Test func notFoundBehallerSvaretOchMarkerarFel() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let kept = try response()
    let fetched = now.addingTimeInterval(-7200)
    try store.setSchedule(CachedSchedule(response: kept, fetchedAt: fetched, lastAttemptAt: fetched), for: address.key)
    let outcome = await ScheduleRefresher(api: StubAPI(.failure(APIError.notFound)), store: store).refresh(address, now: now, manual: true)
    #expect(outcome == .failed(.notFound))
    let saved = try #require(store.schedule(for: address.key))
    #expect(saved.response == kept)
    #expect(saved.lastError == .notFound)
}

@Test func misslyckandeUtanTidigareSchemaSpararForsoket() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let outcome = await ScheduleRefresher(api: StubAPI(.failure(APIError.network)), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .failed(.network))
    #expect(store.schedule(for: address.key) == CachedSchedule(response: nil, fetchedAt: nil, lastAttemptAt: now, lastError: .network))
}

@Test func skippedAnroparInteApiet() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let recent = now.addingTimeInterval(-60)
    let before = CachedSchedule(response: try response(), fetchedAt: recent, lastAttemptAt: recent)
    try store.setSchedule(before, for: address.key)
    let api = StubAPI(.success(try response()))
    let outcome = await ScheduleRefresher(api: api, store: store).refresh(address, now: now, manual: true)
    #expect(outcome == .skipped)
    #expect(api.calls == 0)
    #expect(store.schedule(for: address.key) == before)
}

@Test func avbrutetAnropGerSkippedUtanAttSpara() async throws {
    let (store, temp) = makeStore()
    defer { withExtendedLifetime(temp) {} }
    let before = CachedSchedule(response: try response(), fetchedAt: now.addingTimeInterval(-7200), lastAttemptAt: now.addingTimeInterval(-7200))
    try store.setSchedule(before, for: address.key)
    let outcome = await ScheduleRefresher(api: StubAPI(.failure(CancellationError())), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .skipped)
    #expect(store.schedule(for: address.key) == before)
}

/// Ett LocalStore vars skrivningar alltid misslyckas: katalogen är en fil, så schemamappen kan inte skapas.
private func blockedStore() throws -> (LocalStore, () -> Void) {
    let blocker = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-blockerad-\(UUID().uuidString)")
    try Data().write(to: blocker)
    return (LocalStore(directory: blocker), { try? FileManager.default.removeItem(at: blocker) })
}

@Test func skrivfelGerStorageFailed() async throws {
    let (store, cleanup) = try blockedStore()
    defer { cleanup() }
    let outcome = await ScheduleRefresher(api: StubAPI(.success(try response())), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .storageFailed)
}

@Test func apiFelDarStorageFailedNarForsoketInteGarAttSpara() async throws {
    let (store, cleanup) = try blockedStore()
    defer { cleanup() }
    let outcome = await ScheduleRefresher(api: StubAPI(.failure(APIError.network)), store: store).refresh(address, now: now, manual: false)
    #expect(outcome == .storageFailed)
}
