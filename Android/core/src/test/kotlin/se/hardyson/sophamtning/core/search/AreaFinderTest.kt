package se.hardyson.sophamtning.core.search

import java.time.Instant
import java.util.Collections
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.Pickups
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.api.Stub
import se.hardyson.sophamtning.core.api.fixture
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.schedule.day

private fun hit(id: String = "trakt-7", pickups: Pickups? = null) = SearchHit(
    id = id, street = "Område $id", locality = "", kommun = "Avesta kommun", source = "avesta",
    detail = "Tisdag, jämn vecka · $id", selection = "area", notice = "Du väljer själv", areasUrl = null,
    url = "https://sopor.hardyson.se/api/v1/adress/avesta/$id", pickups = pickups,
)

private fun response(hits: List<SearchHit>, covered: Boolean?, failed: List<String> = emptyList()) =
    SearchResponse(addresses = hits, failed = failed, dateCovered = covered)

class AreaFinderStateTest {
    @Test
    fun enTraffGerMatch() {
        val h = hit()
        assertEquals(AreaFinderState.Match(h), AreaFinderState.from(response(listOf(h), covered = true)))
    }

    @Test
    fun fleraTraffarGerLista() {
        val a = hit("a")
        val b = hit("b")
        assertEquals(AreaFinderState.Multiple(listOf(a, b)), AreaFinderState.from(response(listOf(a, b), covered = true)))
    }

    @Test
    fun tomListaInomSchematGerIngenHamtning() {
        assertEquals(AreaFinderState.NoPickup, AreaFinderState.from(response(emptyList(), covered = true)))
    }

    @Test
    fun tomListaUtanforSchematGerUtanforSchemat() {
        assertEquals(AreaFinderState.OutsideSchedule, AreaFinderState.from(response(emptyList(), covered = false)))
    }

    @Test
    fun tomListaUtanBedomningGerFelAldrigIngenHamtning() {
        assertEquals(AreaFinderState.Failed, AreaFinderState.from(response(emptyList(), covered = null)))
    }

    @Test
    fun tomListaMedFailedGerFelAvenOmSchematTacker() {
        for (covered in listOf(true, false, null)) {
            assertEquals(AreaFinderState.Failed, AreaFinderState.from(response(emptyList(), covered = covered, failed = listOf("avesta"))), "covered $covered")
        }
    }

    @Test
    fun traffVisasAvenOmEnKallaInteSvarade() {
        val h = hit()
        assertEquals(AreaFinderState.Match(h), AreaFinderState.from(response(listOf(h), covered = null, failed = listOf("skogsbo"))))
    }
}

class AreaFinderDecodingTest {
    @Test
    fun tomningsSvaretAvkodas() = runTest {
        val stub = Stub(body = fixture("omraden-tomning"))
        val r = stub.client().areas("Avesta", day("2026-10-27"))
        assertEquals(true, r.dateCovered)
        val pickups = assertNotNull(r.addresses.first().pickups)
        assertEquals(listOf(day("2026-10-13"), day("2026-10-27")), pickups.previous)
        assertEquals(day("2026-11-10"), pickups.next)
        assertEquals("https://sopor.hardyson.se/api/v1/omraden?plats=Avesta&tomning=2026-10-27", stub.requests.first().url.toString())
    }

    @Test
    fun svarUtanNyaFaltAvkodasFortfarande() = runTest {
        val stub = Stub(body = fixture("omraden"))
        val r = stub.client().areas("Avesta")
        assertNull(r.dateCovered)
        assertTrue(r.addresses.all { it.pickups == null })
        assertEquals("plats=Avesta", stub.requests.first().url.encodedQuery)
    }

    @Test
    fun nastaKanVaraNullOchTidigareTom() = runTest {
        val body = """
        {"apiVersion":"1","failed":[],"dateCovered":true,"addresses":[{"id":"a","street":"A","locality":"","kommun":"C","source":"s",
        "detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a","pickups":{"previous":[],"next":null}}]}
        """.trimIndent()
        val p = assertNotNull(Stub(body = body).client().areas("x", day("2026-10-27")).addresses.first().pickups)
        assertTrue(p.previous.isEmpty())
        assertNull(p.next)
    }

    @Test
    fun trasigaPickupsFallerInteTraffen() = runTest {
        val body = """
        {"apiVersion":"1","failed":[],"addresses":[{"id":"a","street":"A","locality":"","kommun":"C","source":"s",
        "detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a","pickups":{"previous":["fel"],"next":5}}]}
        """.trimIndent()
        val r = Stub(body = body).client().areas("x", day("2026-10-27"))
        assertEquals(1, r.addresses.size)
        assertNull(r.addresses[0].pickups)
    }

