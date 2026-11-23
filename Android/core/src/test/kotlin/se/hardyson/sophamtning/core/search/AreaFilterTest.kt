package se.hardyson.sophamtning.core.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.AreaDetails
import se.hardyson.sophamtning.core.api.SearchHit

private fun hit(id: String, name: String, area: AreaDetails? = null, detail: String? = null) = SearchHit(
    id = id, street = name, locality = "", kommun = "Avesta kommun", source = "avesta", detail = detail, selection = "area",
    notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/avesta/$id", area = area,
)

private val hits = listOf(
    hit("1", "Askön, Nyhyttan m.fl.", area = AreaDetails(day = "Måndag, udda vecka", label = "Område 1", places = listOf("Askön", "Nyhyttan", "Klintbo"), searchTerms = listOf("trakt 1", "Åsen"))),
    hit("2", "Östra Krylbo", area = AreaDetails(day = "Tisdag, jämn vecka", label = "Område 2", places = listOf("Krylbo", "Café Hörnan"), searchTerms = emptyList())),
    hit("3", "Kaplansgården, Jularbo m.fl."),
)

private fun ids(query: String, list: List<SearchHit> = hits) = AreaFilter.filter(list, query).map { it.id }

class AreaFilterTest {
    @Test
    fun tomtFaltGerAlla() {
        assertEquals(listOf("1", "2", "3"), ids(""))
        assertEquals(listOf("1", "2", "3"), ids("   "))
    }

    @Test
    fun enEnsamBokstavFiltrerarInte() {
        // Som på webben filtreras det först från 2 tecken. Trimmat räknas, så " k " är en bokstav.
        assertEquals(listOf("1", "2", "3"), ids("k"))
        assertEquals(listOf("1", "2", "3"), ids(" k "))
        assertEquals(listOf("2"), ids("kr"))
        assertEquals(listOf("2"), ids(" kr "))
    }

    @Test
    fun namnetMatcharUtanSkiftlage() {
        assertEquals(listOf("2"), ids("KRYLBO"))
        assertEquals(listOf("3"), ids("kaplans"))
    }

    @Test
    fun ordetMatcharPaBorjan() {
        assertEquals(listOf("1"), ids("nyh"))
        // Mitt i ett ord är ingen träff.
        assertTrue(ids("yhyttan").isEmpty())
    }

    @Test
    fun etiketten() {
        assertEquals(listOf("2"), ids("område 2"))
        assertEquals(listOf("1"), ids("omr 1"))
    }

    @Test
    fun dagen() {
        assertEquals(listOf("1"), ids("måndag"))
        assertEquals(listOf("2"), ids("jämn vecka"))
    }

    @Test
    fun platserna() {
        assertEquals(listOf("1"), ids("klintbo"))
        assertEquals(listOf("2"), ids("hörnan"))
    }

    @Test
    fun soktermerna() {
        assertEquals(listOf("1"), ids("trakt 1"))
        assertEquals(listOf("1"), ids("åsen"))
    }

    @Test
    fun allaOrdenMasteFinnasIEttOmrade() {
        assertEquals(listOf("2"), ids("krylbo tisdag"))
        assertTrue(ids("krylbo måndag").isEmpty())
    }

    @Test
    fun diakriterOverSvenskaBokstaver() {
        // é och e är samma, men å, ä och ö är egna bokstäver, som på webben.
        assertEquals(listOf("2"), ids("cafe"))
        assertEquals(listOf("2"), ids("café"))
        assertEquals(listOf("2"), ids("östra"))
        assertTrue(ids("ostra").isEmpty())
        assertTrue(ids("asen").isEmpty())
    }

    @Test
    fun saknadeFaltMatcharBaraNamnet() {
        assertEquals(listOf("3"), ids("jularbo"))
        assertTrue(ids("måndag", listOf(hits[2])).isEmpty())
        assertTrue(ids("område", listOf(hits[2])).isEmpty())
    }

    @Test
    fun detailAnvandsInteSomFalt() {
        val plain = listOf(hit("9", "Fors", detail = "Torsdag · Område 9"))
        assertTrue(ids("torsdag", plain).isEmpty())
    }

    @Test
    fun smaordenRackerInteEnsamma() {
        // "m.fl." står i många namn men ger ingen träff på egen hand.
        assertTrue(ids("fl").isEmpty())
        assertTrue(ids("och").isEmpty())
        // Ett småord bredvid ett riktigt sökord räknas inte med.
        assertEquals(listOf("2"), ids("krylbo och"))
    }

    @Test
    fun ordningenBehalls() {
        assertEquals(listOf("2", "1"), AreaFilter.filter(hits.reversed(), "omr").map { it.id })
    }

    @Test
    fun utanTraffarArListanTom() {
        assertTrue(ids("zzz").isEmpty())
    }

    @Test
    fun tecknenFarInteGoraAttNagotSaknas() {
        assertEquals(listOf("1"), ids("askön,"))
        assertEquals(listOf("1"), ids("m.fl. askön"))
    }

    // Tillagt på Android: å skrivet som a och en ring (NFD) är samma bokstav som å, som i Swift.
    @Test
    fun sammansattAaRaknasSomAa() {
        assertEquals(listOf("1"), ids("åsen"))
    }
}
