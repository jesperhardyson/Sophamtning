package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming

/**
 * När en påminnelse kommer för en tömning. Den enda platsen som räknar det, så att notiser, Live Update, reserven och
 * texterna alltid är överens. Allt räknas i Europe/Stockholm.
 */
object ReminderTime {
    /** Klockslag före vilket en påminnelse gäller samma dags tömning: 12:00. */
    internal const val SAME_DAY_LATEST_MINUTES = 12 * 60

    /** Dagen påminnelsen kommer: dagen före tömningen eller samma dag. */
    fun reminderDay(pickup: DayDate, timing: ReminderTiming): DayDate =
        if (timing == ReminderTiming.EveningBefore) pickup.plusDays(-1) else pickup

    /** Tömningen som en påminnelse en viss dag gäller. */
    fun pickupDay(remindedOn: DayDate, timing: ReminderTiming): DayDate =
        if (timing == ReminderTiming.EveningBefore) remindedOn.plusDays(1) else remindedOn

    /**
     * Tömningen som en påminnelse vid ett visst klockslag gäller, oberoende av vad som är valt nu. Morgonens tider (05:00 till
     * reservens tak 12:00) och kvällens (15:00 till 23:45) överlappar aldrig, så klockslaget avgör. Det gör att en notis eller
     * Live Update från det andra valet, som står kvar efter ett byte, ändå räknas till rätt tömning.
     */
    fun pickupDay(reminderAt: Instant): DayDate {
        val day = StockholmClock.today(reminderAt)
        return if (StockholmClock.dateOn(day, SAME_DAY_LATEST_MINUTES) > reminderAt) day else day.plusDays(1)
    }

    /** Påminnelsens tid för en tömning, för ett visst val och dess tid. */
    fun date(pickup: DayDate, timing: ReminderTiming, settings: ReminderSettings): Instant =
        StockholmClock.dateOn(reminderDay(pickup, timing), settings.minutes(timing))

    /** En kommande påminnelse: tömningen, valet och tidpunkten. */
    data class UpcomingReminder(val pickup: DayDate, val timing: ReminderTiming, val date: Instant)

    /** Live Updatens start för en tömning: dagen före eller samma dag, på dess egen tid. */
    fun liveActivityStart(pickup: DayDate, settings: ReminderSettings): Instant =
        StockholmClock.dateOn(reminderDay(pickup, settings.liveActivityTiming), settings.liveActivityStartMinutes)

    /**
     * Den tidigaste påminnelsen efter [now], över kommande tömningar med fraktioner och alla påslagna val. Tömningar i
     * [skipping] (utställda) har inga påminnelser kvar och hoppas över.
     */
    fun next(events: List<PickupEvent>, settings: ReminderSettings, now: Instant, skipping: Set<DayDate> = emptySet()): UpcomingReminder? {
        var best: UpcomingReminder? = null
        for (event in events) {
            if (event.fractions.isEmpty() || event.date in skipping) continue
            for (timing in settings.enabledTimings) {
                val date = date(event.date, timing, settings)
                if (date <= now || (best != null && date >= best.date)) continue
                best = UpcomingReminder(event.date, timing, date)
            }
        }
        return best
    }
}
