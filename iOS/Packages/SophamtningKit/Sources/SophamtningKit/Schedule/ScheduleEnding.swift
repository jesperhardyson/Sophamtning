import Foundation

/// Schemat tar snart slut: `schedule.until` är 14 dagar eller mindre bort och har inte passerat. Delas av rutan i
/// adressvyn, raden på hemkortet och raden i widgeten, så att de alltid är överens. Dagarna räknas i Europe/Stockholm
/// och `until` är sista dagen som schemat gäller, så den dagen visas också.
public struct ScheduleEnding: Equatable, Sendable {
    /// Så här många dagar eller färre kvar ger rutan och raderna.
    public static let warningDays = 14

    /// 0 den sista dagen.
    public let daysLeft: Int
    /// Sista dagen som schemat gäller.
    public let until: DayDate
    /// "Schemat slutar 10 jan", utan år, för hemkortet och widgeten.
    public let shortText: String
    /// "Schemat slutar 10 januari", för VoiceOver, som annars läser "jan" som ett ord.
    public let spokenText: String
    /// Rubriken i rutan.
    public let title: String
    /// Att nya tider visas när källan publicerar dem. Källans orsak står en gång, under raden "Schemat gäller till …"
    /// precis ovanför rutan, och upprepas inte här. Påminnelser nämns inte: appen hämtar om schemat vid start, när den
    /// öppnas och i bakgrunden när iOS tillåter det, men inget av det kan lovas, så texten lovar inget.
    public let message: String

    private static let message = "Nya tider visas när källan publicerar dem."

    /// `nil` för live-källor (`schedule: null`), när det är mer än 14 dagar kvar och när `until` har passerat.
    public static func make(_ period: SchedulePeriod?, today: DayDate) -> ScheduleEnding? {
        guard let period else { return nil }
        let daysLeft = today.days(until: period.until)
        guard (0...warningDays).contains(daysLeft) else { return nil }
        return ScheduleEnding(
            daysLeft: daysLeft,
            until: period.until,
            shortText: "Schemat slutar \(SwedishFormat.dayMonth(period.until))",
            spokenText: "Schemat slutar \(period.until.day) \(SwedishFormat.monthName(period.until))",
            title: "Schemat tar snart slut",
            message: message
        )
    }
}
