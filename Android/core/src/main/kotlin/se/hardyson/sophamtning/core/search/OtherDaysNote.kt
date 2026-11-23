package se.hardyson.sophamtning.core.search

import se.hardyson.sophamtning.core.api.AreaDetails
import se.hardyson.sophamtning.core.trimmedNonEmpty

/**
 * Rutan i adressvyn och i Hela schemat för ett område där vissa gator har en annan hämtdag: rubriken som på webben och
 * raderna från `area.otherDays`. Dag och platser visas inte här, de syns redan i adressens namn och `detail`.
 */
data class OtherDaysNote(
    val heading: String,
    /** Raderna ordagrant, utan blanka rader. Aldrig tom. */
    val rows: List<String>,
) {
    companion object {
        /** `null` när området saknas, `otherDays` är tom eller bara har blanka rader. */
        fun make(area: AreaDetails?): OtherDaysNote? {
            val rows = area?.otherDays.orEmpty().mapNotNull { it.trimmedNonEmpty() }
            if (rows.isEmpty()) return null
            return OtherDaysNote(heading = AreaRowContent.otherDaysHeading, rows = rows)
        }
    }
}
