#if DEBUG
import Foundation
import SophamtningKit

/// Stubben som UI-testerna startar appen med (`-uitest` eller `-uitest-intrade`). Den svarar med kopior av testdata ur `UITestData/`
/// och gör aldrig något nätanrop. Filerna och den här koden ingår bara i Debug-bygget.
struct UITestAPI: SoporAPI {
    /// Dagen då testdatat skrevs. Alla datum flyttas så att schemat alltid ligger framåt från i dag.
    private static let recordedDay = DayDate("2026-11-06")!

    func search(query: String, source: String?) async throws -> SearchResponse {
        // Bara "testgatan" ger träffar. Allt annat ger inga träffar och inga fel.
        if query.lowercased().contains("testgatan") { return try Self.load("uitest-sok") }
        return SearchResponse(addresses: [], failed: [])
    }

    func areas(place: String) async throws -> SearchResponse {
        // Områdesval finns bara i Avesta.
        if place.lowercased() == "avesta" { return try Self.load("uitest-omraden") }
        return SearchResponse(addresses: [], failed: [])
    }

    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse {
        try await areas(place: place)
    }

    func address(url: URL) async throws -> AddressResponse {
        // Avesta har ett schema som gäller till ett visst datum. Testgatan är en live-källa utan sådant.
        if url.path.contains("/adress/avesta/") {
            let response: AddressResponse = try Self.load("uitest-adress-avesta")
            return UITestSupport.endsSoon ? Self.endingSoon(response) : response
        }
        return try Self.load("uitest-adress")
    }

    func sources() async throws -> SourcesResponse {
        let all: SourcesResponse = try Self.load("uitest-kallor")
        return SourcesResponse(sources: all.sources.filter { !$0.testData }, fractions: all.fractions)
    }

    /// Samma schema, men med sista dagen 10 dagar fram, så att rutan och raden om att schemat slutar syns.
    private static func endingSoon(_ response: AddressResponse) -> AddressResponse {
        let until = StockholmClock.today(now: Date()).adding(days: 10)
        return AddressResponse(
            today: response.today, address: response.address, next: response.next, summary: response.summary,
            events: response.events, bins: response.bins, fractions: response.fractions, links: response.links,
            updatedAt: response.updatedAt, schedule: SchedulePeriod(until: until, reason: response.schedule?.reason)
        )
    }

    private static func load<Response: Decodable>(_ name: String) throws -> Response {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { throw APIError.unexpected(0) }
        let shift = recordedDay.days(until: StockholmClock.today(now: Date()))
        let shifted = try JSONSerialization.data(withJSONObject: shiftDates(json, by: shift))
        return try JSONDecoder().decode(Response.self, from: shifted)
    }

    private static func shiftDates(_ value: Any, by days: Int) -> Any {
        switch value {
        case let text as String:
            return DayDate(text).map { $0.adding(days: days).iso } ?? text
        case let list as [Any]:
            return list.map { shiftDates($0, by: days) }
        case let object as [String: Any]:
            return object.mapValues { shiftDates($0, by: days) }
        default:
            return value
        }
    }
}

enum UITestSupport {
    /// Som `-uitest`, men inträdet körs och lagringen från förra starten ligger kvar. Paketet känner inte till argumentet,
    /// så i ett Release-bygge gör det ingenting.
    private static let entranceArgument = "-uitest-intrade"

    private static var runsEntrance: Bool { ProcessInfo.processInfo.arguments.contains(entranceArgument) }

    /// `-uitest-schemat-slutar`: Avestas schema gäller bara 10 dagar till.
    static var endsSoon: Bool { ProcessInfo.processInfo.arguments.contains("-uitest-schemat-slutar") }

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") || runsEntrance }

    /// En lagring i en egen katalog, där inget delas med riktig data. Varje testkörning börjar från noll, utom med
    /// `-uitest-intrade`, som startar om appen med det som förra starten sparade.
    static func store() -> LocalStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-store", isDirectory: true)
        if !runsEntrance { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }
}
#endif