    @Test
    fun tomningsanropMedBadRequestKastas() = runTest {
        assertFailsWith<ApiError.BadRequest> {
            Stub(status = 400, body = "{}").client().areas("Avesta", day("2026-10-27"))
        }
    }
}

class AreaFinderTextTest {
    private val today = day("2026-11-06")

    @Test
    fun tvaTidigareOchNasta() {
        val p = Pickups(previous = listOf(day("2026-10-13"), day("2026-10-27")), next = day("2026-11-10"))
        assertEquals(
            "Tömningar 13 okt och 27 okt. Nästa är 10 nov. Stämmer det? En försenad tömning kan ge fel område.",
            AreaFinderText.check(p, today),
        )
        assertEquals("Tömningar 13 okt och 27 okt. Nästa 10 nov.", AreaFinderText.summary(p, today))
    }

    @Test
    fun enTidigare() {
        val p = Pickups(previous = listOf(day("2026-11-03")), next = day("2026-11-17"))
        assertEquals("Tömning 3 nov. Nästa är 17 nov. Stämmer det? En försenad tömning kan ge fel område.", AreaFinderText.check(p, today))
    }

    @Test
    fun nastaSomPasseratVisasSomVar() {
        val p = Pickups(previous = listOf(day("2026-10-13"), day("2026-10-27")), next = day("2026-11-05"))
        assertTrue(AreaFinderText.check(p, today).contains("Nästa var 5 nov."))
        assertTrue(AreaFinderText.summary(p, today)?.endsWith("Nästa var 5 nov.") == true)
    }

    @Test
    fun nastaDagensDatumArEjPasserat() {
        val p = Pickups(previous = listOf(day("2026-10-27")), next = day("2026-11-06"))
        assertTrue(AreaFinderText.check(p, today).contains("Nästa är 6 nov."))
    }

    @Test
    fun utanNastaUtelamnasMeningen() {
        val p = Pickups(previous = listOf(day("2026-10-13"), day("2026-10-27")), next = null)
        assertEquals("Tömningar 13 okt och 27 okt. Stämmer det? En försenad tömning kan ge fel område.", AreaFinderText.check(p, today))
        assertEquals("Tömningar 13 okt och 27 okt.", AreaFinderText.summary(p, today))
    }

    @Test
    fun utanVeckodagOchUtanPickups() {
        assertEquals("Stämmer det? En försenad tömning kan ge fel område.", AreaFinderText.check(null, today))
        assertNull(AreaFinderText.summary(null, today))
    }

    @Test
    fun datumFaltetHarVeckodagOchAr() {
        assertEquals("Tisdag 27 oktober 2026", SwedishFormat.longDateWithYear(day("2026-10-27")))
        assertEquals("13 okt", SwedishFormat.dayMonth(day("2026-10-13")))
    }

    // I DayDatePickerTests på iOS. De andra testerna där gäller datumväljaren i SwiftUI.
    @Test
    fun kommunNamnVisasBaraNarTraffarnaGallerFlera() {
        fun h(k: String) = SearchHit(
            id = k, street = "S", locality = "", kommun = k, source = "s", detail = null, selection = "area", notice = null,
            areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/s/$k",
        )
        assertFalse(AreaFinderText.showsKommun(listOf(h("Avesta kommun"), h("Avesta kommun"))))
        assertTrue(AreaFinderText.showsKommun(listOf(h("Avesta kommun"), h("Hedemora kommun"))))
    }
}

// AreaFinder (modellen bakom arket)

private class FinderApi : SoporApi {
    val days: MutableList<DayDate> = Collections.synchronizedList(mutableListOf())
    var handler: suspend (DayDate) -> SearchResponse = { SearchResponse(emptyList(), emptyList(), dateCovered = true) }

    override suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse {
        days += lastEmptied
        return handler(lastEmptied)
    }
    override suspend fun search(query: String, source: String?): SearchResponse = error("används inte")
    override suspend fun areas(place: String): SearchResponse = error("används inte")
    override suspend fun address(url: String): AddressResponse = error("används inte")
    override suspend fun sources(): SourcesResponse = error("används inte")
}

/** Stockholm: 2026-11-06 12:00. */
private val nowDate = StockholmClock.dateOn(day("2026-11-06"), minutes = 12 * 60)

private fun TestScope.finder(api: FinderApi = FinderApi(), now: () -> Instant = { nowDate }) =
    AreaFinder(api, place = "Avesta", scope = backgroundScope, now = now)

