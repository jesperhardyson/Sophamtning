package se.hardyson.sophamtning.core.storage

import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.DayDate

private val key = AddressKey("kallor", "hem")
private val today = DayDate.parse("2026-11-08")!!
private fun entry(offset: Int) = PlacedOut(key, today.plusDays(offset))

private fun concurrently(count: Int, work: (Int) -> Unit) {
    val pool = Executors.newFixedThreadPool(8)
    repeat(count) { index -> pool.execute { runCatching { work(index) } } }
    pool.shutdown()
    pool.awaitTermination(30, TimeUnit.SECONDS)
}

class PlacedOutStoreTest {
    @Test
    fun enPostLaggsTillUtanAttAndraOvriga() {
        val store = LocalStore(tempDir())
        store.markPlacedOut(entry(1), today)
        store.markPlacedOut(entry(2), today)
        store.markPlacedOut(entry(1), today)
        assertEquals(setOf(entry(1), entry(2)), store.placedOut().toSet())
        assertEquals(2, store.placedOut().size)
    }

    @Test
    fun samtidigaSkrivningarTapparIngenPost() {
        // Varje skrivning har sin egen LocalStore, som appen och widgeten. Utan lås försvinner poster här.
        val dir = tempDir()
        concurrently(60) { index -> LocalStore(dir).markPlacedOut(entry(index + 1), today) }
        val saved = LocalStore(dir).placedOut()
        assertEquals(60, saved.size)
        assertEquals(60, saved.toSet().size)
    }

    @Test
    fun samtidigRensningOchSkrivningTapparIngenPost() {
        val dir = tempDir()
        LocalStore(dir).setPlacedOut((1..20).map { entry(-it) })
        concurrently(40) { index ->
            val store = LocalStore(dir)
            if (index % 2 == 0) store.markPlacedOut(entry(index + 1), today) else store.prunePlacedOut(today)
        }
        val saved = LocalStore(dir).placedOut().toSet()
        assertEquals(20, saved.size)
        assertTrue(saved.all { it.date > today })
    }

    @Test
    fun passeradePosterRensas() {
        val store = LocalStore(tempDir())
        store.setPlacedOut(listOf(entry(-1), entry(0), entry(1)))
        store.prunePlacedOut(today)
        // Dagens post är kvar: tömningen är inte över förrän dagen har passerat.
        assertEquals(setOf(entry(0), entry(1)), store.placedOut().toSet())
    }

    @Test
    fun enNyPostRensarPasserade() {
        val store = LocalStore(tempDir())
        store.setPlacedOut(listOf(entry(-3)))
        store.markPlacedOut(entry(1), today)
        assertEquals(listOf(entry(1)), store.placedOut())
    }

    @Test
    fun rensningUtanFilSkapasIngenFil() {
        val dir = tempDir()
        LocalStore(dir).prunePlacedOut(today)
        assertFalse(File(dir, "placed-out.json").exists())
    }

    @Test
    fun skadadFilErsattsAvNyPost() {
        val dir = tempDir()
        val store = LocalStore(dir)
        File(dir, "placed-out.json").writeText("inte json")
        assertIs<StoreRead.Unreadable>(store.placedOutState())
        store.markPlacedOut(entry(1), today)
        assertEquals(listOf(entry(1)), store.placedOut())
    }

    @Test
    fun skrivfelVidUtstalltKastas() {
        val blocked = File(tempDir(), "blockerad").apply { writeText("") }
        assertFailsWith<Exception> { LocalStore(blocked).markPlacedOut(entry(1), today) }
    }

    @Test
    fun visadeSparasRensasOchTomsPaBegaran() {
        val store = LocalStore(tempDir())
        store.markShown(listOf(entry(-1), entry(1)), today)
        assertEquals(listOf(entry(1)), store.shownActivities())
        store.markShown(listOf(entry(1), entry(2)), today)
        assertEquals(setOf(entry(1), entry(2)), store.shownActivities().toSet())
        assertEquals(2, store.shownActivities().size)
        store.clearShown()
        assertTrue(store.shownActivities().isEmpty())
        // Filerna är skilda åt: en visad är inte utställd.
        assertTrue(store.placedOut().isEmpty())
    }

    // Android: tiden då kärlen ställdes ut, för raden "av dig · kl. 19:42".

    @Test
    fun tidenForUtstalltSparasOchRensasMedBocken() {
        val dir = tempDir()
        val store = LocalStore(dir)
        val at = java.time.Instant.parse("2026-11-08T18:42:00Z")
        store.markPlacedOut(entry(1), today)
        store.setPlacedOutTime(entry(1), at)
        assertEquals(mapOf(entry(1) to at), store.placedOutTimes())
        // Samma format som tiderna i övriga filer: sekunder sedan 2001.
        val json = File(dir, "placed-out-times.json").readText()
        assertTrue(json.contains("\"${key.fileName}-${entry(1).date.iso}\""), json)
        assertEquals(815856120.0, json.substringAfter(":").trimEnd('}').toDouble(), json)

        store.unmarkPlacedOut(entry(1))
        assertTrue(store.placedOutTimes().isEmpty())
        assertFalse(File(dir, "placed-out-times.json").readText().contains(key.fileName))
    }

    @Test
    fun tidenRensasNarBockenHarPasserat() {
        val store = LocalStore(tempDir())
        store.markPlacedOut(entry(0), today)
        store.setPlacedOutTime(entry(0), java.time.Instant.parse("2026-11-08T18:42:00Z"))
        store.prunePlacedOut(today.plusDays(1))
        assertTrue(store.placedOutTimes().isEmpty())
    }
}
