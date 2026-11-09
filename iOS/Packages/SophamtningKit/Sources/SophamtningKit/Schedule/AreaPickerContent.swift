import Foundation

/// Det som områdesvalet visar för en söktext: områdena, varningskortet och raden Hitta område. Under en sökning visas
/// bara träffarna, som i systemets egna sökningar. Ett filter utan träffar säger inget om att något saknas hos källan.
public struct AreaPickerContent: Equatable, Sendable {
    /// Områdena som matchar, i listans ordning. Ett tomt fält visar alla.
    public let hits: [SearchHit]
    /// Varningskortet överst. Det döljs under en sökning och kommer tillbaka när fältet töms.
    public let showsWarning: Bool
    /// Hitta område som listans första rad, ovanför områdena.
    public let showsFinderFirst: Bool
    /// Texten när inget område matchar, "Inga områden matchar ”zzz”.", annars `nil`.
    public let emptyText: String?
    /// Hitta område under texten när inget matchar, som vägen vidare.
    public let showsFinderWhenEmpty: Bool

    /// `hasFinder` är sant när orten är känd, så att Hitta område kan söka i den.
    public static func make(_ hits: [SearchHit], query: String, hasFinder: Bool) -> AreaPickerContent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Samma gräns som filtret: med ett enda tecken visas hela listan, och då står varningen kvar.
        let searching = trimmed.count >= AreaFilter.minimumLength
        let visible = AreaFilter.filter(hits, query: query)
        let empty = visible.isEmpty
        return AreaPickerContent(
            hits: visible,
            showsWarning: !searching,
            showsFinderFirst: !empty && !searching && hasFinder,
            emptyText: empty ? "Inga områden matchar ”\(trimmed)”." : nil,
            showsFinderWhenEmpty: empty && hasFinder
        )
    }
}
