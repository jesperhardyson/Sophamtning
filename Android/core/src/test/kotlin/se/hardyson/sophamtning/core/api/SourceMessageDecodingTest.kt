package se.hardyson.sophamtning.core.api

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import se.hardyson.sophamtning.core.dates.DayDate

private fun rutter(id: String = "nya-rutter-2026", url: JsonElement = JsonNull) = JsonObject(
    mapOf(
        "id" to JsonPrimitive(id), "title" to JsonPrimitive("Hämtrutterna läggs om"), "text" to JsonPrimitive("Schemat kan bli fel."),
        "url" to url, "validFrom" to JsonPrimitive("2026-11-17"), "validTo" to JsonPrimitive("2027-03-31"),
    ),
)

private fun withMessages(messages: JsonElement?): AddressResponse {
    val json = Json.parseToJsonElement(fixture("adress")).jsonObject
    val body = if (messages == null) JsonObject(json - "messages") else JsonObject(json + ("messages" to messages))
    return ApiDecoding.addressResponse(body.toString())
}

class SourceMessageDecodingTest {
    @Test
    fun adressvaretMedMeddelanden() {
        val r = withMessages(JsonArray(listOf(rutter(), rutter("mer", JsonPrimitive("https://www.avestavatten.se/rutter")))))
        assertEquals(2, r.messages.size)
        val first = r.messages.first()
        assertEquals("nya-rutter-2026", first.id)
        assertEquals("Hämtrutterna läggs om", first.title)
        assertNull(first.url)
        assertEquals(DayDate.parse("2026-11-17"), first.validFrom)
        assertEquals(DayDate.parse("2027-03-31"), first.validTo)
        assertEquals("https://www.avestavatten.se/rutter", r.messages[1].url)
    }

    @Test
    fun adressvaretUtanMeddelandenGerTomLista() {
        assertTrue(withMessages(null).messages.isEmpty())
        assertTrue(withMessages(JsonNull).messages.isEmpty())
        val broken = withMessages(JsonPrimitive("trasigt"))
        assertTrue(broken.messages.isEmpty())
        // Resten av svaret är kvar.
        assertTrue(broken.events.isNotEmpty())
    }

    @Test
    fun ettTrasigtMeddelandeFallerInteDeAndra() {
        val broken = JsonObject(mapOf("id" to JsonPrimitive("utan-datum"), "title" to JsonPrimitive("x"), "text" to JsonPrimitive("y")))
        assertEquals(listOf("nya-rutter-2026"), withMessages(JsonArray(listOf(broken, rutter()))).messages.map { it.id })
    }

    @Test
    fun ogiltigLankTasBortMenMeddelandetVisas() {
        val r = withMessages(JsonArray(listOf(rutter(url = JsonPrimitive("http://exa mple")), rutter("b", JsonPrimitive(42)))))
        assertEquals(listOf("nya-rutter-2026", "b"), r.messages.map { it.id })
        assertTrue(r.messages.all { it.url == null })
    }
}
