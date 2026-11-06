import Foundation

public struct KommunRow: Equatable, Sendable {
    public let code: String
    public let name: String
    /// Källan som täcker kommunen, annars `nil`.
    public let sourceId: String?

    public init(code: String, name: String, sourceId: String?) {
        self.code = code
        self.name = name
        self.sourceId = sourceId
    }
}

public enum KommunAnswer: Equatable, Sendable {
    case empty
    case covered(KommunRow, viaPlace: String?)
    case notYet(KommunRow)
    case multiple(place: String, rows: [KommunRow])
    case suggestions([String])
    case unknown
    /// Källistan saknas, så det går inte att säga om kommunen täcks.
    case unavailable
}

/// Svarar på "Finns min kommuns hämtningsschema?".
public enum KommunChecker {
    static let minLength = 2
    static let maxSuggestions = 5

    public static func check(_ query: String, index: PlaceIndex, sources: [Source]?) -> KommunAnswer {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minLength else { return .empty }

        // Kommunnamnet går före orten: "Mora" gäller Mora kommun.
        let kommunCodes = index.kommunCodes(matching: text)
        if !kommunCodes.isEmpty {
            guard let sources else { return .unavailable }
            let rows = rows(for: kommunCodes, index: index, sources: sources)
            if rows.count == 1 { return answer(rows[0], viaPlace: nil) }
            return .multiple(place: text, rows: rows)
        }

        if let place = index.place(matching: text) {
            guard let sources else { return .unavailable }
            let rows = rows(for: place.codes, index: index, sources: sources)
            if rows.count == 1 { return answer(rows[0], viaPlace: place.name) }
            return .multiple(place: place.name, rows: rows)
        }

        let suggestions = index.suggestions(prefix: text, limit: maxSuggestions)
        return suggestions.isEmpty ? .unknown : .suggestions(suggestions)
    }

    private static func answer(_ row: KommunRow, viaPlace: String?) -> KommunAnswer {
        row.sourceId == nil ? .notYet(row) : .covered(row, viaPlace: viaPlace)
    }

    private static func rows(for codes: [String], index: PlaceIndex, sources: [Source]) -> [KommunRow] {
        // Täcker flera källor samma kommun gäller den första i listan.
        var sourceByCode: [String: String] = [:]
        for source in sources {
            for kommun in source.kommuner where sourceByCode[kommun.code] == nil {
                sourceByCode[kommun.code] = source.id
            }
        }
        return codes.sorted().map { code in
            KommunRow(code: code, name: index.kommunName(code) ?? code, sourceId: sourceByCode[code])
        }
    }
}
