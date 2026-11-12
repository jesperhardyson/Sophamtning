import Foundation

/// Texterna i låsskärmens widgetar, räknade från `WidgetContent` som hemskärmens widgetar. Kärlen är de som töms det
/// datum som är nästa tömning, med källans korta namn.
public struct LockScreenContent: Equatable, Sendable {
    /// Raden ovanför klockan: "Tors 19 nov: Mat, Papper", "I morgon: Rest" eller "Utställt: Rest, Mat".
    public let inline: String
    /// Rektangelns rubrik: "Om 13 dagar", "I morgon", "Ca om 13 dagar", eller "Sophämtning" utan schema.
    public let title: String
    /// Rektangelns datum: "Tors 19 nov", "Ca tors 19 nov". Tomt utan schema.
    public let date: String
    /// Rektangelns sista rad: kärlen, "Utställt", "Öppna appen" eller "Inga kommande hämtningar".
    public let line: String
    /// Cirkelns siffra, dagar kvar: "13", "1" i morgon och "0" i dag. `nil` när kärlen är utställda eller schema saknas.
    public let days: String?
    public let placedOut: Bool

    /// Värdet under kontrollen Ställ ut kärlen: "Utställt", "I dag", "I morgon", nästa datum, eller sista raden utan schema.
    public var controlValue: String {
        if placedOut { return "Utställt" }
        guard let days else { return line }
        return days == "0" || days == "1" ? title : date
    }

    public static func make(content: WidgetContent, info: [String: FractionInfo], placedOut: Bool) -> LockScreenContent {
        switch content {
        case .pickup(_, let relative, let shortDate, let fractions):
            let rows = WidgetContent.mediumRows(fractions, maxRows: .max).rows
            let names = rows.map { ScheduleLogic.displayInfo(for: $0.fraction, in: info).short }.joined(separator: ", ")
            let daysUntil = rows.first?.daysUntil ?? 0
            let title = capitalized(relative)
            let date = capitalized(shortDate)
            // I dag och i morgon säger mer än datumet. Längre bort är datumet det man vill se.
            let when = (0...1).contains(daysUntil) ? title : date
            return LockScreenContent(
                inline: placedOut ? "Utställt: \(names)" : "\(when): \(names)",
                title: title,
                date: date,
                line: placedOut ? "Utställt" : names,
                days: placedOut ? nil : String(daysUntil),
                placedOut: placedOut
            )
        case .noUpcoming(let name):
            return LockScreenContent(inline: "\(name): inga kommande hämtningar", title: name, date: "", line: "Inga kommande hämtningar", days: nil, placedOut: false)
        case .noAddress, .unavailable, .noSchedule, .failed, .notFound:
            // Ett tekniskt fel ska aldrig se ut som att adressen saknas, så alla lägen utan schema säger samma sak.
            return LockScreenContent(inline: "Sophämtning: öppna appen", title: "Sophämtning", date: "", line: "Öppna appen", days: nil, placedOut: false)
        }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Länken som lägger in adressens schema i Kalender: `links.ics` med schemat `webcal://`, så att iOS frågar om
/// prenumeration. Bara `https://`-länkar görs om.
public enum CalendarLink {
    public static func webcal(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "webcal"
        return parts.url
    }
}
