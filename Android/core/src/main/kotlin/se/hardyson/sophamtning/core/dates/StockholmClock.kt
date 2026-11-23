package se.hardyson.sophamtning.core.dates

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/** Tid i Europe/Stockholm. Telefonens tidszon används aldrig. */
object StockholmClock {
    val zone: ZoneId = ZoneId.of("Europe/Stockholm")

    /** Dagen i Sverige vid givet ögonblick. */
    fun today(now: Instant = Instant.now()): DayDate = DayDate.from(now.atZone(zone).toLocalDate())

    /**
     * Ögonblicket då klockan är [minutes] minuter efter midnatt (väggklocka) svensk tid på dagen.
     * Räknas som klockslag, inte som förflutna minuter, så att omställningsdagar blir rätt.
     */
    fun dateOn(day: DayDate, minutes: Int): Instant {
        // Minuter utanför dygnet rullar över till en annan dag, som `Calendar.date(from:)` på iOS.
        val date = day.toLocalDate().plusDays(Math.floorDiv(minutes, 1440).toLong())
        val clock = Math.floorMod(minutes, 1440)
        return date.atTime(LocalTime.of(clock / 60, clock % 60)).atZone(zone).toInstant()
    }
}
