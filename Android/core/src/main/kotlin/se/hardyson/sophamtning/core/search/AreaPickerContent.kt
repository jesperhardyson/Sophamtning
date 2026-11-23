package se.hardyson.sophamtning.core.search

import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.graphemeCount

/**
 * Det som områdesvalet visar för en söktext: områdena, varningskortet och raden Hitta område. Under en sökning visas
 * bara träffarna, som i systemets egna sökningar. Ett filter utan träffar säger inget om att något saknas hos källan.
 */
data class AreaPickerContent(
    /** Områdena som matchar, i listans ordning. Ett tomt fält visar alla. */
    val hits: List<SearchHit>,
    /** Varningskortet överst. Det döljs under en sökning och kommer tillbaka när fältet töms. */
    val showsWarning: Boolean,
    /** Hitta område som listans första rad, ovanför områdena. */
    val showsFinderFirst: Boolean,
    /** Texten när inget område matchar, "Inga områden matchar ”zzz”.", annars `null`. */
    val emptyText: String?,
    /** Hitta område under texten när inget matchar, som vägen vidare. */
    val showsFinderWhenEmpty: Boolean,
) {
    companion object {
        /** [hasFinder] är sant när orten är känd, så att Hitta område kan söka i den. */
        fun make(hits: List<SearchHit>, query: String, hasFinder: Boolean): AreaPickerContent {
            val trimmed = query.trim(Char::isWhitespace)
            // Samma gräns som filtret: med ett enda tecken visas hela listan, och då står varningen kvar.
            val searching = trimmed.graphemeCount() >= AreaFilter.minimumLength
            val visible = AreaFilter.filter(hits, query)
            val empty = visible.isEmpty()
            return AreaPickerContent(
                hits = visible,
                showsWarning = !searching,
                showsFinderFirst = !empty && !searching && hasFinder,
                emptyText = if (empty) "Inga områden matchar ”$trimmed”." else null,
                showsFinderWhenEmpty = empty && hasFinder,
            )
        }
    }
}
