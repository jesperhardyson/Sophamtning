import Foundation

/// Tid i Europe/Stockholm. Telefonens tidszon används aldrig.
public enum StockholmClock {
    /// Gregoriansk kalender i svensk tidszon, delad av alla datumtyper.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.locale = Locale(identifier: "sv_SE")
        return calendar
    }()

    /// Dagen i Sverige vid givet ögonblick.
    public static func today(now: Date) -> DayDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return DayDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Ögonblicket då klockan är `minutes` minuter efter midnatt (väggklocka) svensk tid på dagen.
    /// Räknas som klockslag, inte som förflutna minuter, så att omställningsdagar blir rätt.
    public static func date(on day: DayDate, minutes: Int) -> Date {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return calendar.date(from: parts)!
    }
}
