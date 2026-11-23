package se.hardyson.sophamtning.core.api

import io.ktor.client.plugins.HttpTimeoutCapability
import io.ktor.http.HttpHeaders
import java.io.IOException
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import se.hardyson.sophamtning.core.dates.DayDate

private fun day(iso: String) = DayDate.parse(iso)!!

private fun JsonObject.with(key: String, value: kotlinx.serialization.json.JsonElement) =
    JsonObject(this + (key to value))

class SoporClientTest {
    @Test
    fun avkodarAdressMedOkandaFalt() = runTest {
        val json = Json.parseToJsonElement(fixture("adress")).jsonObject
        val address = json.getValue("address").jsonObject.with("nyttFalt", JsonPrimitive("x"))
        val body = json.with("framtidaFalt", buildJsonObject { put("a", 1) }).with("address", address)
        val r = Stub(body = body.toString()).client().address(TEST_URL)
        assertEquals("storgatan-2_uppsala-4004688", r.address.id)
        assertEquals(day("2026-11-06"), r.today)
        assertTrue(r.next.isNotEmpty())
        assertEquals("Mat", r.fractions["mat"]?.short)
        assertNull(r.events.first().deviation)
        assertEquals("sopor.hardyson.se", URI(r.links.web).host)
    }

    @Test
    fun tolAndrasFraktionsId() = runTest {
        val r = Stub(body = fixture("okand-fraktion")).client().address(TEST_URL)
        assertTrue(r.events.any { "tradgard" in it.fractions })
        assertNull(r.fractions["tradgard"])
    }

    @Test
    fun behallerUrlMedAaoOchProcent() = runTest {
        val stub = Stub(body = fixture("sok"))
        val client = stub.client()
        val hit = client.search("storgatan 2", null).addresses.first { it.id == "storgatan-2_kåge-124167" }
        assertTrue("k%C3%A5ge" in hit.url)
        // anropet går exakt till den sparade adressen, utan dubbel kodning
        stub.body = fixture("adress-kage")
        client.address(hit.url)
        assertEquals(hit.url, stub.requests.last().url.toString())
    }

    @Test
    fun delvisSokningBehallerTraffarOchFailed() = runTest {
        val r = Stub(body = fixture("sok-delvis")).client().search("storgatan 2", null)
        assertEquals(listOf("uppsala"), r.failed)
        assertTrue(r.addresses.isNotEmpty())
    }

    @Test
    fun statuskoderMappas() = runTest {
        val cases = listOf(400 to ApiError.BadRequest, 404 to ApiError.NotFound, 502 to ApiError.SourceUnavailable, 500 to ApiError.Unexpected(500))
        for ((status, expected) in cases) {
            val error = assertFailsWith<ApiError> { Stub(status = status, body = "{}").client().address(TEST_URL) }
            assertEquals(expected, error, "status $status")
        }
    }

    @Test
    fun natfelBlirNetwork() = runTest {
        val error = assertFailsWith<ApiError> { Stub(error = IOException("tidsgräns")).client().sources() }
        assertEquals(ApiError.Network, error)
    }

    @Test
    fun ogiltigtSvarBlirUnexpected() = runTest {
        val error = assertFailsWith<ApiError> { Stub(body = "inte json").client().address(TEST_URL) }
        assertEquals(ApiError.Unexpected(200), error)
    }

    @Test
    fun sokningKodarQueryOchSkickarUserAgent() = runTest {
        val stub = Stub(body = fixture("sok"))
        stub.client().search("storgatan 2, örebro", "orebro")
        val request = stub.requests.first()
        assertEquals("https://sopor.hardyson.se/api/v1/sok?q=storgatan%202%2C%20%C3%B6rebro&kalla=orebro", request.url.toString())
        assertEquals("Sophamtning-Android/9.9.9", request.headers[HttpHeaders.UserAgent])
        assertEquals("application/json", request.headers[HttpHeaders.Accept])
        assertEquals(15_000L, request.getCapabilityOrNull(HttpTimeoutCapability)?.requestTimeoutMillis)
    }

