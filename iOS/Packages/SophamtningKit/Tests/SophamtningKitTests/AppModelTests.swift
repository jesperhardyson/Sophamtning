import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-model-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Ett API som räknar anropen per adress och dröjer lite, så att samtidiga anrop hinner överlappa.
private final class CountingAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]
    private let response: AddressResponse

    init(response: AddressResponse) { self.response = response }

    func calls(for url: URL) -> Int { lock.withLock { counts[url, default: 0] } }
    var totalCalls: Int { lock.withLock { counts.values.reduce(0) { $0 + $1 } } }

    func address(url: URL) async throws -> AddressResponse {
        lock.withLock { counts[url, default: 0] += 1 }
        try await Task.sleep(for: .milliseconds(50))
        return response
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

private func hit(_ id: String) -> SearchHit {
    SearchHit(id: id, street: "Storgatan \(id)", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/\(id)")!)
}

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func makeModel(api: any SoporAPI, store: LocalStore) -> AppModel {
    AppModel(api: api, store: store, now: { fixedNow })
}

@Test @MainActor func samtidigaUppdateringarHamtarVarjeAdressEnGang() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let api = CountingAPI(response: try response())
    let model = makeModel(api: api, store: store)
    model.add(hit("1"))
    model.add(hit("2"))

    async let start: Void = model.refreshAll(manual: false)
    async let pull: Void = model.refreshAll(manual: true)
    _ = await (start, pull)

    #expect(api.calls(for: hit("1").url) == 1)
    #expect(api.calls(for: hit("2").url) == 1)
    #expect(model.schedule(for: AddressKey(source: "orebro", id: "1"))?.response != nil)
}

@Test @MainActor func uppdateringarKorAdressernaEnITaget() async throws {
    let temp = TempDir()
    let api = CountingAPI(response: try response())
    let model = makeModel(api: api, store: LocalStore(directory: temp.url))
    model.add(hit("1"))
    model.add(hit("2"))
    await model.refreshAll(manual: false)
    #expect(api.totalCalls == 2)
    // Inom timmen hämtas inget igen.
    await model.refreshAll(manual: true)
    #expect(api.totalCalls == 2)
}

@Test @MainActor func tillagdAdressSparasOchLaddasVidNastaStart() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: store)
    model.add(hit("1"))
    model.add(hit("1"))
    #expect(model.addresses.count == 1)
    #expect(model.addresses[0].isPrimary)
    #expect(store.addresses() == model.addresses)
    let restarted = makeModel(api: CountingAPI(response: try response()), store: store)
    #expect(restarted.addresses == model.addresses)
}

@Test @MainActor func borttagningTarBortAdressOchSparatSchema() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: store)
    model.add(hit("1"))
    model.add(hit("2"))
    await model.refreshAll(manual: false)
    let key = AddressKey(source: "orebro", id: "1")
    #expect(store.schedule(for: key) != nil)

    model.remove(key)
    #expect(model.addresses.map(\.key.id) == ["2"])
    #expect(model.addresses[0].isPrimary)
    #expect(model.schedule(for: key) == nil)
    #expect(store.schedule(for: key) == nil)
    #expect(store.addresses().map(\.key.id) == ["2"])
}

@Test @MainActor func misslyckadSparningBehallerTidigareLageOchVisarFel() async throws {
    // Lagringen går inte att skriva när katalogen i stället är en fil.
    let blocked = TempDir()
    try Data().write(to: blocked.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: LocalStore(directory: blocked.url))
    #expect(model.lastStorageError == nil)
    model.add(hit("1"))
    #expect(model.addresses.isEmpty)
    #expect(model.lastStorageError != nil)
    model.clearStorageError()
    #expect(model.lastStorageError == nil)
}

@Test @MainActor func misslyckadSparningAvForstaSvaretGerFelStalletForHamtar() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: store)
    model.add(hit("1"))
    // En fil där schemakatalogen ska ligga gör att scheman inte går att spara.
    try Data().write(to: temp.url.appendingPathComponent("schedules"))
    await model.refreshAll(manual: false)
    #expect(model.lastStorageError != nil)
    let schedule = try #require(model.schedule(for: AddressKey(source: "orebro", id: "1")))
    #expect(schedule.response == nil)
    #expect(schedule.lastError != nil)
    let content = HomeContent.make(addresses: model.addresses, schedules: model.cachedSchedules, settings: model.settings, now: fixedNow)
    #expect(content.primary?.status != .loading)
}

@Test @MainActor func borttagningUnderPagaendeUppdateringLamnarIngetSchemaKvar() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: store)
    model.add(hit("1"))
    model.add(hit("2"))
    let removed = AddressKey(source: "orebro", id: "1")
    let refresh = Task { await model.refreshAll(manual: false) }
    try await Task.sleep(for: .milliseconds(20))
    model.remove(removed)
    await refresh.value
    #expect(store.schedule(for: removed) == nil)
    #expect(model.schedule(for: removed) == nil)
    #expect(model.addresses.map(\.key.id) == ["2"])
}

@Test @MainActor func misslyckadBorttagningBehallerAdressen() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let model = makeModel(api: CountingAPI(response: try response()), store: store)
    model.add(hit("1"))
    // Gör adressfilen oskrivbar genom att ersätta den med en katalog.
    let file = temp.url.appendingPathComponent("addresses.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file.appendingPathComponent("x"), withIntermediateDirectories: true)

    model.remove(AddressKey(source: "orebro", id: "1"))
    #expect(model.addresses.map(\.key.id) == ["1"])
    #expect(model.lastStorageError != nil)
}
