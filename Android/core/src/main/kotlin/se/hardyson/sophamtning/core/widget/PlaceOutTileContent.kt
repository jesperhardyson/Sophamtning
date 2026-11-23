package se.hardyson.sophamtning.core.widget

import java.time.Instant
import se.hardyson.sophamtning.core.placedout.PlacedOutTexts
import se.hardyson.sophamtning.core.storage.PlacedOut

/**
 * Rutan Ställ ut kärlen i snabbinställningarna, för huvudadressen, som kontrollen `PlaceOutControl` på iOS. Den är aktiv
 * när kärlen ska ställas ut (nästa tömning i dag eller i morgon och inte utställd), visar Utställt när de är det, och är
 * avstängd annars. Undertexten är värdet under kontrollen på iOS: "I dag", "I morgon", "Utställt", nästa datum, eller
 * vad som saknas. Allt räknas från lagringen, som widgeten.
 */
data class PlaceOutTileContent(val state: State, val subtitle: String, val entry: PlacedOut?) {
    enum class State { Active, PlacedOut, Unavailable }

    companion object {
        const val TITLE = PlacedOutTexts.PLACE_OUT
        const val PLACED_OUT = "Utställt"
        const val NO_UPCOMING = "Inga kommande hämtningar"

        /** Ett tekniskt fel ska aldrig se ut som att adressen saknas, så alla lägen utan schema säger samma sak. */
        const val OPEN_APP = "Öppna appen"

        fun make(data: WidgetData, now: Instant): PlaceOutTileContent {
            val entry = data.placeOutEntry(now)
            val placedOut = data.placedOut(now)
            val subtitle = when (val content = data.content(now)) {
                is WidgetContent.Pickup -> when {
                    placedOut -> PLACED_OUT
                    // I dag och i morgon säger mer än datumet. Längre bort är datumet det man vill se.
                    content.fractions.firstOrNull()?.daysUntil in 0..1 -> capitalized(content.relative)
                    else -> capitalized(content.shortDate)
                }
                is WidgetContent.NoUpcoming -> NO_UPCOMING
                else -> OPEN_APP
            }
            val state = when {
                entry != null -> State.Active
                placedOut -> State.PlacedOut
                else -> State.Unavailable
            }
            return PlaceOutTileContent(state, subtitle, entry)
        }

        private fun capitalized(text: String) = text.replaceFirstChar { it.uppercase() }
    }
}
