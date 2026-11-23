package se.hardyson.sophamtning.core.search

import se.hardyson.sophamtning.core.api.Pickups
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat

/** Vad "Hitta område med senaste tömningen" visar. */
sealed interface AreaFinderState {
    data object Idle : AreaFinderState

    data object Searching : AreaFinderState

    /** Exakt ett område hade hämtning den dagen. */
    data class Match(val hit: SearchHit) : AreaFinderState

    /** Flera områden. Inget väljs automatiskt. */
    data class Multiple(val hits: List<SearchHit>) : AreaFinderState

    /** Schemat täcker dagen, men inget område hade hämtning. */
    data object NoPickup : AreaFinderState

    /** Schemat täcker inte dagen. */
    data object OutsideSchedule : AreaFinderState

    /** Det gick inte att avgöra, och det säger inget om området. */
    data object Failed : AreaFinderState

    /** Sant när minst ett område hittades. Då, och bara då, vibrerar arket. */
    val foundAreas: Boolean get() = this is Match || this is Multiple

    companion object {
        /**
         * Träffar visas alltid, även när en källa inte svarade. Utan träffar räknas bara ett fullständigt svar
         * med bedömt datum som "ingen hämtning" eller "utanför schemat". Allt annat är [Failed].
         */
        fun from(response: SearchResponse): AreaFinderState = when (response.addresses.size) {
            0 -> {
                val covered = response.dateCovered
                if (response.failed.isNotEmpty() || covered == null) Failed else if (covered) NoPickup else OutsideSchedule
            }
            1 -> Match(response.addresses[0])
            else -> Multiple(response.addresses)
        }
    }
}

/** Texterna om tömningarna. Datum utan veckodag. */
object AreaFinderText {
    /** Visas när en träff kommer fram trots att en källa inte svarade. */
    const val partialNotice = "En källa svarade inte, så fler områden kan finnas."

    /** Kommunens namn behövs i listan först när träffarna gäller mer än en kommun. */
    fun showsKommun(hits: List<SearchHit>): Boolean = hits.map { it.kommun }.toSet().size > 1

    private const val QUESTION = "Stämmer det? En försenad tömning kan ge fel område."

    /** Kontrolltexten för en enskild träff. */
    fun check(pickups: Pickups?, today: DayDate): String =
        listOfNotNull(dates(pickups, today, verb = true), QUESTION).joinToString(" ")

    /** Kortare text för raderna i listan med flera träffar. `null` utan datum. */
    fun summary(pickups: Pickups?, today: DayDate): String? = dates(pickups, today, verb = false)

    /** "Tömningar 13 okt och 27 okt. Nästa är 10 nov." Passerat nästa datum heter "Nästa var". */
    private fun dates(pickups: Pickups?, today: DayDate, verb: Boolean): String? {
        if (pickups == null) return null
        val parts = mutableListOf<String>()
        previousSentence(pickups.previous)?.let(parts::add)
        pickups.next?.let { next ->
            val lead = if (next < today) "Nästa var" else if (verb) "Nästa är" else "Nästa"
            parts += "$lead ${SwedishFormat.dayMonth(next)}."
        }
        return if (parts.isEmpty()) null else parts.joinToString(" ")
    }

    private fun previousSentence(days: List<DayDate>): String? {
        val texts = days.map(SwedishFormat::dayMonth)
        return when (texts.size) {
            0 -> null
            1 -> "Tömning ${texts[0]}."
            else -> "Tömningar ${texts.dropLast(1).joinToString(", ")} och ${texts.last()}."
        }
    }
}
