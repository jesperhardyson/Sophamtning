package se.hardyson.sophamtning.core.messages

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import se.hardyson.sophamtning.core.api.SourceMessage
import se.hardyson.sophamtning.core.dates.DayDate

private fun day(iso: String) = DayDate.parse(iso)!!

private fun message(id: String, from: String = "2026-11-17", to: String = "2027-03-31") =
    SourceMessage(id = id, title = "Rubrik $id", text = "Text", url = null, validFrom = day(from), validTo = day(to))

class SourceMessagesTest {
    // Vilka som gäller

    @Test
    fun gallerMellanForstaOchSistaDagen() {
        val m = message("a", from = "2026-11-17", to = "2026-11-30")
        val input = listOf("avesta" to listOf(m))
        assertTrue(SourceMessages.active(input, today = day("2026-11-16")).isEmpty())
        assertEquals(1, SourceMessages.active(input, today = day("2026-11-17")).size)
        assertEquals(1, SourceMessages.active(input, today = day("2026-11-30")).size)
        assertTrue(SourceMessages.active(input, today = day("2026-12-01")).isEmpty())
    }

    @Test
    fun sammaMeddelandeHosTvaAdresserBlirEtt() {
        val input = listOf("avesta" to listOf(message("a")), "avesta" to listOf(message("a")))
        assertEquals(1, SourceMessages.active(input, today = day("2026-11-20")).size)
    }

    @Test
    fun sammaIdHosTvaKallorBlirTva() {
        val input = listOf("avesta" to listOf(message("a")), "sater" to listOf(message("a")))
        val active = SourceMessages.active(input, today = day("2026-11-20"))
        assertEquals(listOf("avesta", "sater"), active.map { it.source })
        assertEquals(2, active.map { it.key }.toSet().size)
    }

    @Test
    fun ordnasEfterStartdagOchId() {
        val input = listOf("avesta" to listOf(message("b", from = "2026-11-10"), message("c", from = "2026-11-01"), message("a", from = "2026-11-10")))
        assertEquals(listOf("c", "a", "b"), SourceMessages.active(input, today = day("2026-11-20")).map { it.message.id })
    }

    // Minnet

    @Test
    fun minnetKodasMedKallanSomNyckel() {
        val key = SourceMessageKey(source = "avesta", id = "nya-rutter-2026")
        val memory = SourceMessageMemory().markSeen(listOf(key)).dismiss(key)
        val text = Json.encodeToString(SourceMessageMemory.serializer(), memory)
        val expected = JsonObject(
            mapOf(
                "avesta" to JsonObject(
                    mapOf(
                        "seen" to JsonArray(listOf(JsonPrimitive("nya-rutter-2026"))),
                        "dismissed" to JsonArray(listOf(JsonPrimitive("nya-rutter-2026"))),
                    ),
                ),
            ),
        )
        assertEquals(expected, Json.parseToJsonElement(text))
        val back = Json.decodeFromString(SourceMessageMemory.serializer(), text)
        assertTrue(back.isSeen(key))
        assertTrue(back.isDismissed(key))
        assertFalse(back.isSeen(SourceMessageKey(source = "sater", id = "nya-rutter-2026")))
    }

    @Test
    fun settOchStangtArSkilda() {
        val key = SourceMessageKey(source = "avesta", id = "a")
        val memory = SourceMessageMemory().markSeen(listOf(key)).markSeen(listOf(key))
        assertTrue(memory.isSeen(key))
        assertFalse(memory.isDismissed(key))
    }

    @Test
    fun osedda() {
        val active = SourceMessages.active(listOf("avesta" to listOf(message("a"), message("b"))), today = day("2026-11-20"))
        val memory = SourceMessageMemory().markSeen(listOf(active[0].key))
        assertEquals(listOf("b"), SourceMessages.unseen(active, memory).map { it.message.id })
    }

    // Tillagt på Android: samma id sparas bara en gång, och notisens identifierare är densamma som på iOS.
    @Test
    fun idSparasEnGangOchNotisensIdentifierare() {
        val key = SourceMessageKey(source = "avesta", id = "a")
        val memory = SourceMessageMemory().markSeen(listOf(key, key)).dismiss(key).dismiss(key)
        assertEquals("""{"avesta":{"seen":["a"],"dismissed":["a"]}}""", Json.encodeToString(SourceMessageMemory.serializer(), memory))
        assertEquals("kalla.avesta.a", SourceMessages.notificationId(key))
    }
}