    @Test
    fun sokningUtanKallaSkickarInteKalla() = runTest {
        val stub = Stub(body = fixture("sok"))
        stub.client().search("a+b", null)
        assertEquals("https://sopor.hardyson.se/api/v1/sok?q=a%2Bb", stub.requests.first().url.toString())
    }

    @Test
    fun saknadSelectionBlirAddress() = runTest {
        val body = """
            {"apiVersion":"1","failed":[],"addresses":[{"id":"a_b-1","street":"A","locality":"B",
            "kommun":"C","source":"s","detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a_b-1"}]}
        """.trimIndent()
        val hit = Stub(body = body).client().search("a", null).addresses.first()
        assertEquals("address", hit.selection)
        assertFalse(hit.isArea)
        assertNull(hit.notice)
        assertNull(hit.areasUrl)
    }

    @Test
    fun trasigtAreasUrlGerTraffUtanLank() = runTest {
        for (value in listOf("\"\"", "\"   \"", "123", "{}", "\"http://exa mple\"")) {
            val body = """
                {"apiVersion":"1","failed":[],"addresses":[{"id":"a_b-1","street":"A","locality":"B",
                "kommun":"C","source":"s","detail":null,"areasUrl":$value,"url":"https://sopor.hardyson.se/api/v1/adress/s/a_b-1"}]}
            """.trimIndent()
            val hit = Stub(body = body).client().search("a", null).addresses.first()
            assertNull(hit.areasUrl, "areasUrl $value")
        }
    }

    @Test
    fun omradenAvkodasOchArOmraden() = runTest {
        val stub = Stub(body = fixture("omraden"))
        val r = stub.client().areas("Avesta")
        assertTrue(r.addresses.all { it.isArea })
        assertNotNull(r.addresses.first().areasUrl)
        assertEquals("https://sopor.hardyson.se/api/v1/omraden?plats=Avesta", stub.requests.first().url.toString())
    }

    @Test
    fun omradenMedTomningSkickarDatumet() = runTest {
        val stub = Stub(body = fixture("omraden-tomning"))
        stub.client().areas("Avesta", day("2026-11-03"))
        assertEquals("https://sopor.hardyson.se/api/v1/omraden?plats=Avesta&tomning=2026-11-03", stub.requests.first().url.toString())
    }

    @Test
    fun kallorFiltrerarBortTestdata() = runTest {
        val json = Json.parseToJsonElement(fixture("kallor")).jsonObject
        val sources = json.getValue("sources").jsonArray
        val test = sources[0].jsonObject.with("id", JsonPrimitive("testkalla")).with("testData", JsonPrimitive(true))
        val body = json.with("sources", JsonArray(sources + test))
        val r = Stub(body = body.toString()).client().sources()
        assertTrue(r.sources.isNotEmpty())
        assertFalse(r.sources.any { it.id == "testkalla" || it.testData })
        assertTrue(r.sources.first().kommuner.isNotEmpty())
    }

    @Test
    fun avkodarAvvikelseOchKarl() = runTest {
        val r = Stub(body = fixture("adress-avvikelse")).client().address(TEST_URL)
        assertEquals(Deviation(day("2026-11-10"), "Flyttad på grund av helg"), r.events[0].deviation)
        assertEquals(Deviation(null, "Julhelgen"), r.events[1].deviation)
        assertNull(r.events[2].deviation)
        assertEquals(2, r.bins.size)
        assertEquals(Bin("mat", 140, 26, "Varannan vecka"), r.bins[0])
        assertEquals(Bin("karl", null, null, null), r.bins[1])
    }

    @Test
    fun adressHallerRundgang() {
        for (name in listOf("adress", "adress-avvikelse", "adress-kage", "adress-avesta")) {
            val first = ApiDecoding.addressResponse(fixture(name))
            val again = ApiDecoding.addressResponse(ApiDecoding.json.encodeToString(AddressResponse.serializer(), first))
            assertEquals(first, again, name)
        }
    }
}
