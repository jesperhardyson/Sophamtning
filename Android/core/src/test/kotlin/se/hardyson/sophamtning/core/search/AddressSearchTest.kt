package se.hardyson.sophamtning.core.search

import java.util.Collections
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.schedule.LatestOnly

private fun hit(id: String, kommun: String = "Avesta kommun", selection: String = "address") = SearchHit(
    id = id, street = "Gata $id", locality = "", kommun = kommun, source = "avesta", detail = null, selection = selection,
    notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/avesta/$id",
)

private val avestaAreas = listOf(hit("trakt-1", selection = "area"), hit("trakt-2", selection = "area"))

/** Stubbe där `/sok` och `/omraden` svarar var för sig. Anropen till `/omraden` sparas i ordning. */
private class SearchApi(
    private val onSearch: suspend (String) -> SearchResponse,
    private val onAreas: suspend (String) -> SearchResponse,
) : SoporApi {
    val places: MutableList<String> = Collections.synchronizedList(mutableListOf())

    override suspend fun search(query: String, source: String?) = onSearch(query)
    override suspend fun areas(place: String): SearchResponse {
        places += place
        return onAreas(place)
    }
    override suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse = error("används inte")
    override suspend fun address(url: String): AddressResponse = error("används inte")
    override suspend fun sources(): SourcesResponse = error("används inte")
}

private fun empty() = SearchResponse(addresses = emptyList(), failed = emptyList())

class AreaLookupTest {
    @Test
    fun kandidaternaFragasIOrdningTillsNagonGerOmraden() = runTest {
        val api = SearchApi({ empty() }, { place -> if (place == "Avesta") SearchResponse(avestaAreas, emptyList()) else empty() })
        val result = AreaLookup.run("Bergslagsgatan Avesta", api)
        assertEquals(AreaLookup.Found(place = "Avesta", areas = avestaAreas), result)
        assertEquals(listOf("Bergslagsgatan Avesta", "Avesta"), api.places)
    }

    @Test
    fun forstaTraffenAvslutar() = runTest {
        val api = SearchApi({ empty() }, { SearchResponse(avestaAreas, emptyList()) })
        AreaLookup.run("Bergslagsgatan Avesta", api)
        assertEquals(listOf("Bergslagsgatan Avesta"), api.places)
    }

    @Test
    fun hogstTreAnrop() = runTest {
        val api = SearchApi({ empty() }, { empty() })
        val result = AreaLookup.run(candidates = listOf("a1", "a2", "a3", "a4"), api = api)
        assertEquals(AreaLookup.NotFound, result)
        assertEquals(listOf("a1", "a2", "a3"), api.places)
    }

    @Test
    fun utanKandidaterGorsIngetAnrop() = runTest {
        val api = SearchApi({ empty() }, { SearchResponse(avestaAreas, emptyList()) })
        assertEquals(AreaLookup.NotFound, AreaLookup.run("Storgatan 3", api))
        assertTrue(api.places.isEmpty())
    }

    @Test
    fun felGerFailedAldrigNotFound() = runTest {
        val api = SearchApi({ empty() }, { throw ApiError.Network })
        assertEquals(AreaLookup.Failed, AreaLookup.run("Bergslagsgatan Avesta", api))
        assertEquals(listOf("Bergslagsgatan Avesta", "Avesta"), api.places)
    }

    @Test
    fun kallaSomInteSvaradeGerFailed() = runTest {
        val api = SearchApi({ empty() }, { SearchResponse(emptyList(), listOf("avesta")) })
        assertEquals(AreaLookup.Failed, AreaLookup.run("Avesta", api))
    }

    @Test
    fun felForEnKandidatHindrarInteNasta() = runTest {
        val api = SearchApi({ empty() }, { place ->
            if (place == "Avesta") SearchResponse(avestaAreas, emptyList()) else throw ApiError.Network
        })
        assertEquals(AreaLookup.Found(place = "Avesta", areas = avestaAreas), AreaLookup.run("Bergslagsgatan Avesta", api))
    }

    @Test
    fun badRequestBetyderIngaOmradenForKandidaten() = runTest {
        val api = SearchApi({ empty() }, { throw ApiError.BadRequest })
        assertEquals(AreaLookup.NotFound, AreaLookup.run("Avesta", api))
    }

    @Test
    fun omradenFoljerMedSinaKallor() = runTest {
        val sources = listOf(AreaSource(id = "avesta", name = "Avesta Vatten och Avfall", explanation = "Förklaring.", help = "Hjälp."))
        val api = SearchApi({ empty() }, { place ->
            if (place == "Avesta") SearchResponse(avestaAreas, emptyList(), sources = sources) else empty()
        })
        val result = AreaLookup.run("okänd gata 1, Avesta", api)
        assertEquals(AreaLookup.Found(place = "Avesta", areas = avestaAreas, sources = sources), result)
    }
}

