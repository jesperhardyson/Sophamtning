#if DEBUG
import Foundation
import SophamtningKit

/// Stubben som UI-testerna startar appen med (`-uitest`). Den svarar med kopior av testdata ur `UITestData/`
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
        try Self.load("uitest-adress")
    }

    func sources() async throws -> SourcesResponse {
        let all: SourcesResponse = try Self.load("uitest-kallor")
        return SourcesResponse(sources: all.sources.filter { !$0.testData }, fractions: all.fractions)
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
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") }

    /// En tom lagring i en egen katalog, så att varje testkörning börjar från noll och inget delas med riktig data.
    static func freshStore() -> LocalStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-store", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return LocalStore(directory: directory)
    }
}
#endif
