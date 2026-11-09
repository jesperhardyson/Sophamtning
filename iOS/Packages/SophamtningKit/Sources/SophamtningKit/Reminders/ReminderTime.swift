import Foundation

/// När en påminnelse kommer för en tömning. Den enda platsen som räknar det, så att notiser, Live Activity, reserven och
/// texterna alltid är överens. Allt räknas i Europe/Stockholm.
public enum ReminderTime {
    /// Dagen påminnelsen kommer: dagen före tömningen eller samma dag.
    public static func reminderDay(forPickup pickup: DayDate, timing: ReminderTiming) -> DayDate {
        timing == .eveningBefore ? pickup.adding(days: -1) : pickup
    }

    /// Tömningen som en påminnelse en viss dag gäller.
    public static func pickupDay(remindedOn day: DayDate, timing: ReminderTiming) -> DayDate {
        timing == .eveningBefore ? day.adding(days: 1) : day
    }

    /// Tömningen som en påminnelse vid ett visst klockslag gäller, oberoende av vad som är valt nu. Morgonens tider (05:00 till
    /// reservens tak 12:00) och kvällens (15:00 till 23:45) överlappar aldrig, så klockslaget avgör. Det gör att en notis eller
    /// aktivitet från det andra valet, som står kvar efter ett byte, ändå räknas till rätt tömning.
    public static func pickupDay(forReminderAt date: Date) -> DayDate {
        let day = StockholmClock.today(now: date)
        return StockholmClock.date(on: day, minutes: sameDayLatestMinutes) > date ? day : day.adding(days: 1)
    }

    /// Klockslag före vilket en påminnelse gäller samma dags tömning: 12:00.
    static let sameDayLatestMinutes = 12 * 60

    /// Påminnelsens tid för en tömning, med det valda och dess tid.
    public static func date(forPickup pickup: DayDate, settings: ReminderSettings) -> Date {
        StockholmClock.date(on: reminderDay(forPickup: pickup, timing: settings.timing), minutes: settings.activeMinutes)
    }
}
