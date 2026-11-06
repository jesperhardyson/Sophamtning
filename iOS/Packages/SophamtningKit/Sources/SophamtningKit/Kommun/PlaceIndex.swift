import Foundation

/// Ortlistan: kommuner och orter som pekar på kommunkoder. Uppslagstabellerna byggs en gång i `init`.
public struct PlaceIndex: Sendable {
    struct Place: Sendable {
        /// Ortens stavning i listan.
        let name: String
        let codes: [String]
    }

    /// Orten eller orterna som en söktext pekar ut.
    struct PlaceMatch {
        /// Stavningen från listan. Vid flera stavningar den första.
        let name: String
        let codes: [String]
        /// Sant när flera stavningar slagits ihop (Alby och Älby).
        let mergedSpellings: Bool
    }

    private struct Suggestion: Sendable {
        let key: String
        let name: String
        let length: Int
    }

    private struct FileFormat: Decodable {
        let kommuner: [String: String]
        let orter: [String: [String]]
    }

    private let kommuner: [String: String]
    /// Normaliserad kommunstam till kommunkoder i kodordning.
    private let kommunerByStem: [String: [String]]
    /// Normaliserat ortnamn till orter, i bokstavsordning.
    private let placesByKey: [String: [Place]]
    /// Orter och kommuner för förslag, kortast först och sedan i bokstavsordning.
    private let suggestionList: [Suggestion]

    public init(kommuner: [String: String], orter: [String: [String]]) {
        self.kommuner = kommuner

        var stems: [String: [String]] = [:]
        for (code, name) in kommuner.sorted(by: { $0.key < $1.key }) {
            stems[Self.kommunStem(name), default: []].append(code)
        }
        kommunerByStem = stems

        var byKey: [String: [Place]] = [:]
        var all: [Suggestion] = []
        for (name, codes) in orter {
            byKey[Self.normalize(name), default: []].append(Place(name: name, codes: codes))
            all.append(Suggestion(key: Self.normalize(name), name: name, length: name.count))
        }
        let places = byKey.mapValues { $0.sorted { $0.name < $1.name } }
        placesByKey = places

        // Kommunens namn som stam utan "kommun" och "Region". Genitiv-s tas bara bort när resten är en ort
        // (Stockholms -> Stockholm, men Alingsås förblir Alingsås).
        var seen = Set(all.map(\.name))
        for name in kommuner.values {
            var display = Self.stripKommunWords(name)
            if display.count > 1, display.lowercased().hasSuffix("s") {
                let shorter = String(display.dropLast())
                if places[Self.normalize(shorter)] != nil { display = shorter }
            }
            if seen.insert(display).inserted {
                all.append(Suggestion(key: Self.normalize(display), name: display, length: display.count))
            }
        }
        suggestionList = all.sorted {
            $0.length != $1.length ? $0.length < $1.length : $0.name < $1.name
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

    private static func caseFolded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Namnet utan inledande "Region " och avslutande " kommun", med bevarat skiftläge.
    static func stripKommunWords(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("region ") { s.removeFirst("region ".count) }
        if s.lowercased().hasSuffix(" kommun") { s.removeLast(" kommun".count) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Stammen utan "Region", "kommun" och avslutande s (genitiv), utan skiftläge men med diakritiska tecken.
    private static func stemKeepingDiacritics(_ text: String) -> String {
        let s = caseFolded(stripKommunWords(text))
        if s.count > 1, s.hasSuffix("s") { return String(s.dropLast()) }
        return s
    }

    /// Som `stemKeepingDiacritics`, men också utan diakritiska tecken.
    static func kommunStem(_ text: String) -> String {
        normalize(stemKeepingDiacritics(text))
    }

    /// Sant när söktexten har å, ä, ö eller annat diakritiskt tecken, så att stavningen är ett val.
    private static func hasDiacritics(_ text: String) -> Bool {
        caseFolded(text) != normalize(text)
    }

    // MARK: Uppslag

    var kommunCount: Int { kommuner.count }
    var placeCount: Int { placesByKey.values.reduce(0) { $0 + $1.count } }

    func kommunName(_ code: String) -> String? { kommuner[code] }

    /// Kommunerna som söktexten pekar ut med namn, med eller utan "kommun", "Region" och genitiv-s.
    /// Har söktexten diakritiska tecken och någon stavning stämmer exakt gäller bara de.
    /// Annars gäller alla med samma namn utan diakritiska tecken (Habo och Håbo).
    func kommunCodes(matching query: String) -> [String] {
        let codes = kommunerByStem[Self.kommunStem(query)] ?? []
        guard codes.count > 1, Self.hasDiacritics(query) else { return codes }
        let wanted = Self.stemKeepingDiacritics(query)
        let exact = codes.filter { Self.stemKeepingDiacritics(kommuner[$0] ?? "") == wanted }
        return exact.isEmpty ? codes : exact
    }

    /// Orten eller orterna som söktexten pekar ut. Samma regel för stavning som för kommuner.
    func place(matching query: String) -> PlaceMatch? {
        guard let candidates = placesByKey[Self.normalize(query)] else { return nil }
        var chosen = candidates
        if candidates.count > 1, Self.hasDiacritics(query) {
            let wanted = Self.caseFolded(query)
            let exact = candidates.filter { Self.caseFolded($0.name) == wanted }
            if !exact.isEmpty { chosen = exact }
        }
        var codes: [String] = []
        for code in chosen.flatMap(\.codes) where !codes.contains(code) { codes.append(code) }
        return PlaceMatch(name: chosen[0].name, codes: codes, mergedSpellings: chosen.count > 1)
    }

    /// Orter och kommuner som börjar med söktexten, kortast först.
    func suggestions(prefix query: String, limit: Int) -> [String] {
        let key = Self.normalize(query)
        var result: [String] = []
        for entry in suggestionList where entry.key.hasPrefix(key) {
            result.append(entry.name)
            if result.count == limit { break }
        }
        return result
    }
}
