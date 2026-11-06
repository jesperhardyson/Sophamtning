import Foundation

/// Vad adressökningen visar.
public enum SearchState: Equatable, Sendable {
    case idle
    case searching
    /// Träffar, och källor som inte svarade.
    case results(hits: [SearchHit], failed: [String])
    /// Inga träffar och minst en källa svarade inte. Det betyder inte att adressen saknas.
    case sourcesFailed([String])
    /// Inga träffar och inga fel. `place` är orten i söktexten, om någon angetts.
    case noHits(place: String?)
    case failed(APIError)

    public static func from(_ response: SearchResponse, query: String) -> SearchState {
        if !response.addresses.isEmpty {
            return .results(hits: response.addresses, failed: response.failed)
        }
        if !response.failed.isEmpty {
            return .sourcesFailed(response.failed)
        }
        return .noHits(place: place(in: query))
    }

    /// Orten i söktexten: texten efter kommatecknet, annars texten efter husnumret (och en bokstav efter numret).
    public static func place(in query: String) -> String? {
        if let comma = query.firstIndex(of: ",") {
            return nonEmpty(words(query[query.index(after: comma)...]))
        }
        var tokens = query.split(whereSeparator: \.isWhitespace)
        guard let numberIndex = tokens.firstIndex(where: { $0.first?.isNumber == true }) else { return nil }
        tokens.removeSubrange(...numberIndex)
        // Husnummer som "12 B": en ensam bokstav efter numret hör till numret.
        if let first = tokens.first, first.count == 1, first.first?.isLetter == true {
            tokens.removeFirst()
        }
        return nonEmpty(tokens.joined(separator: " "))
    }

    private static func words(_ text: Substring) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}
