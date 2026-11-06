import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-widget-reload-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private struct StubAPI: SoporAPI {
    let result: Result<AddressResponse, APIError>
    func address(url: URL) async throws -> AddressResponse { try result.get() }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

@MainActor
private final class Counter {
    var count = 0
}

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

private func response() throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private func hit(_ id: String) -> SearchHit {
    SearchHit(id: id, street: "Storgatan \(id)", locality: "Örebro", kommun: "Örebro", source: "orebro", detail: nil, selection: "address", notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/\(id)")!)
}

@MainActor
private func makeModel(_ result: Result<AddressResponse, APIError>, counter: Counter, directory: URL) -> AppModel {
    AppModel(api: StubAPI(result: result), store: LocalStore(directory: directory), now: { fixedNow }, widgetReloader: { counter.count += 1 })
}

@Test @MainActor func sparatSchemaLaddarOmWidgeten() async throws {
    let temp = TempDir()
    let counter = Counter()
    let model = makeModel(.success(try response()), counter: counter, directory: temp.url)
    model.add(hit("1"))
    let afterAdd = counter.count
    await model.refreshAll(manual: false)
    #expect(counter.count > afterAdd)
    // Inom timmen hämtas inget och inget ändras, så widgeten laddas inte om.
    let afterFetch = counter.count
    await model.refreshAll(manual: false)
    #expect(counter.count == afterFetch)
}

@Test @MainActor func misslyckatForsokLaddarOmWidgetenSaAttFeletSyns() async throws {
    let temp = TempDir()
    let counter = Counter()
    let model = makeModel(.failure(.network), counter: counter, directory: temp.url)
    model.add(hit("1"))
    let before = counter.count
    await model.refreshAll(manual: false)
    #expect(counter.count > before)
}

@Test @MainActor func andradHuvudadressOchBorttagningLaddarOmWidgeten() async throws {
    let temp = TempDir()
    let counter = Counter()
    let model = makeModel(.success(try response()), counter: counter, directory: temp.url)
    model.add(hit("1"))
    model.add(hit("2"))
    var before = counter.count
    model.setPrimary(AddressKey(source: "orebro", id: "2"))
    #expect(counter.count == before + 1)
    before = counter.count
    model.remove(AddressKey(source: "orebro", id: "2"))
    #expect(counter.count == before + 1)
}

@Test @MainActor func nyttNamnLaddarOmWidgetenMenOgiltigtNamnGorDetInte() async throws {
    let temp = TempDir()
    let counter = Counter()
    let model = makeModel(.success(try response()), counter: counter, directory: temp.url)
    model.add(hit("1"))
    let before = counter.count
    #expect(model.rename(AddressKey(source: "orebro", id: "1"), to: "") == false)
    #expect(counter.count == before)
    #expect(model.rename(AddressKey(source: "orebro", id: "1"), to: "Stugan"))
    #expect(counter.count == before + 1)
}
