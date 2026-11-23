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
    fun dateOn(day: DayDate, minutes: Int): Instant =
        day.toLocalDate().atTime(LocalTime.of(minutes / 60, minutes % 60)).atZone(zone).toInstant()
}
