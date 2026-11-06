import Foundation
import Synchronization
import Testing
@testable import SophamtningKit

/// Delat tillstånd för en stubbad session. Varje test får en egen, så parallella tester stör inte varandra.
final class StubStore: Sendable {
    struct State {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data()
        var error: URLError?
    }

    let id = UUID().uuidString
    let state = Mutex(State())

    var requests: [URLRequest] { state.withLock { $0.requests } }
}

enum StubRegistry {
    static let stores = Mutex<[String: StubStore]>([:])
    static let header = "X-Stub-ID"
}

final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: StubRegistry.header),
              let store = StubRegistry.stores.withLock({ $0[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let snapshot = store.state.withLock { state in
            state.requests.append(request)
            return state
        }
        if let error = snapshot.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: snapshot.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: snapshot.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// En klient bakom en egen stubbad session.
func makeClient(
    status: Int = 200, body: Data = Data(), error: URLError? = nil
) -> (SoporClient, StubStore) {
    let store = StubStore()
    store.state.withLock { $0.status = status; $0.body = body; $0.error = error }
    StubRegistry.stores.withLock { $0[store.id] = store }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    configuration.httpAdditionalHeaders = [StubRegistry.header: store.id]
    return (SoporClient(session: URLSession(configuration: configuration), version: "1.0"), store)
}

func client(fixture: String) throws -> (SoporClient, StubStore) {
    makeClient(body: try fixtureData(fixture))
}

let testURL = URL(string: "https://sopor.hardyson.se/api/v1/adress/uppsala/storgatan-2_uppsala-4004688")!

@Suite struct APIClientTests {
    @Test func avkodarAdressMedOkandaFalt() async throws {
        var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("adress")) as? [String: Any])
        json["framtidaFalt"] = ["a": 1]
        var address = try #require(json["address"] as? [String: Any])
        address["nyttFalt"] = "x"
        json["address"] = address
        let body = try JSONSerialization.data(withJSONObject: json)
        let (client, _) = makeClient(body: body)
        let r = try await client.address(url: testURL)
        #expect(r.address.id == "storgatan-2_uppsala-4004688")
        #expect(r.today == DayDate("2026-11-06"))
        #expect(!r.next.isEmpty)
        #expect(r.fractions["mat"]?.short == "Mat")
        #expect(r.events.first?.deviation == nil)
        #expect(r.links.web.host() == "sopor.hardyson.se")
    }

    @Test func tolAndrasFraktionsId() async throws {
        let (client, _) = try client(fixture: "okand-fraktion")
        let r = try await client.address(url: testURL)
        #expect(r.events.contains { $0.fractions.contains("tradgard") })
        #expect(r.fractions["tradgard"] == nil)
    }

    @Test func behallerUrlMedAaoOchProcent() async throws {
        let (client, store) = try client(fixture: "sok")
        let hit = try #require(try await client.search(query: "storgatan 2", source: nil).addresses
            .first { $0.id == "storgatan-2_kåge-124167" })
        #expect(hit.url.absoluteString.contains("k%C3%A5ge"))
        // anropet går exakt till den sparade adressen, utan dubbel kodning
        let kage = try fixtureData("adress-kage")
        store.state.withLock { $0.body = kage }
        _ = try await client.address(url: hit.url)
        let requested = try #require(store.requests.last?.url)
        #expect(requested.absoluteString == hit.url.absoluteString)
    }

    @Test func delvisSokningBehallerTraffarOchFailed() async throws {
        let (client, _) = try client(fixture: "sok-delvis")
        let r = try await client.search(query: "storgatan 2", source: nil)
        #expect(r.failed == ["uppsala"])
        #expect(!r.addresses.isEmpty)
    }

    @Test(arguments: [(400, APIError.badRequest), (404, .notFound), (502, .sourceUnavailable), (500, .unexpected(500))])
    func statuskoderBlirFel(status: Int, expected: APIError) async {
        let (client, _) = makeClient(status: status, body: Data("{}".utf8))
        await #expect(throws: expected) { try await client.address(url: testURL) }
    }

    @Test func natfelBlirNetwork() async {
        let (client, _) = makeClient(error: URLError(.timedOut))
        await #expect(throws: APIError.network) { try await client.sources() }
    }

    @Test func ogiltigtSvarBlirUnexpected() async {
        let (client, _) = makeClient(body: Data("inte json".utf8))
        await #expect(throws: APIError.unexpected(200)) { try await client.address(url: testURL) }
    }

    @Test func sokningKodarQueryOchSkickarUserAgent() async throws {
        let (client, store) = try client(fixture: "sok")
        _ = try await client.search(query: "storgatan 2, örebro", source: "orebro")
        let request = try #require(store.requests.first)
        #expect(request.url?.absoluteString
            == "https://sopor.hardyson.se/api/v1/sok?q=storgatan%202%2C%20%C3%B6rebro&kalla=orebro")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Sophamtning-iOS/1.0")
        #expect(request.timeoutInterval == 15)
    }

    @Test func sokningUtanKallaSkickarInteKalla() async throws {
        let (client, store) = try client(fixture: "sok")
        _ = try await client.search(query: "a+b", source: nil)
        #expect(store.requests.first?.url?.absoluteString == "https://sopor.hardyson.se/api/v1/sok?q=a%2Bb")
    }

    @Test func saknadSelectionBlirAddress() async throws {
        let body = Data("""
        {"apiVersion":"1","failed":[],"addresses":[{"id":"a_b-1","street":"A","locality":"B",
        "kommun":"C","source":"s","detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a_b-1"}]}
        """.utf8)
        let (client, _) = makeClient(body: body)
        let hit = try #require(try await client.search(query: "a", source: nil).addresses.first)
        #expect(hit.selection == "address")
        #expect(!hit.isArea)
        #expect(hit.notice == nil)
        #expect(hit.areasUrl == nil)
    }

    @Test(arguments: ["\"\"", "\"   \"", "123", "{}", "\"http://exa mple\""])
    func trasigtAreasUrlGerTraffUtanLank(_ value: String) async throws {
        let body = Data("""
        {"apiVersion":"1","failed":[],"addresses":[{"id":"a_b-1","street":"A","locality":"B",
        "kommun":"C","source":"s","detail":null,"areasUrl":\(value),"url":"https://sopor.hardyson.se/api/v1/adress/s/a_b-1"}]}
        """.utf8)
        let (client, _) = makeClient(body: body)
        let hit = try #require(try await client.search(query: "a", source: nil).addresses.first)
        #expect(hit.areasUrl == nil)
    }

    @Test func omradenAvkodasOchArOmraden() async throws {
        let (client, store) = try client(fixture: "omraden")
        let r = try await client.areas(place: "Avesta")
        #expect(r.addresses.allSatisfy { $0.isArea })
        #expect(r.addresses.first?.areasUrl != nil)
        #expect(store.requests.first?.url?.absoluteString == "https://sopor.hardyson.se/api/v1/omraden?plats=Avesta")
    }

    @Test func kallorFiltrerarBortTestdata() async throws {
        var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("kallor")) as? [String: Any])
        var sources = try #require(json["sources"] as? [[String: Any]])
        var test = sources[0]
        test["id"] = "testkalla"
        test["testData"] = true
        sources.append(test)
        json["sources"] = sources
        let (client, _) = makeClient(body: try JSONSerialization.data(withJSONObject: json))
        let r = try await client.sources()
        #expect(!r.sources.isEmpty)
        #expect(!r.sources.contains { $0.id == "testkalla" || $0.testData })
        #expect(r.sources.first?.kommuner.isEmpty == false)
    }

    @Test func avkodarAvvikelseOchKarl() async throws {
        let (client, _) = try client(fixture: "adress-avvikelse")
        let r = try await client.address(url: testURL)
        #expect(r.events[0].deviation == Deviation(originalDate: DayDate("2026-11-10"), reason: "Flyttad på grund av helg"))
        #expect(r.events[1].deviation == Deviation(originalDate: nil, reason: "Julhelgen"))
        #expect(r.events[2].deviation == nil)
        #expect(r.bins.count == 2)
        #expect(r.bins[0] == Bin(fraction: "mat", sizeLiters: 140, pickupsPerYear: 26, frequencyText: "Varannan vecka"))
        #expect(r.bins[1] == Bin(fraction: "karl", sizeLiters: nil, pickupsPerYear: nil, frequencyText: nil))
    }

    @Test(arguments: ["adress", "adress-avvikelse", "adress-kage"])
    func adressHallerRundgang(fixture: String) throws {
        let decoder = JSONDecoder()
        let first = try decoder.decode(AddressResponse.self, from: fixtureData(fixture))
        let again = try decoder.decode(AddressResponse.self, from: JSONEncoder().encode(first))
        #expect(again == first)
    }
}
