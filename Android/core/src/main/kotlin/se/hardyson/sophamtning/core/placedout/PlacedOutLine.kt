package se.hardyson.sophamtning.core.placedout

import java.time.Instant
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

/**
 * Regler för Ställ ut kärlen utan hushåll, som `HouseholdLogic` på iOS för en adress som inte delas. Inget här läser klockan.
 */
object PlacedOutLogic {
    /**
     * Sant när nästa tömning är i dag eller i morgon och adressen har påminnelser på. Utan knappen går en ångrad bock från Live
     * Update inte att sätta igen på tömningsdagen, när den inte startar om.
     */
    fun showsPlaceOutButton(remindersOn: Boolean, nextPickup: DayDate?, today: DayDate): Boolean {
        if (!remindersOn || nextPickup == null) return false
        return today.daysUntil(nextPickup) in 0..1
    }

    /** Den utställda för adressens nästa tömning, om någon. Den gäller hämtdatumet, aldrig dagen då någon tryckte. */
    fun currentMark(key: AddressKey, nextPickup: DayDate?, placedOut: Set<PlacedOut>): PlacedOut? {
        nextPickup ?: return null
        return PlacedOut(key, nextPickup).takeIf { it in placedOut }
    }
}

/** Texterna för Ställ ut kärlen och Utställt. */
object PlacedOutTexts {
    /** Rubriken i raden när kärlen är utställda. */
    const val PLACED_OUT_TITLE = "Utställt"

    /** Raderna på hemskärmen när nästa tömning är markerad. */
    const val OWN_PLACED_OUT = "Kärlen är utställda"

    const val PLACE_OUT = "Ställ ut kärlen"
    const val UNDO = "Ångra"
    const val UNDO_HINT = "Tar bort att kärlen är utställda"

    /** Raden under "Utställt": "av dig · kl. 19:42". Klockslaget är svensk tid. */
    fun placedOutSubtitle(at: Instant): String {
        val time = at.atZone(StockholmClock.zone)
        return "av dig · kl. ${SwedishFormat.clock(time.hour * 60 + time.minute)}"
    }
}

/**
 * Raden för Utställt på ett kort och i adressvyn, som `HouseholdLine` på iOS för en adress som inte delas: knappen Ställ ut
 * kärlen, eller Utställt när nästa tömning är markerad. `null` när det inte finns något att visa.
 */
data class PlacedOutLine(
    /** Knappen Ställ ut kärlen visas: påminnelser på, tömning i dag eller i morgon, och inte utställt än. */
    val showsButton: Boolean,
    /** "Kärlen är utställda" när nästa tömning är markerad. Raderna på hemskärmen visar den, och TalkBack läser den. */
    val placedOutText: String?,
    /** Rubriken i raden: "Utställt". */
    val placedOutTitle: String = PlacedOutTexts.PLACED_OUT_TITLE,
    /** Raden under "Utställt": "av dig · kl. 19:42", när tiden är känd. */
    val placedOutSubtitle: String? = null,
) {
    companion object {
        /**
         * Raden för en adress och dess nästa tömning.
         *
         * @param ownPlacedOut de utställda i `placed-out.json`.
         * @param remindersOn adressen har notiser eller Live Update på. Då visas knappen, så att kärlen går att ställa ut
         *   igen efter Ångra.
         * @param placedOutTimes när kärlen ställdes ut, för undertexten. Saknas tiden står ingen undertext.
         */
        fun make(
            key: AddressKey,
            nextPickup: DayDate?,
            today: DayDate,
            ownPlacedOut: Set<PlacedOut> = emptySet(),
            remindersOn: Boolean = false,
            placedOutTimes: Map<PlacedOut, Instant> = emptyMap(),
        ): PlacedOutLine? {
            val mark = PlacedOutLogic.currentMark(key, nextPickup, ownPlacedOut)
            if (mark == null) {
                val showsButton = PlacedOutLogic.showsPlaceOutButton(remindersOn, nextPickup, today)
                return if (showsButton) PlacedOutLine(showsButton = true, placedOutText = null) else null
            }
            return PlacedOutLine(
                showsButton = false,
                placedOutText = PlacedOutTexts.OWN_PLACED_OUT,
                placedOutSubtitle = placedOutTimes[mark]?.let(PlacedOutTexts::placedOutSubtitle),
            )
        }
    }
}
