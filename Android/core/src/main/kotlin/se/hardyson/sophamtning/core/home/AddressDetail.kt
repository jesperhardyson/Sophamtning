package se.hardyson.sophamtning.core.home

import java.time.Instant
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.capitalizedFirst
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.reminders.ReminderTime
import se.hardyson.sophamtning.core.reminders.missedText
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming

/** Adressvyns innehåll. Här står än så länge bara texterna för påminnelserna. */
class AddressDetail private constructor() {
    companion object {
        /** Klockslaget för ett ögonblick i svensk tid, "18:45". */
        internal fun clock(date: Instant): String {
            val time = date.atZone(StockholmClock.zone)
            return SwedishFormat.clock(time.hour * 60 + time.minute)
        }

        /**
         * "Söndag kl. 18:45 inför måndagens tömning, om aktiviteten inte syns." eller "Måndag kl. 06:45, samma dag som
         * tömningen, om aktiviteten inte syns." När det är reserven som gäller. Tömningsdagen räknas från reservens klockslag,
         * inte från det som är valt nu: en notis från det andra valet kan stå kvar efter ett byte.
         */
        internal fun reserveText(reserveAt: Instant): String {
            val day = StockholmClock.today(reserveAt)
            val pickup = ReminderTime.pickupDay(reserveAt)
            val timing = if (pickup == day) ReminderTiming.SameMorning else ReminderTiming.EveningBefore
            return "${whenText(day, pickup, clock(reserveAt), timing)}, om aktiviteten inte syns."
        }

        /** "Söndag kl. 18:00 inför måndagens tömning" eller "Måndag kl. 06:00, samma dag som tömningen". */
        private fun whenText(day: DayDate, pickup: DayDate, time: String, timing: ReminderTiming): String {
            val start = "${SwedishFormat.weekdayName(day).capitalizedFirst()} kl. $time"
            return when (timing) {
                ReminderTiming.EveningBefore -> "$start inför ${SwedishFormat.weekdayName(pickup)}ens tömning"
                ReminderTiming.SameMorning -> "$start, samma dag som tömningen"
            }
        }

        /** Det som står bakom knappen Mer om Live Update, en mening per rad. */
        fun liveActivityDetails(): List<String> = listOf(
            "Starten aviseras med ljud.",
            "Den försvinner senast efter 12 timmar.",
            "Öppna appen ibland, så att nästa tömning kommer med.",
            "Med notis vid samma tid får du en reserv om du inte bekräftar.",
        )

        /**
         * Hela tiden Live Updaten syns, högst 12 timmar från starten: "Visas på låsskärmen kl. 21:00 dagen före till 09:00."
         * eller "Visas på låsskärmen kl. 06:00–18:00 samma dag."
         */
        fun liveActivityText(settings: ReminderSettings): String {
            val start = settings.liveActivityStartMinutes
            val from = SwedishFormat.clock(start)
            val to = SwedishFormat.clock((start + 12 * 60) % (24 * 60))
            return when (settings.liveActivityTiming) {
                ReminderTiming.EveningBefore -> "Visas på låsskärmen kl. $from dagen före till $to."
                ReminderTiming.SameMorning -> "Visas på låsskärmen kl. $from–$to samma dag."
            }
        }

        /**
         * Påminnelsetiden i dag har redan passerat för tömningen den gäller, i morgon med kvällen före och i dag med samma
         * morgon. Till exempel efter att tiden ändrats eller notisen slagits på sent.
         */
        fun missedReminder(events: List<PickupEvent>, settings: ReminderSettings, now: Instant): String? {
            val today = StockholmClock.today(now)
            // Det senast påslagna valet avgör: kvällens tid kan ha passerat utan att något är missat, när morgonen kommer.
            val timing = settings.latestTiming
            val pickup = ReminderTime.pickupDay(today, timing)
            if (events.none { it.date == pickup && it.fractions.isNotEmpty() }) return null
            if (ReminderTime.date(pickup, timing, settings) > now) return null
            return timing.missedText
        }

        /**
         * Raden under reglaget: reservnotisen när den är nästa påminnelse, annars nästa påminnelse. Reserven ersätter notisen
         * för Live Updatens val, så den gäller när det är nästa, när den kommer före nästa eller när ingen annan finns.
         */
        internal fun rowText(events: List<PickupEvent>, settings: ReminderSettings, now: Instant, reserveAt: Instant?, skipping: Set<DayDate>): String {
            if (reserveAt != null) {
                val next = ReminderTime.next(events, settings, now, skipping)
                if (next == null || next.timing == settings.liveActivityTiming || reserveAt <= next.date) return reserveText(reserveAt)
            }
            return reminderText(events, settings, now, skipping)
        }

        /**
         * "Söndag kl. 18:00 inför måndagens tömning." eller "Måndag kl. 06:00, samma dag som tömningen." Det är nästa
         * påminnelse av de påslagna valen. Finns ingen kommande tömning står texten för varje påslaget val.
         */
        internal fun reminderText(events: List<PickupEvent>, settings: ReminderSettings, now: Instant, skipping: Set<DayDate> = emptySet()): String {
            ReminderTime.next(events, settings, now, skipping)?.let { next ->
                return "${whenText(StockholmClock.today(next.date), next.pickup, clock(next.date), next.timing)}."
            }
            return settings.enabledTimings.joinToString(" ") { timing ->
                val time = SwedishFormat.clock(settings.minutes(timing))
                when (timing) {
                    ReminderTiming.EveningBefore -> "Kvällen före varje tömning kl. $time."
                    ReminderTiming.SameMorning -> "Samma morgon som varje tömning kl. $time."
                }
            }
        }
    }
}
