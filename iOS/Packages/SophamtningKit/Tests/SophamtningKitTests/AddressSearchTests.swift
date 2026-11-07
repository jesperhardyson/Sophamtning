import Foundation
import Testing
@testable import SophamtningKit

private func hit(_ id: String, kommun: String = "Avesta kommun", selection: String = "address") -> SearchHit {
    SearchHit(id: id, street: "Gata \(id)", locality: "", kommun: kommun, source: "avesta", detail: nil, selection: selection,
              notice: nil, areasUrl: nil, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/\(id)")!)
}

private let avestaAreas = [hit("trakt-1", selection: "area"), hit("trakt-2", selection: "area")]

/// Stubbe där `/sok` och `/omraden` svarar var för sig. Anropen till `/omraden` sparas i ordning.
private final class SearchAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _places: [String] = []
    var places: [String] { lock.withLock { _places } }

    let onSearch: @Sendable (String) async throws -> SearchResponse
    let onAreas: @Sendable (String) async throws -> SearchResponse

    init(search: @escaping @Sendable (String) async throws -> SearchResponse,
         areas: @escaping @Sendable (String) async throws -> SearchResponse) {
        onSearch = search
        onAreas = areas
    }

    func search(query: String, source: String?) async throws -> SearchResponse { try await onSearch(query) }
    func areas(place: String) async throws -> SearchResponse {
        lock.withLock { _places.append(place) }
        return try await onAreas(place)
    }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { fatalError() }
    func address(url: URL) async throws -> AddressResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

private func empty() -> SearchResponse { SearchResponse(addresses: [], failed: []) }

@MainActor private final class Deliveries {
    var all: [SearchOutcome] = []
}

@MainActor private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@Suite struct AreaLookupTests {
    @Test func kandidaternaFragasIOrdningTillsNagonGerOmraden() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { place in
            place == "Avesta" ? SearchResponse(addresses: avestaAreas, failed: []) : empty()
        })
        let result = try await AreaLookup.run(query: "Bergslagsgatan Avesta", api: api)
        #expect(result == .found(place: "Avesta", areas: avestaAreas))
        #expect(api.places == ["Bergslagsgatan Avesta", "Avesta"])
    }

    @Test func forstaTraffenAvslutar() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in SearchResponse(addresses: avestaAreas, failed: []) })
        _ = try await AreaLookup.run(query: "Bergslagsgatan Avesta", api: api)
        #expect(api.places == ["Bergslagsgatan Avesta"])
    }

    @Test func hogstTreAnrop() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in empty() })
        let result = try await AreaLookup.run(candidates: ["a1", "a2", "a3", "a4"], api: api)
        #expect(result == .notFound)
        #expect(api.places == ["a1", "a2", "a3"])
    }

    @Test func utanKandidaterGorsIngetAnrop() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in SearchResponse(addresses: avestaAreas, failed: []) })
        #expect(try await AreaLookup.run(query: "Storgatan 3", api: api) == .notFound)
        #expect(api.places.isEmpty)
    }

    @Test func felGerFailedAldrigNotFound() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in throw APIError.network })
        #expect(try await AreaLookup.run(query: "Bergslagsgatan Avesta", api: api) == .failed)
        #expect(api.places == ["Bergslagsgatan Avesta", "Avesta"])
    }

    @Test func kallaSomInteSvaradeGerFailed() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in SearchResponse(addresses: [], failed: ["avesta"]) })
        #expect(try await AreaLookup.run(query: "Avesta", api: api) == .failed)
    }

    @Test func felForEnKandidatHindrarInteNasta() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { place in
            if place == "Avesta" { return SearchResponse(addresses: avestaAreas, failed: []) }
            throw APIError.network
        })
        #expect(try await AreaLookup.run(query: "Bergslagsgatan Avesta", api: api) == .found(place: "Avesta", areas: avestaAreas))
    }

    @Test func badRequestBetyderIngaOmradenForKandidaten() async throws {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in throw APIError.badRequest })
        #expect(try await AreaLookup.run(query: "Avesta", api: api) == .notFound)
    }
}

