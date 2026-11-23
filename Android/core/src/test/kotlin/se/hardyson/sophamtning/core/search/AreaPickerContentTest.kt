package se.hardyson.sophamtning.core.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.AreaDetails
import se.hardyson.sophamtning.core.api.SearchHit

private fun hit(id: String, name: String, places: List<String> = emptyList()) = SearchHit(
    id = id, street = name, locality = "", kommun = "Avesta kommun", source = "avesta", detail = null, selection = "area",
    notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/avesta/$id",
    area = AreaDetails(day = "Måndag, udda vecka", label = null, places = places),
)

private val hits = listOf(
    hit("1", "Askön, Nyhyttan m.fl.", places = listOf("Askön", "Nyhyttan", "Klintbo")),
    hit("2", "Kaplansgården, Jularbo m.fl."),
)

/** Områdesvalet: varningen, raden Hitta område och texten när inget matchar. */
class AreaPickerContentTest {
    @Test
    fun tomtFaltVisarVarningenOchHittaOmradeForst() {
        val content = AreaPickerContent.make(hits, query = "", hasFinder = true)
        assertEquals(listOf("1", "2"), content.hits.map { it.id })
        assertTrue(content.showsWarning)
        assertTrue(content.showsFinderFirst)
        assertNull(content.emptyText)
        assertFalse(content.showsFinderWhenEmpty)
    }

    @Test
    fun enEnsamBokstavArIngenSokning() {
        val content = AreaPickerContent.make(hits, query = " k ", hasFinder = true)
        assertEquals(2, content.hits.size)
        assertTrue(content.showsWarning)
        assertTrue(content.showsFinderFirst)
    }

    @Test
    fun underSokningVisasBaraTraffarna() {
        // En plats som bara står i listan över platser hittar rätt område.
        val content = AreaPickerContent.make(hits, query = "klintbo", hasFinder = true)
        assertEquals(listOf("1"), content.hits.map { it.id })
        assertFalse(content.showsWarning)
        assertFalse(content.showsFinderFirst)
        assertNull(content.emptyText)
    }

    @Test
    fun ingaTraffarGerTextOchHittaOmradeSomVagVidare() {
        val content = AreaPickerContent.make(hits, query = " zzz ", hasFinder = true)
        assertTrue(content.hits.isEmpty())
        assertEquals("Inga områden matchar ”zzz”.", content.emptyText)
        assertTrue(content.showsFinderWhenEmpty)
        assertFalse(content.showsFinderFirst)
        assertFalse(content.showsWarning)
    }

    @Test
    fun utanOrtFinnsIngenHittaOmrade() {
        assertFalse(AreaPickerContent.make(hits, query = "", hasFinder = false).showsFinderFirst)
        assertFalse(AreaPickerContent.make(hits, query = "zzz", hasFinder = false).showsFinderWhenEmpty)
    }
}
