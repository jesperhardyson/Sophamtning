package se.hardyson.sophamtning.core.storage

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.fixture
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/** Från SourceMessagesTests och StoredModels på iOS: sparade filer från äldre versioner. */
class ReminderSettingsTest {
    private fun read(text: String) = storeJson.decodeFromString(ReminderSettings.serializer(), text)

    @Test
    fun installningenArPaFranBorjanOchIGamlaFiler() {
        assertTrue(ReminderSettings().sourceMessagesOn)
        assertTrue(read("""{"eveningOn":true,"morningOn":false,"reminderMinutes":1080,"liveActivityOn":false}""").sourceMessagesOn)
        val off = ReminderSettings(sourceMessagesOn = false)
        assertFalse(read(storeJson.encodeToString(ReminderSettings.serializer(), off)).sourceMessagesOn)
    }

    @Test
    fun gamlaEndaValetLasesSomDetEndaPaslagna() {
        val settings = read("""{"reminderMinutes":1080,"liveActivityOn":false,"timing":"sameMorning"}""")
        assertFalse(settings.eveningOn)
        assertTrue(settings.morningOn)
        assertEquals(ReminderTiming.SameMorning, settings.liveActivityTiming)
    }

    @Test
    fun okantValLasesSomKvallenFore() {
        val settings = read("""{"reminderMinutes":1080,"liveActivityOn":false,"liveActivityTiming":"natten"}""")
        assertEquals(ReminderTiming.EveningBefore, settings.liveActivityTiming)
        assertTrue(settings.eveningOn)
    }

    @Test
    fun bådaValenAvGerKvallen() {
        assertTrue(read("""{"reminderMinutes":1080,"liveActivityOn":false,"eveningOn":false,"morningOn":false}""").eveningOn)
    }

    @Test
    fun egenTidForLiveUpdateFoljerNotisensTidNarDenSaknas() {
        assertEquals(1020, read("""{"reminderMinutes":1020,"liveActivityOn":true}""").liveActivityMinutes)
        assertEquals(1020, ReminderSettings(reminderMinutes = 1020).liveActivityMinutes)
    }

    @Test
    fun turOchRetur() {
        val settings = ReminderSettings(eveningOn = true, morningOn = true, morningMinutes = 420, liveActivityOn = true, liveActivityMinutes = 1020, reminderOfferShown = true)
        assertEquals(settings, read(storeJson.encodeToString(ReminderSettings.serializer(), settings)))
    }

    @Test
    fun sattningensText() {
        assertEquals("Kvällen före, 18:00", ReminderSettings().settingsValue)
        assertEquals("18:00 och 06:00", ReminderSettings(morningOn = true).settingsValue)
        assertEquals("Samma morgon, 07:00", ReminderSettings(eveningOn = false, morningOn = true, morningMinutes = 420).settingsValue)
    }

    @Test
    fun sparatSchemaFranForeFaltetGarAttLasa() {
        val json = Json.parseToJsonElement(fixture("adress")).jsonObject
        val old = JsonObject(mapOf("response" to JsonObject(json - "messages"), "fetchedAt" to JsonPrimitive(0)))
        val cached = storeJson.decodeFromString(CachedSchedule.serializer(), old.toString())
        assertEquals(emptyList(), cached.response?.messages)
        assertEquals(ApiDecoding.addressResponse(JsonObject(json - "messages")), cached.response)
    }
}
