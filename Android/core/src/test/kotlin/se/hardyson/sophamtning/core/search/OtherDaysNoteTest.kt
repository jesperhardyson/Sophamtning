package se.hardyson.sophamtning.core.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.AreaDetails
import se.hardyson.sophamtning.core.api.fixture
import java.time.Instant
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress

/** Adressvaret i `adress-avesta` med fältet `area` ersatt, satt till null eller ([omit]) borttaget. */
private fun addressResponse(area: JsonElement?, omit: Boolean = false): AddressResponse {
    val json = ApiDecoding.json.parseToJsonElement(fixture("adress-avesta")).jsonObject
    val address = json.getValue("address").jsonObject
    val changed = if (omit) JsonObject(address - "area") else JsonObject(address + ("area" to (area ?: JsonNull)))
    return ApiDecoding.addressResponse(JsonObject(json + ("address" to changed)))
}

private fun area(otherDays: List<String>?) = buildJsonObject {
    put("day", "Måndag, udda vecka")
    put("label", "Område 7")
    put("places", JsonArray(listOf(JsonPrimitive("Rosse"))))
    put("otherDays", otherDays?.let { list -> JsonArray(list.map(::JsonPrimitive)) } ?: JsonNull)
    put("searchTerms", JsonArray(emptyList()))
}

class AddressAreaDecodingTest {
    @Test
    fun omradetAvkodasIAdressvaret() {
        val response = addressResponse(area(listOf("Grängesbergsgatan har hämtning på tisdagar.")))
        assertEquals(listOf("Grängesbergsgatan har hämtning på tisdagar."), response.address.area?.otherDays)
        assertEquals("Område 7", response.address.area?.label)
    }

    @Test
    fun faltetSaknasEllerArNull() {
        assertNull(addressResponse(null, omit = true).address.area)
        assertNull(addressResponse(null).address.area)
    }

    @Test
    fun trasigtFaltFallerInteAdressvaret() {
        assertNull(addressResponse(JsonPrimitive("trasig")).address.area)
        val partial = addressResponse(buildJsonObject { put("day", 3); put("otherDays", "fel") })
        assertEquals(AreaDetails(day = "", label = null, places = emptyList()), partial.address.area)
    }

    @Test
    fun sparadDataUtanFaltetAvkodasOchKodasOm() {
        val old = addressResponse(null, omit = true)
        val again = ApiDecoding.addressResponse(ApiDecoding.json.encodeToString(AddressResponse.serializer(), old))
        assertEquals(old, again)
        val withArea = addressResponse(area(listOf("En rad.")))
        assertEquals(withArea, ApiDecoding.addressResponse(ApiDecoding.json.encodeToString(AddressResponse.serializer(), withArea)))
    }
}

class OtherDaysNoteTest {
    @Test
    fun radernVisasUnderRubriken() {
        val note = assertNotNull(OtherDaysNote.make(AreaDetails(day = "x", label = null, places = emptyList(), otherDays = listOf("Rad ett.", "Rad två."))))
        assertEquals("Vissa gator har en annan hämtdag", note.heading)
        assertEquals(listOf("Rad ett.", "Rad två."), note.rows)
    }

    @Test
    fun blankaRaderRensasBort() {
        val note = assertNotNull(OtherDaysNote.make(AreaDetails(day = "x", label = null, places = emptyList(), otherDays = listOf("  ", "", " Rad ett.\n", "\t"))))
        assertEquals(listOf("Rad ett."), note.rows)
    }

    @Test
    fun tomListaNullOchSaknatGerIngenRuta() {
        assertNull(OtherDaysNote.make(AreaDetails(day = "x", label = null, places = emptyList(), otherDays = emptyList())))
        assertNull(OtherDaysNote.make(AreaDetails(day = "x", label = null, places = emptyList(), otherDays = listOf(" ", ""))))
        assertNull(OtherDaysNote.make(null))
    }

    @Test
    fun adressvynHarRutanFranSparatSchema() {
        val key = AddressKey(source = "avesta", id = "trakt-7")
        val saved = SavedAddress(
            key = key, url = "https://sopor.hardyson.se/api/v1/adress/avesta/trakt-7", street = "Område 7", locality = "", kommun = "Avesta kommun",
            detail = null, selection = "area", displayName = "Område 7", isPrimary = true, addedAt = Instant.EPOCH,
        )
        val now = StockholmClock.dateOn(DayDate.parse("2026-11-06")!!, 12 * 60)
        fun make(response: AddressResponse?): AddressDetail {
            val cached = response?.let { CachedSchedule(response = it, fetchedAt = now, lastAttemptAt = now, lastError = null) }
            return AddressDetail.make(saved, cached, ReminderSettings(), sourceName = "Avesta", now = now)
        }
        assertEquals(listOf("En rad."), make(addressResponse(area(listOf("En rad.")))).otherDays?.rows)
        assertNull(make(addressResponse(area(emptyList()))).otherDays)
        assertNull(make(addressResponse(null)).otherDays)
        assertNull(make(addressResponse(null, omit = true)).otherDays)
        assertNull(make(null).otherDays)
    }
}
