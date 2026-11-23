package se.hardyson.sophamtning.core.placedout

import java.io.File
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.tempDir
import se.hardyson.sophamtning.core.schedule.day

private val key = AddressKey("kallor", "hem")
private val today = day("2026-11-08")
private fun entry(offset: Int) = PlacedOut(key, today.plusDays(offset))

/** Tar emot borttagningarna, och kan misslyckas med varje. */
private class FakeCenter(private val failing: Boolean = false) {
    val cancelled = mutableListOf<String>()

    fun cancel(id: String) {
        cancelled += id
        if (failing) throw IOException("Gick inte att ta bort")
    }
}

/** Testerna för PlacedOutAction i PlacedOutTests på iOS. */
class PlacedOutActionTest {
    @Test
    fun utstalltAvslutarAktivitetenSpararOchTarBortNotisen() = runTest {
        val store = LocalStore(tempDir())
        var ended = false
        val center = FakeCenter()
        val saved = PlacedOutAction.perform(store, entry(1), today, end = { ended = true }, cancelReminder = center::cancel)
        assertTrue(saved)
        assertTrue(ended)
        assertEquals(listOf(entry(1)), store.placedOut())
        // Adressens och datumets notis, med samma identifierare som planeraren ger.
        assertEquals(listOf("${key.fileName}-${entry(1).date.iso}", "${key.fileName}-${entry(1).date.iso}-morgon"), center.cancelled)
    }

    @Test
    fun utstalltAvslutarAktivitetenAvenVidSkrivfel() = runTest {
        val blocked = File(tempDir(), "blockerad").apply { writeBytes(ByteArray(0)) }
        var ended = false
        val center = FakeCenter()
        // Skrivfelet kastas inte utanför.
        val saved = PlacedOutAction.perform(LocalStore(blocked), entry(1), today, end = { ended = true }, cancelReminder = center::cancel)
        assertFalse(saved)
        assertTrue(ended)
        // Notisen tas bort ändå: användaren har sagt att det är utställt.
        assertEquals(2, center.cancelled.size)
    }

    @Test
    fun utstalltAvslutarAktivitetenAvenNarNotisenInteGarAttTaBort() = runTest {
        val store = LocalStore(tempDir())
        var ended = false
        val center = FakeCenter(failing = true)
        val saved = PlacedOutAction.perform(store, entry(1), today, end = { ended = true }, cancelReminder = center::cancel)
        // Felet kastas inte, Live Updaten är avslutad och valet sparat. Följden är bara en extra påminnelse.
        assertTrue(saved)
        assertTrue(ended)
        assertEquals(listOf(entry(1)), store.placedOut())
        // Båda försöks även när det första misslyckas.
        assertEquals(2, center.cancelled.size)
    }

    @Test
    fun utställtTarBortBåda() = runTest {
        val center = FakeCenter()
        PlacedOutAction.perform(LocalStore(tempDir()), entry(1), today, end = {}, cancelReminder = center::cancel)
        val date = entry(1).date
        assertEquals(
            setOf(PlannedNotification.identifier(key, date, ReminderTiming.EveningBefore), PlannedNotification.identifier(key, date, ReminderTiming.SameMorning)),
            center.cancelled.toSet(),
        )
        assertEquals(2, center.cancelled.size)
    }

    @Test
    fun utstalltTarBortNotisernaAvenNarAvslutningenMisslyckas() = runTest {
        val store = LocalStore(tempDir())
        val center = FakeCenter()
        val saved = PlacedOutAction.perform(store, entry(1), today, end = { throw SecurityException("nekad") }, cancelReminder = center::cancel)
        assertTrue(saved)
        assertEquals(listOf(entry(1)), store.placedOut())
        assertEquals(2, center.cancelled.size)
    }
}