class AddressSearchTest {
    @Test
    fun adressernaVantarInteFororadena() = runTest {
        val gate = CompletableDeferred<Unit>()
        val addresses = listOf(hit("1"))
        val api = SearchApi({ SearchResponse(addresses, emptyList()) }, {
            gate.await()
            SearchResponse(avestaAreas, emptyList())
        })
        val got = mutableListOf<SearchOutcome>()
        val run = launch {
            AddressSearch.run("Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        }
        runCurrent()
        assertEquals(1, got.size)
        assertEquals(SearchOutcome(SearchState.Results(hits = addresses, failed = emptyList()), areas = null), got.first())
        gate.complete(Unit)
        run.join()
        assertEquals(
            SearchOutcome(SearchState.Results(hits = addresses, failed = emptyList()), areas = AreaLookup.Found(place = "Avesta", areas = avestaAreas)),
            got.last(),
        )
        assertEquals(2, got.size)
    }

    @Test
    fun nollTraffarVantarPaOmradena() = runTest {
        val api = SearchApi({ empty() }, { SearchResponse(avestaAreas, emptyList()) })
        val got = mutableListOf<SearchOutcome>()
        AddressSearch.run("Bergslagsgatan Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        assertEquals(
            listOf(SearchOutcome(SearchState.NoHits(place = null), AreaLookup.Found(place = "Bergslagsgatan Avesta", areas = avestaAreas))),
            got,
        )
    }

    @Test
    fun avbrottVisarInteOmradena() = runTest {
        val gate = CompletableDeferred<Unit>()
        val api = SearchApi({ SearchResponse(listOf(hit("1")), emptyList()) }, {
            gate.await()
            SearchResponse(avestaAreas, emptyList())
        })
        val got = mutableListOf<SearchOutcome>()
        val run = launch {
            AddressSearch.run("Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        }
        runCurrent()
        assertEquals(1, got.size)
        run.cancel()
        gate.complete(Unit)
        run.join()
        assertEquals(1, got.size)
        assertNull(got.first().areas)
    }

    @Test
    fun gammaltOmradessvarVisasInteEfterNyareSokning() = runTest {
        val gate = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        val api = SearchApi({ SearchResponse(listOf(hit("1")), emptyList()) }, { place ->
            if (place == "Avesta") {
                started.complete(Unit)
                gate.await()
            }
            SearchResponse(avestaAreas, emptyList())
        })
        val searches = LatestOnly()
        val lookups = LatestOnly()
        val old = mutableListOf<SearchOutcome>()
        val new = mutableListOf<SearchOutcome>()
        val first = launch {
            AddressSearch.run("Avesta", null, api, searches, lookups) { old += it }
        }
        started.await()
        AddressSearch.run("Säter", null, api, searches, lookups) { new += it }
        gate.complete(Unit)
        first.join()
        assertTrue(old.all { it.areas == null })
        assertEquals(AreaLookup.Found(place = "Säter", areas = avestaAreas), new.last().areas)
    }

    @Test
    fun felIOmradenaMedAdresserGerAdresserna() = runTest {
        val addresses = listOf(hit("1"))
        val api = SearchApi({ SearchResponse(addresses, emptyList()) }, { throw ApiError.Network })
        val got = mutableListOf<SearchOutcome>()
        AddressSearch.run("Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        assertEquals(
            listOf(
                SearchOutcome(SearchState.Results(hits = addresses, failed = emptyList()), areas = null),
                SearchOutcome(SearchState.Results(hits = addresses, failed = emptyList()), areas = AreaLookup.Failed),
            ),
            got,
        )
    }

    @Test
    fun felIOmradenaVidNollTraffarGerFailed() = runTest {
        val api = SearchApi({ empty() }, { throw ApiError.Network })
        val got = mutableListOf<SearchOutcome>()
        AddressSearch.run("Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        assertEquals(listOf(SearchOutcome(SearchState.NoHits(place = null), AreaLookup.Failed)), got)
    }

    @Test
    fun sokfelVisasDirekt() = runTest {
        val api = SearchApi({ throw ApiError.SourceUnavailable }, { SearchResponse(avestaAreas, emptyList()) })
        val got = mutableListOf<SearchOutcome>()
        AddressSearch.run("Avesta", null, api, LatestOnly(), LatestOnly()) { got += it }
        assertEquals(listOf(SearchOutcome(SearchState.Failed(ApiError.SourceUnavailable), areas = null)), got)
    }
}

/** Raden Välj område står i en egen grupp, och områdesträffarna för samma kommun göms under den. */
class VisibleHitsTest {
    private val mixed = listOf(hit("1"), hit("trakt-1", selection = "area"), hit("2"), hit("trakt-9", kommun = "Mora kommun", selection = "area"))

    @Test
    fun omradenaForKommunenMedRadenGoms() {
        val lookup = AreaLookup.Found(place = "Avesta", areas = avestaAreas)
        val visible = AreaLookup.visibleHits(mixed, lookup)
        assertEquals(listOf("1", "2", "trakt-9"), visible.map { it.value.id })
        // Raderna behåller sin plats i svaret, så att inträdet inte börjar om.
        assertEquals(listOf(0, 2, 3), visible.map { it.index })
    }

    @Test
    fun utanOmradenVisasAllaTraffar() {
        assertEquals(4, AreaLookup.visibleHits(mixed, null).size)
        assertEquals(4, AreaLookup.visibleHits(mixed, AreaLookup.NotFound).size)
        assertEquals(4, AreaLookup.visibleHits(mixed, AreaLookup.Failed).size)
    }
}
