package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.ReminderTiming

private val key = AddressKey(source = "orebro", id = "1")

private fun seconds(value: Double): Instant = Instant.ofEpochSecond(0, Math.round(value * 1_000_000_000))

private fun planned(id: String, at: Double, body: String = "Text") =
    PlannedNotification(identifier = id, fireDate = seconds(at), title = "Ställ ut kärlen", body = body, key = key, pickupDate = DayDate.parse("2026-11-09")!!)

private val hex64 = "ab12".repeat(16)

/** NotificationDiffTests på iOS. */
class NotificationDiffTest {
    @Test
    fun ingenSkillnadGerIngaAndringar() {
        val desired = listOf(planned("a", 100.0), planned("b", 200.0))
        val result = NotificationDiff.diff(desired, pendingIds = setOf("a", "b"), pendingFireDates = mapOf("a" to seconds(100.0), "b" to seconds(200.0)))
        assertTrue(result.add.isEmpty())
        assertTrue(result.removeIds.isEmpty())
    }

    @Test
    fun borttagenPlanTarBortVantande() {
        val result = NotificationDiff.diff(emptyList(), pendingIds = setOf("b", "a"), pendingFireDates = emptyMap())
        assertTrue(result.add.isEmpty())
        assertEquals(listOf("a", "b"), result.removeIds)
    }

    @Test
    fun andradTidErsatterNotisen() {
        val result = NotificationDiff.diff(listOf(planned("a", 500.0)), pendingIds = setOf("a"), pendingFireDates = mapOf("a" to seconds(100.0)))
        assertEquals(listOf("a"), result.add.map { it.identifier })
        assertEquals(listOf("a"), result.removeIds)
    }

    @Test
    fun nyPlanLaggsTill() {
        val result = NotificationDiff.diff(listOf(planned("a", 100.0), planned("b", 200.0)), pendingIds = setOf("a"), pendingFireDates = mapOf("a" to seconds(100.0)))
        assertEquals(listOf("b"), result.add.map { it.identifier })
        assertTrue(result.removeIds.isEmpty())
    }

    @Test
    fun vantandeUtanKantTidErsattsEftersomTidenOkandIKontrollen() {
        val result = NotificationDiff.diff(listOf(planned("a", 100.0)), pendingIds = setOf("a"), pendingFireDates = emptyMap())
        assertEquals(listOf("a"), result.add.map { it.identifier })
        assertEquals(listOf("a"), result.removeIds)
    }

    @Test
    fun andradTextErsatterNotisen() {
        val result = NotificationDiff.diff(
            listOf(planned("a", 100.0, body = "Nytt namn")),
            pendingIds = setOf("a"),
            pendingFireDates = mapOf("a" to seconds(100.0)),
            pendingBodies = mapOf("a" to "Gammalt namn"),
        )
        assertEquals(listOf("a"), result.add.map { it.identifier })
        assertEquals(listOf("a"), result.removeIds)
    }

    @Test
    fun bladdraEnSekundTraffarInteSomAndring() {
        val result = NotificationDiff.diff(listOf(planned("a", 100.4)), pendingIds = setOf("a"), pendingFireDates = mapOf("a" to seconds(100.0)))
        assertTrue(result.add.isEmpty() && result.removeIds.isEmpty())
    }

    @Test
    fun baraEgnaIdentifierareKannsIgen() {
        val own = "${key.fileName}-2026-11-09"
        assertTrue(NotificationDiff.isOwn(own))
        assertFalse(NotificationDiff.isOwn("annan-notis"))
        assertFalse(NotificationDiff.isOwn("${key.fileName}-inte-ett-datum"))
        assertFalse(NotificationDiff.isOwn("abc-2026-11-09"))
        assertFalse(NotificationDiff.isOwn(""))
    }

    @Test
    fun hushalletsNotisArInteEgen() {
        // Planeringen får aldrig ta bort en notis med en annan form, som hushållets på iOS.
        assertFalse(NotificationDiff.isOwn("hushall.${key.fileName}.2026-11-09"))
    }

    @Test
    fun behalletNotisSomLiggerFramforTasInteBort() {
        val now = seconds(1000.0)
        val result = NotificationDiff.diff(emptyList(), pendingIds = setOf("a", "b"), pendingFireDates = mapOf("a" to seconds(2000.0), "b" to seconds(2000.0)), retain = setOf("a"), now = now)
        // Bara den som ska stå kvar behålls. Den andra tas bort som vanligt.
        assertEquals(listOf("b"), result.removeIds)
        assertTrue(result.add.isEmpty())
    }

    @Test
    fun behalletNotisMedPasseradTidEllerOkandTidTasBort() {
        val now = seconds(1000.0)
        val result = NotificationDiff.diff(emptyList(), pendingIds = setOf("a", "b"), pendingFireDates = mapOf("a" to seconds(900.0)), retain = setOf("a", "b"), now = now)
        assertEquals(listOf("a", "b"), result.removeIds)
    }

    @Test
    fun behalletNotisErsattsNarPlanenHarEnNyTid() {
        val now = seconds(1000.0)
        val result = NotificationDiff.diff(listOf(planned("a", 3000.0)), pendingIds = setOf("a"), pendingFireDates = mapOf("a" to seconds(2000.0)), retain = setOf("a"), now = now)
        assertEquals(listOf("a"), result.add.map { it.identifier })
        assertEquals(listOf("a"), result.removeIds)
    }

    @Test
    fun morgonensIdentifierare() {
        val date = DayDate.parse("2026-11-11")!!
        val morning = PlannedNotification.identifier(key, date, ReminderTiming.SameMorning)
        assertTrue(morning.endsWith("-2026-11-11-morgon"))
        assertEquals("${key.fileName}-2026-11-11", PlannedNotification.identifier(key, date, ReminderTiming.EveningBefore))
    }

    @Test
    fun egnaIdentifierare() {
        assertTrue(NotificationDiff.isOwn("$hex64-2026-11-11"))
        assertTrue(NotificationDiff.isOwn("$hex64-2026-11-11-morgon"))
        assertFalse(NotificationDiff.isOwn("$hex64-2026-11-11-kvall"))
        assertFalse(NotificationDiff.isOwn("$hex64-2026-11-11-"))
        assertFalse(NotificationDiff.isOwn("$hex64-morgon"))
    }

    @Test
    fun gammalMorgonnotisErsätts() {
        // En morgonnotis som schemalagts före ändringen hade kvällens identifierare. Nu har morgonen sin egen.
        val old = "$hex64-2026-11-11"
        val new = "$hex64-2026-11-11-morgon"
        val result = NotificationDiff.diff(listOf(planned(new, 100.0)), pendingIds = setOf(old), pendingFireDates = mapOf(old to seconds(100.0)))
        assertEquals(listOf(new), result.add.map { it.identifier })
        assertEquals(listOf(old), result.removeIds)
    }
}
