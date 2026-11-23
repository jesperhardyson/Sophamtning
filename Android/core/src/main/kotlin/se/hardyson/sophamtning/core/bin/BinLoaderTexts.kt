package se.hardyson.sophamtning.core.bin

import kotlin.random.Random

/** Sopors roliga texter, ordagrant från `index.html`, plus Louies hälsning sist. Som `BinLoaderTexts` på iOS. */
object BinLoaderTexts {
    val ALL: List<String> = listOf(
        "Slänger rester från middagen…", "Äter upp det sista i kylen först…", "Tackar av gårdagens gratäng…", "Skrapar ur stekpannan…", "Bananen hann bli för brun…",
        "Plattar till pizzakartongen…", "Trycker ner en kartong till…", "Får inte ner lådan. Provar igen…", "Tar bort tejpen från paketet…", "Viker ihop nätshoppandet…",
        "Sköljer ur yoghurtburken…", "Letar efter rätt lock…", "Är det här ens plast?", "Klämmer ihop flaskan…", "Sköljer lagom mycket…",
        "Rullar ut kärlet till vägen…", "Oj, är det redan tömning i dag?", "Springer efter sopbilen…", "Hoppas på att grannen har plats…", "Lyfter på locket försiktigt…", "Sorterar som ett proffs…",
        "Tjabba, tjena hallå! /Louie",
    )

    /** En slumpad text som aldrig är samma som [after]. */
    fun next(after: String?, random: Random = Random.Default): String {
        val candidates = ALL.filter { it != after }
        return if (candidates.isEmpty()) ALL[0] else candidates.random(random)
    }

    /**
     * Webbens kö (`kvar`): alla texter visas i slumpad ordning innan någon upprepas. När kön är tom fylls den på igen, och
     * första texten blir aldrig samma som den sista i förra omgången.
     */
    class Queue {
        private val remaining = mutableListOf<String>()
        private var last: String? = null

        fun next(random: Random = Random.Default): String {
            if (remaining.isEmpty()) remaining += ALL
            var index = random.nextInt(remaining.size)
            if (remaining[index] == last && remaining.size > 1) index = (index + 1) % remaining.size
            val text = remaining.removeAt(index)
            last = text
            return text
        }
    }
}
