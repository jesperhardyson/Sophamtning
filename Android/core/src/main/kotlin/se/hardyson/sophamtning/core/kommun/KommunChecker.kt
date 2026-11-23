package se.hardyson.sophamtning.core.kommun

import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.graphemeCount

data class KommunRow(
    val code: String,
    val name: String,
    /** Källan som täcker kommunen, annars `null`. */
    val sourceId: String?,
)

sealed interface KommunAnswer {
    data object Empty : KommunAnswer

    data class Covered(val row: KommunRow, val viaPlace: String?) : KommunAnswer

    data class NotYet(val row: KommunRow) : KommunAnswer

    data class Multiple(val place: String, val rows: List<KommunRow>) : KommunAnswer

    data class Suggestions(val suggestions: List<String>) : KommunAnswer

    data object Unknown : KommunAnswer

    /** Källistan saknas, så det går inte att säga om kommunen täcks. */
    data object Unavailable : KommunAnswer
}

/** Svarar på "Finns min kommuns hämtningsschema?". */
object KommunChecker {
    internal const val minLength = 2
    internal const val maxSuggestions = 5

    /**
     * `sources = null` betyder att källistan saknas, och då går det inte att svara om en kommun täcks.
     * En tom lista betyder att listan finns men att inget täcks.
     */
    fun check(query: String, index: PlaceIndex, sources: List<Source>?): KommunAnswer {
        val text = query.trim(Char::isWhitespace)
        if (text.graphemeCount() < minLength) return KommunAnswer.Empty

        // Kommunnamnet går före orten: "Mora" gäller Mora kommun.
        val kommunCodes = index.kommunCodes(text)
        if (kommunCodes.isNotEmpty()) {
            if (sources == null) return KommunAnswer.Unavailable
            val rows = rows(kommunCodes, index, sources)
            if (rows.size == 1) return answer(rows[0], viaPlace = null)
            return KommunAnswer.Multiple(place = text, rows = rows)
        }

        val place = index.place(text)
        if (place != null) {
            if (sources == null) return KommunAnswer.Unavailable
            val rows = rows(place.codes, index, sources)
            if (rows.size == 1) return answer(rows[0], viaPlace = place.name)
            return KommunAnswer.Multiple(place = if (place.mergedSpellings) text else place.name, rows = rows)
        }

        val suggestions = index.suggestions(text, maxSuggestions)
        return if (suggestions.isEmpty()) KommunAnswer.Unknown else KommunAnswer.Suggestions(suggestions)
    }

    private fun answer(row: KommunRow, viaPlace: String?): KommunAnswer =
        if (row.sourceId == null) KommunAnswer.NotYet(row) else KommunAnswer.Covered(row, viaPlace)

    private fun rows(codes: List<String>, index: PlaceIndex, sources: List<Source>): List<KommunRow> {
        // Täcker flera källor samma kommun gäller den första i listan.
        val sourceByCode = mutableMapOf<String, String>()
        val sourceNames = mutableMapOf<String, String>()
        for (source in sources) {
            for (kommun in source.kommuner) {
                if (kommun.code in sourceByCode) continue
                sourceByCode[kommun.code] = source.id
                sourceNames[kommun.code] = kommun.name
            }
        }
        // Källans namn gäller när kommunen täcks ("Gotlands kommun" i stället för "Region Gotland").
        return codes.sorted().map { code ->
            KommunRow(code = code, name = sourceNames[code] ?: index.kommunName(code) ?: code, sourceId = sourceByCode[code])
        }
    }
}