class AreaFinderModelTest {
    @Test
    fun oppningenHarInteDatumOchGerInteAnrop() = runTest {
        val api = FinderApi()
        val finder = finder(api)
        assertNull(finder.date)
        assertEquals(AreaFinderState.Idle, finder.state)
        assertEquals(day("2026-11-06"), finder.latestSelectable)
        runCurrent()
        assertTrue(api.days.isEmpty())
        assertEquals(AreaFinderState.Idle, finder.state)
    }

    @Test
    fun forsokIgenUtanValtDatumGerInteAnrop() = runTest {
        val api = FinderApi()
        val finder = finder(api)
        finder.retry()
        runCurrent()
        assertTrue(api.days.isEmpty())
        assertEquals(AreaFinderState.Idle, finder.state)
    }

    @Test
    fun idagRaknasISvenskTidOavsettTidpunktetPaDygnet() = runTest {
        // 23:30 UTC den 5 november är redan den 6 november i Stockholm.
        val late = Instant.ofEpochSecond(1_793_921_400)
        assertEquals(day("2026-11-06"), finder(now = { late }).latestSelectable)
    }

    @Test
    fun framtidaDatumBegransasTillIDag() = runTest {
        val finder = finder()
        finder.find(day("2026-11-20"))
        assertEquals(day("2026-11-06"), finder.date)
    }

    @Test
    fun senastValbaraRaknasOmVidValetEfterMidnatt() = runTest {
        var clock = nowDate
        val finder = finder(now = { clock })
        finder.find(day("2026-11-07"))
        assertEquals(day("2026-11-06"), finder.date)
        // Midnatt har passerat medan arket låg öppet.
        clock = StockholmClock.dateOn(day("2026-11-07"), minutes = 5)
        assertEquals(day("2026-11-07"), finder.latestSelectable)
        finder.find(day("2026-11-07"))
        assertEquals(day("2026-11-07"), finder.date)
        finder.find(day("2026-11-08"))
        assertEquals(day("2026-11-07"), finder.date)
    }

    @Test
    fun lyckatSvarGerMatchOchEttAnrop() = runTest {
        val api = FinderApi()
        val h = hit()
        api.handler = { SearchResponse(listOf(h), emptyList(), dateCovered = true) }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        assertEquals(AreaFinderState.Searching, finder.state)
        runCurrent()
        assertEquals(AreaFinderState.Match(h), finder.state)
        assertEquals(listOf(day("2026-10-27")), api.days)
        assertFalse(finder.partial)
    }

    @Test
    fun tekniskFelGerFelAldrigIngenHamtning() = runTest {
        val api = FinderApi()
        api.handler = { throw ApiError.Network }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(AreaFinderState.Failed, finder.state)
        assertTrue(finder.retryable)
    }

    @Test
    fun badRequestGerFelUtanForsokIgen() = runTest {
        val api = FinderApi()
        api.handler = { throw ApiError.BadRequest }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(AreaFinderState.Failed, finder.state)
        assertFalse(finder.retryable)
        // Ett nytt datum nollställer.
        api.handler = { SearchResponse(emptyList(), emptyList(), dateCovered = true) }
        finder.find(day("2026-10-26"))
        assertTrue(finder.retryable)
        runCurrent()
        assertEquals(AreaFinderState.NoPickup, finder.state)
    }

    @Test
    fun traffMedFailedMarkerasSomDelvis() = runTest {
        val api = FinderApi()
        val h = hit()
        api.handler = { SearchResponse(listOf(h), listOf("skogsbo"), dateCovered = null) }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(AreaFinderState.Match(h), finder.state)
        assertTrue(finder.partial)
        assertEquals("En källa svarade inte, så fler områden kan finnas.", AreaFinderText.partialNotice)
    }

    @Test
    fun gammaltSvarErsatterAldrigNyare() = runTest {
        val api = FinderApi()
        val gate = CompletableDeferred<Unit>()
        val slow = hit("gammal")
        val fresh = hit("ny")
        api.handler = { d ->
            if (d == day("2026-10-27")) {
                gate.await()
                SearchResponse(listOf(slow), emptyList(), dateCovered = true)
            } else {
                SearchResponse(listOf(fresh), emptyList(), dateCovered = true)
            }
        }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(1, api.days.size)
        finder.find(day("2026-10-13"))
        runCurrent()
        assertEquals(AreaFinderState.Match(fresh), finder.state)
        gate.complete(Unit)
        runCurrent()
        assertEquals(AreaFinderState.Match(fresh), finder.state)
        assertEquals(day("2026-10-13"), finder.date)
    }

