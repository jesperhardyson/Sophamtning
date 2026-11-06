import Foundation

/// Svenska datumtexter. Namnen är fasta tabeller så att utseendet inte beror på telefonens språkdata.
public enum SwedishFormat {
    private static let weekdays = ["söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag"]
    private static let shortWeekdays = ["sön", "mån", "tis", "ons", "tors", "fre", "lör"]
    private static let months = [
        "januari", "februari", "mars", "april", "maj", "juni",
        "juli", "augusti", "september", "oktober", "november", "december",
    ]
    private static let shortMonths = [
        "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec",
    ]

    /// Index 0 är söndag, som `Calendar.weekday - 1`.
    private static func weekdayIndex(_ day: DayDate) -> Int {
        let date = StockholmClock.date(on: day, minutes: 12 * 60)
        return StockholmClock.calendar.component(.weekday, from: date) - 1
    }

    /// "måndag 9 november", eller "Måndag 9 november" med versal.
    public static func longDate(_ day: DayDate, capitalized: Bool) -> String {
        let text = "\(weekdays[weekdayIndex(day)]) \(day.day) \(months[day.month - 1])"
        return capitalized ? text.prefix(1).uppercased() + text.dropFirst() : text
    }

    /// "Mån 9 nov".
    public static func shortDate(_ day: DayDate) -> String {
        let weekday = shortWeekdays[weekdayIndex(day)]
        return "\(weekday.prefix(1).uppercased() + weekday.dropFirst()) \(day.day) \(shortMonths[day.month - 1])"
    }

    public static func relative(days: Int) -> String {
        switch days {
        case 0: "i dag"
        case 1: "i morgon"
        default: "om \(days) dagar"
        }
    }

    /// Sätter "ca" framför en text när tiden är uppskattad.
    public static func estimated(_ text: String, _ isEstimated: Bool) -> String {
        isEstimated ? "ca \(text)" : text
    }
}
