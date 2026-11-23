package se.hardyson.sophamtning.core.search

import java.text.Normalizer
import java.util.Locale
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.graphemeCount

/**
 * Sökfältet i områdesvalet. Som på webbens områdessida räcker det att varje sökord är början på ett ord i områdets
 * namn, etikett, dag, platser eller söktermer. Skiftläge och diakritiska tecken spelar ingen roll, utom å, ä och ö,
 * som är egna bokstäver ("ostra" är inte "Östra"). Saknar området detaljer matchar bara namnet.
 */
object AreaFilter {
    /** Småord i områdesnamn ("m.fl.", "och", "del av"). De går inte att söka på, annars ger "fl" nästan alla områden. */
    private val fillerWords = setOf("m", "fl", "och", "del", "av", "om", "by")

    /** Kortaste frågan som filtrerar, som på webben. */
    const val minimumLength = 2

    /** Träffarna i samma ordning som listan. Ett tomt fält, eller en fråga på färre än 2 tecken, ger alla. */
    fun filter(hits: List<SearchHit>, query: String): List<SearchHit> {
        // Som på webben filtreras det först från 2 tecken. Ett enda tecken ger alla områden.
        if (query.trim(Char::isWhitespace).graphemeCount() < minimumLength) return hits
        val normalized = normalize(query)
        if (normalized.isEmpty()) return hits
        // Småord i frågan räknas inte, och en fråga med bara småord ger inga träffar.
        val tokens = normalized.split(' ').filter { it.isNotEmpty() && it !in fillerWords }
        if (tokens.isEmpty()) return emptyList()
        return hits.filter { matches(tokens, it) }
    }

    private fun matches(tokens: List<String>, hit: SearchHit): Boolean {
        val words = fields(hit).flatMap { normalize(it).split(' ').filter(String::isNotEmpty) }.filter { it !in fillerWords }
        return tokens.all { token -> words.any { it.startsWith(token) } }
    }

    private fun fields(hit: SearchHit): List<String> {
        val area = hit.area ?: return listOf(hit.street)
        return listOfNotNull(hit.street, area.label, area.day) + area.places + area.searchTerms
    }

    /** Gemener, ett mellanslag mellan orden och diakriter bort, utom å, ä och ö. */
    internal fun normalize(text: String): String {
        // NFC först, så att ett å skrivet som a och en ring också räknas som å, som när Swift jämför tecken.
        val lowered = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFC)
            .replace('å', '\u0001').replace('ä', '\u0002').replace('ö', '\u0003')
        val stripped = Normalizer.normalize(lowered, Normalizer.Form.NFD).codePoints()
            .filter { !isNonBase(it) }
            .collect(::StringBuilder, StringBuilder::appendCodePoint, StringBuilder::append).toString()
        val restored = stripped.replace('\u0001', 'å').replace('\u0002', 'ä').replace('\u0003', 'ö')
        // Allt som inte är bokstäver, siffror eller tecken som hör till dem delar orden, som `CharacterSet.alphanumerics`.
        val words = mutableListOf<String>()
        val current = StringBuilder()
        restored.codePoints().forEach { cp ->
            if (isAlphanumeric(cp)) current.appendCodePoint(cp) else if (current.isNotEmpty()) { words += current.toString(); current.clear() }
        }
        if (current.isNotEmpty()) words += current.toString()
        return words.joinToString(" ")
    }

    /** Som `CharacterSet.nonBaseCharacters`: kombinerande tecken. */
    private fun isNonBase(cp: Int) = when (Character.getType(cp).toByte()) {
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> true
        else -> false
    }

    /** Som `CharacterSet.alphanumerics`: bokstäver, tal och kombinerande tecken. */
    private fun isAlphanumeric(cp: Int) = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER, Character.MODIFIER_LETTER,
        Character.OTHER_LETTER, Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER,
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> true
        else -> false
    }
}