    @Test
    fun gammaltFelErsatterInteNyttSvar() = runTest {
        val api = FinderApi()
        val gate = CompletableDeferred<Unit>()
        val fresh = hit("ny")
        api.handler = { d ->
            if (d == day("2026-10-27")) {
                gate.await()
                throw ApiError.BadRequest
            }
            SearchResponse(listOf(fresh), emptyList(), dateCovered = true)
        }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(1, api.days.size)
        finder.find(day("2026-10-13"))
        runCurrent()
        assertEquals(AreaFinderState.Match(fresh), finder.state)
        gate.complete(Unit)
        runCurrent()
        assertEquals(AreaFinderState.Match(fresh), finder.state)
        assertTrue(finder.retryable)
    }

    @Test
    fun andratUtkastGerInteAnropOchTarBortGammaltResultat() = runTest {
        val api = FinderApi()
        val h = hit()
        api.handler = { SearchResponse(listOf(h), emptyList(), dateCovered = true) }
        val finder = finder(api)
        assertEquals(day("2026-11-06"), finder.draft)
        finder.setDraft(day("2026-10-27"))
        finder.setDraft(day("2026-10-26"))
        runCurrent()
        assertTrue(api.days.isEmpty())
        assertEquals(AreaFinderState.Idle, finder.state)
        assertNull(finder.date)

        finder.find()
        runCurrent()
        assertEquals(AreaFinderState.Match(h), finder.state)
        assertEquals(listOf(day("2026-10-26")), api.days)
        assertEquals(day("2026-10-26"), finder.date)

        // Nytt utkast: resultatet för förra datumet försvinner och inget frågas förrän knappen trycks.
        finder.setDraft(day("2026-10-24"))
        assertEquals(AreaFinderState.Idle, finder.state)
        assertNull(finder.date)
        runCurrent()
        assertEquals(listOf(day("2026-10-26")), api.days)
        finder.find()
        runCurrent()
        assertEquals(2, api.days.size)
        assertEquals(day("2026-10-24"), api.days.last())
    }

    @Test
    fun sammaUtkastBehallerResultatet() = runTest {
        val finder = finder()
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(AreaFinderState.NoPickup, finder.state)
        finder.setDraft(day("2026-10-27"))
        assertEquals(AreaFinderState.NoPickup, finder.state)
        assertEquals(day("2026-10-27"), finder.date)
    }

    @Test
    fun gammaltSvarErsatterInteEttNyttUtkast() = runTest {
        val api = FinderApi()
        val gate = CompletableDeferred<Unit>()
        api.handler = {
            gate.await()
            SearchResponse(listOf(hit()), emptyList(), dateCovered = true)
        }
        val finder = finder(api)
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(1, api.days.size)
        finder.setDraft(day("2026-10-24"))
        gate.complete(Unit)
        runCurrent()
        assertEquals(AreaFinderState.Idle, finder.state)
    }

    @Test
    fun utkastetBegransasTillIDag() = runTest {
        val finder = finder()
        finder.setDraft(day("2026-11-20"))
        assertEquals(day("2026-11-06"), finder.draft)
    }

    @Test
    fun forsokIgenAnroparMedSammaDatum() = runTest {
        val api = FinderApi()
        val finder = finder(api)
        api.handler = { throw ApiError.Network }
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(AreaFinderState.Failed, finder.state)
        api.handler = { SearchResponse(emptyList(), emptyList(), dateCovered = false) }
        finder.retry()
        runCurrent()
        assertEquals(AreaFinderState.OutsideSchedule, finder.state)
        assertEquals(listOf(day("2026-10-27"), day("2026-10-27")), api.days)
    }

    // Tillagt på Android: tillståndet som UI:t läser är ett enda oföränderligt värde i ett StateFlow.
    @Test
    fun tillstandetFinnsIEttStateFlow() = runTest {
        val finder = finder()
        finder.find(day("2026-10-27"))
        runCurrent()
        assertEquals(
            AreaFinder.Snapshot(state = AreaFinderState.NoPickup, date = day("2026-10-27"), draft = day("2026-10-27"), retryable = true, partial = false),
            finder.snapshot.value,
        )
    }
}

class AreaFinderFoundTest {
    @Test
    fun barTraffarRaknasSomFunna() {
        val h = hit()
        assertTrue(AreaFinderState.Match(h).foundAreas)
        assertTrue(AreaFinderState.Multiple(listOf(h, hit("b"))).foundAreas)
        for (state in listOf(AreaFinderState.Idle, AreaFinderState.Searching, AreaFinderState.NoPickup, AreaFinderState.OutsideSchedule, AreaFinderState.Failed)) {
            assertFalse(state.foundAreas, "$state")
        }
    }
}
