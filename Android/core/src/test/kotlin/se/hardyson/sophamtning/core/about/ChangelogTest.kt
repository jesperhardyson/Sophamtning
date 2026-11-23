package se.hardyson.sophamtning.core.about

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private val sample = """
# Changelog

## [1.1.0](https://github.com/x/y/compare/v1.0.2...v1.1.0) (2026-11-10)


### Nytt

* Förslag om påminnelse efter första adressen ([#53](https://github.com/x/y/issues/53)) ([b7e13ad](https://github.com/x/y/commit/b7e13ad))
* **hushåll:** Hushåll med delade adresser ([#60](https://github.com/x/y/issues/60)) ([1dad2b0](https://github.com/x/y/commit/1dad2b0))


### Rättat

* Pilen står till höger ([#41](https://github.com/x/y/issues/41)) ([2e9d52f](https://github.com/x/y/commit/2e9d52f))

## 1.0.0 (2026-11-08)


### ⚠ BREAKING CHANGES

* inställningarna sparas på nytt sätt

### Nytt

* Milstolpe 4, redo för App Store ([#24](https://github.com/x/y/issues/24)) ([4b1ca42](https://github.com/x/y/commit/4b1ca42))
""".trimIndent()

class ChangelogTest {
    @Test
    fun versionerNyastFörst() {
        val versions = Changelog.parse(sample, hiding = emptySet())
        assertEquals(listOf("1.1.0", "1.0.0"), versions.map { it.version })
        assertEquals("1.1.0 · 10 november 2026", versions[0].title)
        assertEquals("1.0.0 · 8 november 2026", versions[1].title)
    }

    @Test
    fun raderUtanLänkar() {
        val first = Changelog.parse(sample)[0]
        assertEquals(listOf("Nytt", "Rättat"), first.sections.map { it.title })
        assertEquals(listOf("Förslag om påminnelse efter första adressen", "Hushåll med delade adresser"), first.sections[0].items)
        assertEquals(listOf("Pilen står till höger"), first.sections[1].items)
    }

    @Test
    fun förstaVersionenVisasInte() {
        // På iOS döljs 1.0.0, som bara innehåller "Milstolpe 4, redo för App Store". Android-appens 1.0.0 visas,
        // så listan är tom här, men det går fortfarande att dölja en version.
        val versions = Changelog.parse(sample, hiding = setOf("1.0.0"))
        assertEquals(listOf("1.1.0"), versions.map { it.version })
        assertEquals(emptySet(), Changelog.hiddenVersions)
    }

    @Test
    fun tekniskaDelarVisasInte() {
        // Delar som inte är Nytt, Rättat eller Snabbare visas inte, till exempel listan över brytande ändringar.
        val old = Changelog.parse(sample, hiding = emptySet())[1]
        assertEquals(listOf("Nytt"), old.sections.map { it.title })
        assertEquals(listOf("Milstolpe 4, redo för App Store"), old.sections[0].items)
    }

    @Test
    fun tomOchTrasigText() {
        assertTrue(Changelog.parse("").isEmpty())
        assertTrue(Changelog.parse("# Changelog\n\nnågot annat").isEmpty())
        // En version utan datum visas med bara versionen.
        assertEquals("2.0.0", Changelog.parse("## 2.0.0\n\n### Nytt\n\n* Något").first().title)
    }

    @Test
    fun riktigaChangelogenGårAttLäsa() {
        // Läser iOS-appens CHANGELOG.md tills Android-appen har en egen changelog med versioner i. Testerna körs i
        // Android/core, så filen ligger två kataloger upp. Ändrar Release Please formatet ska det märkas här.
        val file = File("../../iOS/CHANGELOG.md")
        val versions = Changelog.parse(file.readText())
        assertTrue(versions.isNotEmpty())
        assertTrue(versions.all { it.title.contains(" · ") && it.sections.isNotEmpty() })
        assertTrue(versions.flatMap { it.sections }.flatMap { it.items }.all { !it.contains("](") && !it.contains("([#") })
    }
}
