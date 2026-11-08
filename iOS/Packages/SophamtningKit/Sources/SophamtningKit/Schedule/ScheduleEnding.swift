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
    /// Källans orsak, om den finns, och att nya tider visas när källan publicerar dem.
    public let message: String

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
            message: message(reason: period.reason?.trimmedNonEmpty)
        )
    }

    /// Källans orsak med punkt efter, och sedan att nya tider visas. Påminnelser nämns inte: appen hämtar om schemat vid
    /// start, när den öppnas och i bakgrunden när iOS tillåter det, men inget av det kan lovas, så texten lovar inget.
    private static func message(reason: String?) -> String {
        let promise = "Nya tider visas när källan publicerar dem."
        guard let reason else { return promise }
        let terminated = reason.hasSuffix(".") || reason.hasSuffix("!") || reason.hasSuffix("?") ? reason : reason + "."
        return terminated + " " + promise
    }
}
