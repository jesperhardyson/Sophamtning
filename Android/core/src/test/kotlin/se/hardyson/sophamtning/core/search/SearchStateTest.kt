package se.hardyson.sophamtning.core.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse

private fun hit(id: String, selection: String = "address") = SearchHit(
    id = id, street = "Storgatan $id", locality = "Örebro", kommun = "Örebro kommun", source = "orebro", detail = null,
    selection = selection, notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/orebro/$id",
)

private fun resp(hits: List<SearchHit>, failed: List<String>) = SearchResponse(addresses = hits, failed = failed)

class SearchStateTest {
    @Test
    fun tomListaOchFailedBetyderForsokIgen() {
        assertEquals(SearchState.SourcesFailed(listOf("uppsala")), SearchState.from(resp(emptyList(), listOf("uppsala")), "x y"))
    }

    @Test
    fun traffarOchFailedVisasBada() {
        val hits = listOf(hit("1"), hit("2"))
        assertEquals(SearchState.Results(hits, listOf("uppsala")), SearchState.from(resp(hits, listOf("uppsala")), "storgatan"))
    }

    @Test
    fun traffarUtanFel() {
        val hits = listOf(hit("1"))
        assertEquals(SearchState.Results(hits, emptyList()), SearchState.from(resp(hits, emptyList()), "storgatan 1"))
    }

    @Test
    fun tomtOchUtanFelMedOrtGerOmradesval() {
        assertEquals(SearchState.NoHits("avesta"), SearchState.from(resp(emptyList(), emptyList()), "kvarnvägen 3, avesta"))
        assertEquals(SearchState.NoHits(null), SearchState.from(resp(emptyList(), emptyList()), "kvarnvägen 3"))
    }

    @Test
    fun ortEfterKommatecken() {
        assertEquals("avesta", SearchState.place("kvarnvägen 3, avesta"))
        assertEquals("avesta", SearchState.place("kvarnvägen, avesta"))
        assertNull(SearchState.place("kvarnvägen 3,"))
    }

    @Test
    fun ortEfterHusnummer() {
        assertEquals("avesta", SearchState.place("kvarnvägen 3 avesta"))
        assertEquals("avesta", SearchState.place("kvarnvägen 3 b avesta"))
        assertNull(SearchState.place("kvarnvägen 3 b"))
        assertNull(SearchState.place("kvarnvägen 3"))
        assertNull(SearchState.place("kvarnvägen"))
        assertEquals("södra avesta", SearchState.place("  kvarnvägen   3   södra  avesta "))
    }

    @Test
    fun ortkandidaterMedKommatecken() {
        assertEquals(listOf("Avesta"), SearchState.placeCandidates("Bergslagsgatan, Avesta"))
    }

    @Test
    fun ortkandidaterUtanKommatecken() {
        assertEquals(listOf("Bergslagsgatan Avesta", "Avesta"), SearchState.placeCandidates("Bergslagsgatan Avesta"))
        assertEquals(listOf("Upplands Väsby", "Väsby"), SearchState.placeCandidates("Storgatan Upplands Väsby"))
    }

    @Test
    fun ortkandidaterEfterHusnummer() {
        assertEquals(listOf("Avesta"), SearchState.placeCandidates("Bergslagsgatan 1 Avesta"))
        assertEquals(listOf("Avesta"), SearchState.placeCandidates("Bergslagsgatan 12 B Avesta"))
    }

    @Test
    fun ortkandidaterForBaraOrt() {
        assertEquals(listOf("Avesta"), SearchState.placeCandidates("Avesta"))
        assertEquals(listOf("Säter"), SearchState.placeCandidates("Säter"))
        assertEquals(listOf("Upplands Väsby", "Väsby"), SearchState.placeCandidates("Upplands Väsby"))
        assertEquals(listOf("avesta"), SearchState.placeCandidates(" avesta "))
    }

    @Test
    fun ortkandidaterKraverTvaTecken() {
        assertTrue(SearchState.placeCandidates("a").isEmpty())
        assertTrue(SearchState.placeCandidates("").isEmpty())
        assertEquals(listOf("Storgatan B"), SearchState.placeCandidates("Storgatan B"))
    }

    @Test
    fun ortkandidaterHarHogstTvaOrd() {
        assertTrue(SearchState.placeCandidates("Storgatan 3, Södra Avesta by").isEmpty())
        assertTrue(SearchState.placeCandidates("Storgatan 3 Södra Avesta by").isEmpty())
        assertTrue(SearchState.placeCandidates("Storgatan 3").isEmpty())
    }
}
