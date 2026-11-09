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

    public static func date(forPickup pickup: DayDate, settings: ReminderSettings) -> Date {
        StockholmClock.date(on: reminderDay(forPickup: pickup, timing: settings.timing), minutes: settings.activeMinutes)
    }
}
