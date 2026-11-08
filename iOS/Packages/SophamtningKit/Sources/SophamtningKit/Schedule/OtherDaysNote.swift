import Foundation

/// Rutan i adressvyn och i Hela schemat för ett område där vissa gator har en annan hämtdag: rubriken som på webben och
/// raderna från `area.otherDays`. Dag och platser visas inte här, de syns redan i adressens namn och `detail`.
public struct OtherDaysNote: Equatable, Sendable {
    public let heading: String
    /// Raderna ordagrant, utan blanka rader. Aldrig tom.
    public let rows: [String]

    /// Hela rutan som en mening för VoiceOver: rubriken, och sedan raderna, som redan är meningar.
    public var accessibilityLabel: String { heading + ". " + rows.joined(separator: " ") }

    /// `nil` när området saknas, `otherDays` är tom eller bara har blanka rader.
    public static func make(_ area: AreaDetails?) -> OtherDaysNote? {
        let rows = (area?.otherDays ?? []).compactMap { text in text.trimmedNonEmpty }
        guard !rows.isEmpty else { return nil }
        return OtherDaysNote(heading: AreaRowContent.otherDaysHeading, rows: rows)
    }
}
