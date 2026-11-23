package se.hardyson.sophamtning.core.schedule

import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate

/** Nästa hämtning för en fraktion, räknad lokalt från händelserna. */
data class FractionPickup(
    /** Fraktions-id. */
    val fraction: String,
    val date: DayDate,
    val estimated: Boolean,
    val warning: String?,
    /** Dagar från `today` till `date`. Räknas lokalt, aldrig från API:ts `daysUntil`. */
    val daysUntil: Int,
)

/** Ren schemalogik. Allt räknas från händelserna och given dag, aldrig från sparade `next`-fält. */
object ScheduleLogic {
    /** Neutral färg för fraktioner som API:t inte känner till. */
    internal const val NEUTRAL_COLOR = "#526158"
    internal const val FALLBACK_ICON = "recycle"

    /** Händelser från och med `today`, sorterade på datum. */
    fun upcoming(events: List<PickupEvent>, today: DayDate) = events.filter { it.date >= today }.sortedBy { it.date }

    fun nextPickup(events: List<PickupEvent>, today: DayDate) = upcoming(events, today).firstOrNull()

    /** Första kommande datum per fraktion, sorterat på datum och sedan på fraktions-id. */
    fun nextByFraction(events: List<PickupEvent>, today: DayDate): List<FractionPickup> {
        val first = LinkedHashMap<String, FractionPickup>()
        for (event in upcoming(events, today)) {
            for (id in event.fractions) {
                if (id !in first) first[id] = FractionPickup(id, event.date, event.estimated, event.warning, today.daysUntil(event.date))
            }
        }
        return first.values.sortedWith(compareBy<FractionPickup> { it.date }.thenBy { it.fraction })
    }

    /** Visningsinfo för ett fraktions-id. Okända id:n får id:t som namn, neutral färg och ikonen `recycle`. */
    fun displayInfo(id: String, fractions: Map<String, FractionInfo>) =
        fractions[id] ?: FractionInfo(name = id, short = id, color = NEUTRAL_COLOR, icon = FALLBACK_ICON)
}
