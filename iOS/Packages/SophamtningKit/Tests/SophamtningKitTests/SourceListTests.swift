import Foundation
import Testing
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sophamtning-sources-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private final class SourcesAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var result: Result<SourcesResponse, any Error>
    init(_ result: Result<SourcesResponse, any Error>) { self.result = result }
    var callCount: Int { lock.withLock { calls } }
    func sources() async throws -> SourcesResponse {
        lock.withLock { calls += 1 }
        return try result.get()
    }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func address(url: URL) async throws -> AddressResponse { fatalError() }
}

private func list(_ id: String) -> SourcesResponse {
    SourcesResponse(sources: [Source(id: id, name: id, url: URL(string: "https://example.com")!, kommuner: [Kommun(code: "1880", name: "Örebro kommun")], testData: false)], fractions: [:])
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = t0
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

@Suite @MainActor struct SourceListTests {
    @Test func sparadListaUnderEttDygnHamtarInteIgen() async throws {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        try store.setSources(CachedSources(response: list("sparad"), fetchedAt: t0.addingTimeInterval(-3600)))
        let api = SourcesAPI(.success(list("ny")))
        let model = AppModel(api: api, store: store, now: { t0 })
        let sources = await model.sourceList()
        #expect(sources?.first?.id == "sparad")
        #expect(api.callCount == 0)
    }

    @Test func gammalListaHamtasOchSparas() async throws {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        try store.setSources(CachedSources(response: list("sparad"), fetchedAt: t0.addingTimeInterval(-90_000)))
        let api = SourcesAPI(.success(list("ny")))
        let model = AppModel(api: api, store: store, now: { t0 })
        #expect(await model.sourceList()?.first?.id == "ny")
        #expect(store.sources()?.response.sources.first?.id == "ny")
        #expect(store.sources()?.fetchedAt == t0)
        _ = await model.sourceList()
        #expect(api.callCount == 1)
    }

    @Test func saknadListaHamtas() async {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        let api = SourcesAPI(.success(list("ny")))
        let model = AppModel(api: api, store: store, now: { t0 })
        #expect(await model.sourceList()?.first?.id == "ny")
    }

    @Test func sparadListaAnvandsNarHamtningMisslyckas() async throws {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        try store.setSources(CachedSources(response: list("sparad"), fetchedAt: t0.addingTimeInterval(-90_000)))
        let api = SourcesAPI(.failure(APIError.network))
        let model = AppModel(api: api, store: store, now: { t0 })
        #expect(await model.sourceList()?.first?.id == "sparad")
    }

    @Test func inteSparatOchMisslyckadGerNilAldrigTomLista() async {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        let api = SourcesAPI(.failure(APIError.sourceUnavailable))
        let model = AppModel(api: api, store: store, now: { t0 })
        #expect(await model.sourceList() == nil)
        // Ett nytt försök hämtar igen, så att Försök igen fungerar.
        api.result = .success(list("ny"))
        #expect(await model.sourceList()?.first?.id == "ny")
    }

    @Test func avbrottUnderHamtningSatterIngenSparr() async throws {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        try store.setSources(CachedSources(response: list("sparad"), fetchedAt: t0.addingTimeInterval(-90_000)))
        let api = SourcesAPI(.failure(CancellationError()))
        let model = AppModel(api: api, store: store, now: { t0 })
        #expect(await model.sourceList()?.first?.id == "sparad")
        api.result = .success(list("ny"))
        #expect(await model.sourceList()?.first?.id == "ny")
        #expect(api.callCount == 2)
    }

    @Test func misslyckadHamtningUpprepasInteVidVarjeTangent() async throws {
        let temp = TempDir(); let store = LocalStore(directory: temp.url)
        try store.setSources(CachedSources(response: list("sparad"), fetchedAt: t0.addingTimeInterval(-90_000)))
        let clock = Clock()
        let api = SourcesAPI(.failure(APIError.network))
        let model = AppModel(api: api, store: store, now: { clock.now })
        _ = await model.sourceList(); _ = await model.sourceList()
        #expect(api.callCount == 1)
        clock.advance(3700)
        _ = await model.sourceList()
        #expect(api.callCount == 2)
    }
}

@Suite @MainActor struct AddDisplayNameTests {
    private func hit(_ id: String, street: String, selection: String) -> SearchHit {
        SearchHit(id: id, street: street, locality: "", kommun: "Avesta kommun", source: "avesta", detail: nil, selection: selection, notice: nil, areasUrl: nil,
                  url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/\(id)")!)
    }

    @Test func visningsnamn() {
        let temp = TempDir()
        let model = AppModel(api: SourcesAPI(.failure(APIError.network)), store: LocalStore(directory: temp.url), now: { t0 })
        #expect(model.add(hit("1", street: "Kvarnvägen 3", selection: "address")))
        #expect(model.add(hit("2", street: "Skogsbo tätort, Rosse m.fl.", selection: "area")))
        #expect(model.add(hit("3", street: "Storgatan 5", selection: "address")))
        #expect(model.addresses.map(\.displayName) == ["Hemma", "Skogsbo tätort, Rosse m.fl.", "Storgatan 5"])
    }
}

@Suite @MainActor struct AddFailureTests {
    @Test func misslyckatSparandeGerFalseOchLamnarListanOforandrad() throws {
        let blocked = TempDir()
        try Data().write(to: blocked.url)
        let model = AppModel(api: SourcesAPI(.failure(APIError.network)), store: LocalStore(directory: blocked.url), now: { t0 })
        let hit = SearchHit(id: "1", street: "Storgatan 1", locality: "Örebro", kommun: "Örebro kommun", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
                            url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/1")!)
        #expect(model.add(hit) == false)
        #expect(model.addresses.isEmpty)
    }
}
