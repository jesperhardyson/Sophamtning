import Foundation

/// Ortlistan: kommuner och orter som pekar på kommunkoder. Uppslagstabellerna byggs en gång i `init`.
public struct PlaceIndex: Sendable {
    struct Place: Sendable {
        /// Ortens stavning i listan.
        let name: String
        let codes: [String]
    }

    private struct FileFormat: Decodable {
        let kommuner: [String: String]
        let orter: [String: [String]]
    }

    private let kommuner: [String: String]
    /// Normaliserad kommunstam till kommunkoder. Flera koder bara när stammarna krockar (Habo och Håbo).
    private let kommunerByStem: [String: [String]]
    /// Normaliserat ortnamn till orter. Flera orter bara när stavningarna krockar utan prickar (Alby och Älby).
    private let placesByKey: [String: [Place]]
    /// Alla orter, kortast först och sedan i bokstavsordning, för förslag.
    private let placesByLength: [(key: String, place: Place)]

    public init(kommuner: [String: String], orter: [String: [String]]) {
        self.kommuner = kommuner

        var stems: [String: [String]] = [:]
        for (code, name) in kommuner.sorted(by: { $0.key < $1.key }) {
            stems[Self.kommunStem(name), default: []].append(code)
        }
        kommunerByStem = stems

        var byKey: [String: [Place]] = [:]
        var all: [(key: String, place: Place)] = []
        for (name, codes) in orter {
            let place = Place(name: name, codes: codes)
            let key = Self.normalize(name)
            byKey[key, default: []].append(place)
            all.append((key, place))
        }
        placesByKey = byKey.mapValues { $0.sorted { $0.name < $1.name } }
        placesByLength = all.sorted {
            if $0.place.name.count != $1.place.name.count { return $0.place.name.count < $1.place.name.count }
            return $0.place.name < $1.place.name
        }
    }

    /// Ortlistan som följer med appen. Filen läses och tabellerna byggs bara första gången.
    public static func bundled() throws -> PlaceIndex {
        try cached.get()
    }

    private static let cached: Result<PlaceIndex, any Error> = Result {
        guard let url = Bundle.module.url(forResource: "orter", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try JSONDecoder().decode(FileFormat.self, from: Data(contentsOf: url))
        return PlaceIndex(kommuner: file.kommuner, orter: file.orter)
    }

    // MARK: Normalisering

    /// Skiftläge och diakritiska tecken spelar ingen roll, så å, ä och ö jämförs som a och o.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Namnet utan " kommun" och utan avslutande s (genitiv), normaliserat.
    static func kommunStem(_ text: String) -> String {
        var s = normalize(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.hasSuffix(" kommun") { s.removeLast(" kommun".count) }
        let stem = s.trimmingCharacters(in: .whitespaces)
        if stem.count > 1, stem.hasSuffix("s") { return String(stem.dropLast()) }
        return stem
    }

    // MARK: Uppslag

    var kommunCount: Int { kommuner.count }
    var placeCount: Int { placesByKey.values.reduce(0) { $0 + $1.count } }

    func kommunName(_ code: String) -> String? { kommuner[code] }

    /// Kommunerna som söktexten pekar ut med namn, med eller utan "kommun" och genitiv-s.
    /// Krockar stammarna väljs den vars stavning stämmer med söktexten om en gör det.
    func kommunCodes(matching query: String) -> [String] {
        let codes = kommunerByStem[Self.kommunStem(query)] ?? []
        guard codes.count > 1 else { return codes }
        let exact = codes.filter { code in
            let name = kommuner[code] ?? ""
            return Self.caseFolded(Self.stripKommun(name)) == Self.caseFolded(Self.stripKommun(query))
        }
        return exact.isEmpty ? codes : exact
    }

    /// Orten som söktexten pekar ut, med ortens stavning från listan.
    func place(matching query: String) -> (name: String, codes: [String])? {
        guard let candidates = placesByKey[Self.normalize(query)] else { return nil }
        let wanted = Self.caseFolded(query)
        let place = candidates.first { Self.caseFolded($0.name) == wanted } ?? candidates[0]
        return (place.name, place.codes)
    }

    /// Orter som börjar med söktexten, kortast först.
    func suggestions(prefix query: String, limit: Int) -> [String] {
        let key = Self.normalize(query)
        var result: [String] = []
        for entry in placesByLength where entry.key.hasPrefix(key) {
            result.append(entry.place.name)
            if result.count == limit { break }
        }
        return result
    }

    private static func caseFolded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func stripKommun(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasSuffix(" kommun") { s.removeLast(" kommun".count) }
        if s.count > 1, s.lowercased().hasSuffix("s") { s.removeLast() }
        return s
    }
}