@MainActor @Suite struct AddressSearchTests {
    @Test func adressernaVantarInteFororadena() async {
        let gate = AsyncStream<Void>.makeStream()
        let addresses = [hit("1")]
        let api = SearchAPI(search: { _ in SearchResponse(addresses: addresses, failed: []) }, areas: { _ in
            for await _ in gate.stream { break }
            return SearchResponse(addresses: avestaAreas, failed: [])
        })
        let got = Deliveries()
        let run = Task {
            await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: LatestOnly(), areaLookups: LatestOnly()) {
                got.all.append($0)
            }
        }
        #expect(await eventually { got.all.count == 1 })
        #expect(got.all.first == SearchOutcome(state: .results(hits: addresses, failed: []), areas: nil))
        gate.continuation.yield()
        await run.value
        #expect(got.all.last == SearchOutcome(state: .results(hits: addresses, failed: []),
                                             areas: .found(place: "Avesta", areas: avestaAreas)))
        #expect(got.all.count == 2)
    }

    @Test func nollTraffarVantarPaOmradena() async {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in SearchResponse(addresses: avestaAreas, failed: []) })
        let got = Deliveries()
        await AddressSearch.run(query: "Bergslagsgatan Avesta", source: nil, api: api, searches: LatestOnly(),
                                areaLookups: LatestOnly()) { got.all.append($0) }
        #expect(got.all == [SearchOutcome(state: .noHits(place: nil), areas: .found(place: "Bergslagsgatan Avesta", areas: avestaAreas))])
    }

    @Test func avbrottVisarInteOmradena() async {
        let gate = AsyncStream<Void>.makeStream()
        let api = SearchAPI(search: { _ in SearchResponse(addresses: [hit("1")], failed: []) }, areas: { _ in
            for await _ in gate.stream { break }
            return SearchResponse(addresses: avestaAreas, failed: [])
        })
        let got = Deliveries()
        let run = Task {
            await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: LatestOnly(), areaLookups: LatestOnly()) {
                got.all.append($0)
            }
        }
        #expect(await eventually { got.all.count == 1 })
        run.cancel()
        gate.continuation.yield()
        await run.value
        #expect(got.all.count == 1)
        #expect(got.all.first?.areas == nil)
    }

    @Test func gammaltOmradessvarVisasInteEfterNyareSokning() async {
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let api = SearchAPI(search: { _ in SearchResponse(addresses: [hit("1")], failed: []) }, areas: { place in
            if place == "Avesta" {
                started.continuation.yield()
                for await _ in gate.stream { break }
            }
            return SearchResponse(addresses: avestaAreas, failed: [])
        })
        let searches = LatestOnly(), lookups = LatestOnly()
        let old = Deliveries(), new = Deliveries()
        let first = Task {
            await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: searches, areaLookups: lookups) {
                old.all.append($0)
            }
        }
        for await _ in started.stream { break }
        await AddressSearch.run(query: "Säter", source: nil, api: api, searches: searches, areaLookups: lookups) {
            new.all.append($0)
        }
        gate.continuation.yield()
        await first.value
        #expect(old.all.allSatisfy { $0.areas == nil })
        #expect(new.all.last?.areas == .found(place: "Säter", areas: avestaAreas))
    }

    @Test func felIOmradenaMedAdresserGerAdresserna() async {
        let addresses = [hit("1")]
        let api = SearchAPI(search: { _ in SearchResponse(addresses: addresses, failed: []) }, areas: { _ in throw APIError.network })
        let got = Deliveries()
        await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: LatestOnly(), areaLookups: LatestOnly()) {
            got.all.append($0)
        }
        #expect(got.all == [SearchOutcome(state: .results(hits: addresses, failed: []), areas: nil),
                            SearchOutcome(state: .results(hits: addresses, failed: []), areas: .failed)])
    }

    @Test func felIOmradenaVidNollTraffarGerFailed() async {
        let api = SearchAPI(search: { _ in empty() }, areas: { _ in throw APIError.network })
        let got = Deliveries()
        await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: LatestOnly(), areaLookups: LatestOnly()) {
            got.all.append($0)
        }
        #expect(got.all == [SearchOutcome(state: .noHits(place: nil), areas: .failed)])
    }

    @Test func sokfelVisasDirekt() async {
        let api = SearchAPI(search: { _ in throw APIError.sourceUnavailable }, areas: { _ in SearchResponse(addresses: avestaAreas, failed: []) })
        let got = Deliveries()
        await AddressSearch.run(query: "Avesta", source: nil, api: api, searches: LatestOnly(), areaLookups: LatestOnly()) {
            got.all.append($0)
        }
        #expect(got.all == [SearchOutcome(state: .failed(.sourceUnavailable), areas: nil)])
    }
}

@Test func omradenFoljerMedSinaKallor() async throws {
    let sources = [AreaSource(id: "avesta", name: "Avesta Vatten och Avfall", explanation: "Förklaring.", help: "Hjälp.")]
    let api = SearchAPI(search: { _ in empty() }, areas: { place in
        place == "Avesta" ? SearchResponse(addresses: avestaAreas, failed: [], sources: sources) : empty()
    })
    let result = try await AreaLookup.run(query: "okänd gata 1, Avesta", api: api)
    #expect(result == .found(place: "Avesta", areas: avestaAreas, sources: sources))
}
