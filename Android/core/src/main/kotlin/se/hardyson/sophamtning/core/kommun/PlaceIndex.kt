package se.hardyson.sophamtning.core.kommun

import java.io.IOException
import java.text.Normalizer
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import se.hardyson.sophamtning.core.graphemeCount

/** Ortlistan: kommuner och orter som pekar på kommunkoder. Uppslagstabellerna byggs en gång när indexet skapas. */
class PlaceIndex(private val kommuner: Map<String, String>, orter: Map<String, List<String>>) {
    internal data class Place(
        /** Ortens stavning i listan. */
        val name: String,
        val codes: List<String>,
    )

    /** Orten eller orterna som en söktext pekar ut. */
    internal data class PlaceMatch(
        /** Stavningen från listan. Vid flera stavningar den första. */
        val name: String,
        val codes: List<String>,
        /** Sant när flera stavningar slagits ihop (Alby och Älby). */
        val mergedSpellings: Boolean,
    )

    private data class Suggestion(val key: String, val name: String, val length: Int)

    @Serializable
    private data class FileFormat(val kommuner: Map<String, String>, val orter: Map<String, List<String>>)

    /** Normaliserad kommunstam till kommunkoder i kodordning. */
    private val kommunerByStem: Map<String, List<String>>

    /** Normaliserat ortnamn till orter, i bokstavsordning. */
    private val placesByKey: Map<String, List<Place>>

    /** Orter och kommuner för förslag, kortast först och sedan i bokstavsordning. */
    private val suggestionList: List<Suggestion>

    init {
        val stems = mutableMapOf<String, MutableList<String>>()
        for ((code, name) in kommuner.toSortedMap()) stems.getOrPut(kommunStem(name)) { mutableListOf() } += code
        kommunerByStem = stems

        val byKey = mutableMapOf<String, MutableList<Place>>()
        val all = mutableListOf<Suggestion>()
        for ((name, codes) in orter) {
            byKey.getOrPut(normalize(name)) { mutableListOf() } += Place(name, codes)
            all += Suggestion(key = normalize(name), name = name, length = name.graphemeCount())
        }
        val places = byKey.mapValues { (_, list) -> list.sortedBy { it.name } }
        placesByKey = places

        // Kommunens namn som stam utan "kommun" och "Region". Genitiv-s tas bara bort när resten är en ort
        // (Stockholms -> Stockholm, men Alingsås förblir Alingsås).
        val seen = all.map { it.name }.toMutableSet()
        for (name in kommuner.values) {
            var display = stripKommunWords(name)
            if (display.graphemeCount() > 1 && display.lowercase(Locale.ROOT).endsWith("s")) {
                val shorter = display.dropLast(1)
                if (places[normalize(shorter)] != null) display = shorter
            }
            if (seen.add(display)) all += Suggestion(key = normalize(display), name = display, length = display.graphemeCount())
        }
        suggestionList = all.sortedWith(compareBy<Suggestion> { it.length }.thenBy { it.name })
    }

    // Uppslag

    internal val kommunCount: Int get() = kommuner.size
    internal val placeCount: Int get() = placesByKey.values.sumOf { it.size }

    internal fun kommunName(code: String): String? = kommuner[code]

    /**
     * Kommunerna som söktexten pekar ut med namn, med eller utan "kommun", "Region" och genitiv-s.
     * Har söktexten diakritiska tecken och någon stavning stämmer exakt gäller bara de.
     * Annars gäller alla med samma namn utan diakritiska tecken (Habo och Håbo).
     */
    internal fun kommunCodes(query: String): List<String> {
        val codes = kommunerByStem[kommunStem(query)].orEmpty()
        if (codes.size <= 1 || !hasDiacritics(query)) return codes
        val wanted = stemKeepingDiacritics(query)
        val exact = codes.filter { stemKeepingDiacritics(kommuner[it] ?: "") == wanted }
        return exact.ifEmpty { codes }
    }

    /** Orten eller orterna som söktexten pekar ut. Samma regel för stavning som för kommuner. */
    internal fun place(query: String): PlaceMatch? {
        val candidates = placesByKey[normalize(query)] ?: return null
        var chosen = candidates
        if (candidates.size > 1 && hasDiacritics(query)) {
            val wanted = caseFolded(query)
            val exact = candidates.filter { caseFolded(it.name) == wanted }
            if (exact.isNotEmpty()) chosen = exact
        }
        val codes = mutableListOf<String>()
        for (code in chosen.flatMap { it.codes }) if (code !in codes) codes += code
        return PlaceMatch(name = chosen[0].name, codes = codes, mergedSpellings = chosen.size > 1)
    }

    /** Orter och kommuner som börjar med söktexten, kortast först. */
    internal fun suggestions(prefix: String, limit: Int): List<String> {
        val key = normalize(prefix)
        val result = mutableListOf<String>()
        for (entry in suggestionList) {
            if (!entry.key.startsWith(key)) continue
            result += entry.name
            if (result.size == limit) break
        }
        return result
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Läses och byggs bara första gången. */
        private val cached: Result<PlaceIndex> by lazy {
            runCatching {
                val stream = PlaceIndex::class.java.getResourceAsStream("/orter.json") ?: throw IOException("orter.json saknas")
                val file = json.decodeFromString(FileFormat.serializer(), stream.use { it.readBytes().decodeToString() })
                PlaceIndex(kommuner = file.kommuner, orter = file.orter)
            }
        }

        /** Ortlistan som följer med appen, som `bundled()` på iOS. Filen läses och tabellerna byggs bara första gången. */
        fun load(): PlaceIndex = cached.getOrThrow()

        // Normalisering

        /**
         * Skiftläge och diakritiska tecken spelar ingen roll, så å, ä och ö jämförs som a och o. Som
         * `folding(options: [.caseInsensitive, .diacriticInsensitive])` på iOS: gemener, och kombinerande tecken bort.
         */
        internal fun normalize(text: String): String =
            Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD).filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }

        /** Bara gemener. I NFC, så att samma bokstav skriven på två sätt blir lika, som när Swift jämför text. */
        private fun caseFolded(text: String): String = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFC)

        /** Namnet utan inledande "Region " och avslutande " kommun", med bevarat skiftläge. */
        internal fun stripKommunWords(text: String): String {
            var s = text.trim(Char::isWhitespace)
            if (s.lowercase(Locale.ROOT).startsWith("region ")) s = s.drop("region ".length)
            if (s.lowercase(Locale.ROOT).endsWith(" kommun")) s = s.dropLast(" kommun".length)
            return s.trim(Char::isWhitespace)
        }

        /** Stammen utan "Region", "kommun" och avslutande s (genitiv), utan skiftläge men med diakritiska tecken. */
        private fun stemKeepingDiacritics(text: String): String {
            val s = caseFolded(stripKommunWords(text))
            return if (s.graphemeCount() > 1 && s.endsWith("s")) s.dropLast(1) else s
        }

        /** Som [stemKeepingDiacritics], men också utan diakritiska tecken. */
        internal fun kommunStem(text: String): String = normalize(stemKeepingDiacritics(text))

        /** Sant när söktexten har å, ä, ö eller annat diakritiskt tecken, så att stavningen är ett val. */
        private fun hasDiacritics(text: String): Boolean = caseFolded(text) != normalize(text)
    }
}
