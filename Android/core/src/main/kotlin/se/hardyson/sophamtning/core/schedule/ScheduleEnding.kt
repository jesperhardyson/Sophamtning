package se.hardyson.sophamtning.core.schedule

import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat

/**
 * Schemat tar snart slut: `schedule.until` är 14 dagar eller mindre bort och har inte passerat. Delas av rutan i adressvyn,
 * raden på hemkortet och raden i widgeten, så att de alltid är överens. `until` är sista dagen som schemat gäller.
 */
data class ScheduleEnding(
    /** 0 den sista dagen. */
    val daysLeft: Int,
    val until: DayDate,
    /** "Schemat slutar 10 jan", utan år, för hemkortet och widgeten. */
    val shortText: String,
    /** "Schemat slutar 10 januari", för TalkBack, som annars läser "jan" som ett ord. */
    val spokenText: String,
    val title: String,
    /** Att nya tider visas när källan publicerar dem. Påminnelser nämns inte, eftersom inget kan lovas. */
    val message: String,
) {
    companion object {
        const val WARNING_DAYS = 14

        /** `null` för live-källor, när det är mer än 14 dagar kvar och när `until` har passerat. */
        fun make(period: SchedulePeriod?, today: DayDate): ScheduleEnding? {
            period ?: return null
            val daysLeft = today.daysUntil(period.until)
            if (daysLeft !in 0..WARNING_DAYS) return null
            return ScheduleEnding(
                daysLeft = daysLeft,
                until = period.until,
                shortText = "Schemat slutar ${SwedishFormat.dayMonth(period.until)}",
                spokenText = "Schemat slutar ${period.until.day} ${SwedishFormat.monthName(period.until)}",
                title = "Schemat tar snart slut",
                message = "Nya tider visas när källan publicerar dem.",
            )
        }
    }
}
