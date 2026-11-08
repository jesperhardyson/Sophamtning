import Foundation

/// Sökfältet i områdesvalet. Som på webbens områdessida räcker det att varje sökord är början på ett ord i områdets
/// namn, etikett, dag, platser eller söktermer. Skiftläge och diakritiska tecken spelar ingen roll, utom å, ä och ö,
/// som är egna bokstäver ("ostra" är inte "Östra"). Saknar området detaljer matchar bara namnet.
public enum AreaFilter {
    /// Småord i områdesnamn ("m.fl.", "och", "del av"). De går inte att söka på, annars ger "fl" nästan alla områden.
    private static let fillerWords: Set<String> = ["m", "fl", "och", "del", "av", "om", "by"]

    /// Träffarna i samma ordning som listan. Ett tomt fält ger alla.
    public static func filter(_ hits: [SearchHit], query: String) -> [SearchHit] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return hits }
        // Småord i frågan räknas inte, och en fråga med bara småord ger inga träffar.
        let tokens = normalized.split(separator: " ").map(String.init).filter { token in !fillerWords.contains(token) }
        guard !tokens.isEmpty else { return [] }
        return hits.filter { hit in matches(tokens, hit) }
    }

    private static func matches(_ tokens: [String], _ hit: SearchHit) -> Bool {
        let words = fields(of: hit).flatMap { field in normalize(field).split(separator: " ").map(String.init) }
            .filter { word in !fillerWords.contains(word) }
        return tokens.allSatisfy { token in words.contains { word in word.hasPrefix(token) } }
    }

    private static func fields(of hit: SearchHit) -> [String] {
        guard let area = hit.area else { return [hit.street] }
        return [hit.street, area.label, area.day].compactMap { field in field } + area.places + area.searchTerms
    }

    /// Gemener, ett mellanslag mellan orden och diakriter bort, utom å, ä och ö.
    static func normalize(_ text: String) -> String {
        let kept: [Character: Character] = ["å": "\u{1}", "ä": "\u{2}", "ö": "\u{3}"]
        let restore: [Character: Character] = ["\u{1}": "å", "\u{2}": "ä", "\u{3}": "ö"]
        let lowered = String(text.lowercased().map { character in kept[character] ?? character })
        let stripped = lowered.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { scalar in !CharacterSet.nonBaseCharacters.contains(scalar) }
        let restored = String(String.UnicodeScalarView(stripped)).map { character in restore[character] ?? character }
        return String(restored)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { part in !part.isEmpty }
            .joined(separator: " ")
    }
}
