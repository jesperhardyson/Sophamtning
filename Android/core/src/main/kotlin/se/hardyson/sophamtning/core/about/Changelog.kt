package se.hardyson.sophamtning.core.about

import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat

/**
 * Nyheterna i appen, tolkade från `CHANGELOG.md` som Release Please skriver. Bara texten visas: PR-nummer, commit-länkar
 * och jämförelselänkar tas bort, eftersom de är till för utvecklarna.
 */
object Changelog {
    data class Version(
        val version: String,
        /** "1.1.0 · 10 november 2026", eller bara versionen när datumet saknas. */
        val title: String,
        val sections: List<Section>,
    ) {
        val id: String get() = version
    }

    data class Section(val title: String, val items: List<String>) {
        val id: String get() = title
    }

    /** Delarna som visas, i Release Please-konfigurationens namn. Övriga, som brytande ändringar, är för utvecklare. */
    internal val shownSections = setOf("Nytt", "Rättat", "Snabbare")

    /**
     * Versioner som inte visas. `CHANGELOG.md` skrivs av Release Please och ändras aldrig för hand, så det som inte är för
     * användarna döljs här. På iOS döljs 1.0.0, men Android-appens 1.0.0 ska visas, så här döljs ingen.
     */
    val hiddenVersions: Set<String> = emptySet()

    private val versionLink = Regex("""\[([^\]]+)\]""")
    private val date = Regex("""\((\d{4}-\d{2}-\d{2})\)""")
    private val itemLink = Regex("""\s*\(\[[^\]]*\]\([^)]*\)\)""")
    private val scope = Regex("""^\*\*[^*]+:\*\*\s*""")

    /** Versionerna i filens ordning, som är nyast först. Versioner utan någon visad rad, och de i [hiding], hoppas över. */
    fun parse(markdown: String, hiding: Set<String> = hiddenVersions): List<Version> {
        val versions = mutableListOf<Version>()
        var current: Pair<String, String>? = null
        var sections = mutableListOf<Section>()
        var section: Pair<String, MutableList<String>>? = null

        fun closeSection() {
            val open = section
            if (open != null && open.first in shownSections && open.second.isNotEmpty()) sections += Section(open.first, open.second.toList())
            section = null
        }

        fun closeVersion() {
            closeSection()
            val open = current
            if (open != null && sections.isNotEmpty() && open.first !in hiding) versions += Version(open.first, open.second, sections)
            current = null
            sections = mutableListOf()
        }

        for (raw in markdown.split("\n")) {
            val line = raw.trimSpaces()
            when {
                line.startsWith("## ") -> {
                    closeVersion()
                    current = heading(line.drop(3))
                }
                line.startsWith("### ") -> {
                    closeSection()
                    if (current != null) section = line.drop(4).trimSpaces() to mutableListOf()
                }
                (line.startsWith("* ") || line.startsWith("- ")) && section != null -> {
                    val text = item(line.drop(2))
                    if (text.isNotEmpty()) section?.second?.add(text)
                }
            }
        }
        closeVersion()
        return versions
    }

    /** "[1.1.0](url) (2026-11-10)" eller "1.0.0 (2026-11-08)" blir versionen och rubriken. */
    private fun heading(text: String): Pair<String, String> {
        val version = versionLink.find(text)?.groupValues?.get(1) ?: text.takeWhile { it != ' ' }
        val day = date.find(text)?.groupValues?.get(1)?.let(DayDate::parse) ?: return version to version
        return version to "$version · ${SwedishFormat.dayMonthYear(day)}"
    }

    /** "**scope:** Text ([#53](url)) ([b7e13ad](url))" blir "Text". */
    private fun item(text: String): String = text.replace(itemLink, "").replace(scope, "").trimSpaces()

    /** Som `trimmingCharacters(in: .whitespaces)` på iOS: mellanslag och tabb, men inte radbrytningar. */
    private fun String.trimSpaces() = trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
}
