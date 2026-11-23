package se.hardyson.sophamtning.core.search

import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.graphemeCount

/** Vad adressökningen visar. */
sealed interface SearchState {
    data object Idle : SearchState

    data object Searching : SearchState

    /** Träffar, och källor som inte svarade. */
    data class Results(val hits: List<SearchHit>, val failed: List<String>) : SearchState

    /** Inga träffar och minst en källa svarade inte. Det betyder inte att adressen saknas. */
    data class SourcesFailed(val failed: List<String>) : SearchState

    /** Inga träffar och inga fel. [place] är orten i söktexten, om någon angetts. */
    data class NoHits(val place: String?) : SearchState

    data class Failed(val error: ApiError) : SearchState

    companion object {
        fun from(response: SearchResponse, query: String): SearchState {
            if (response.addresses.isNotEmpty()) return Results(hits = response.addresses, failed = response.failed)
            if (response.failed.isNotEmpty()) return SourcesFailed(response.failed)
            return NoHits(place = place(query))
        }

        /** Orten i söktexten: texten efter kommatecknet, annars texten efter husnumret (och en bokstav efter numret). */
        fun place(query: String): String? {
            val comma = query.indexOf(',')
            if (comma >= 0) return words(query.substring(comma + 1)).nilIfBlank()
            val tokens = tokens(query).toMutableList()
            val numberIndex = tokens.indexOfFirst { it.startsWithNumber() }
            if (numberIndex < 0) return null
            repeat(numberIndex + 1) { tokens.removeAt(0) }
            // Husnummer som "12 B": en ensam bokstav efter numret hör till numret.
            val first = tokens.firstOrNull()
            if (first != null && first.graphemeCount() == 1 && Character.isLetter(first.codePointAt(0))) tokens.removeAt(0)
            return tokens.joinToString(" ").nilIfBlank()
        }

        /**
         * Orterna att fråga `/omraden` om, i ordning: texten efter kommatecknet, annars texten efter husnumret, och utan
         * nummer de två sista orden och det sista ordet (hela texten när den är ett eller två ord). Ett namn har högst två
         * ord och minst två tecken, och skiftläget behålls.
         */
        fun placeCandidates(query: String): List<String> {
            val tokens = tokens(query)
            val raw: List<String> = if (query.contains(',') || tokens.any { it.startsWithNumber() }) {
                listOfNotNull(place(query))
            } else {
                buildList {
                    if (tokens.size >= 2) add(tokens.takeLast(2).joinToString(" "))
                    tokens.lastOrNull()?.let(::add)
                    if (tokens.size <= 2) add(tokens.joinToString(" "))
                }
            }
            val result = mutableListOf<String>()
            for (name in raw) {
                if (name.graphemeCount() >= 2 && name.split(' ').count { it.isNotEmpty() } <= 2 && name !in result) result += name
            }
            return result
        }

        /** Orden i texten, delade på blanktecken som `split(whereSeparator: \.isWhitespace)` i Swift. */
        private fun tokens(text: String): List<String> = text.splitWhere(Char::isWhitespace).filter { it.isNotEmpty() }

        private fun words(text: String) = tokens(text).joinToString(" ")

        private fun String.nilIfBlank(): String? = ifEmpty { null }

        /** Som `Character.isNumber` i Swift: siffror, men också andra taltecken som ½. */
        private fun String.startsWithNumber(): Boolean = when (Character.getType(codePointAt(0)).toByte()) {
            Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
            else -> false
        }
    }
}

private fun String.splitWhere(isSeparator: (Char) -> Boolean): List<String> {
    val parts = mutableListOf<String>()
    val current = StringBuilder()
    for (c in this) {
        if (isSeparator(c)) { parts += current.toString(); current.clear() } else current.append(c)
    }
    parts += current.toString()
    return parts
}
