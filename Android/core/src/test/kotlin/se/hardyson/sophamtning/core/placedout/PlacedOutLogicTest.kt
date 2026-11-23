package se.hardyson.sophamtning.core.placedout

import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

/** De fall i HouseholdLogicTests på iOS som gäller en adress som inte delas. */
class PlacedOutLogicTest {
    private val today = day("2026-11-10")
    private val home = AddressKey(source = "avesta", id = "hemma")
    private val work = AddressKey(source = "avesta", id = "jobbet")

    /** Bara kontrollerna för en adress som inte delas och saknar påminnelser. */
    @Test
    fun knappenVisasDagenForeOchTomningsdagen() {
        assertFalse(PlacedOutLogic.showsPlaceOutButton(remindersOn = false, nextPickup = day("2026-11-10"), today = today))
        assertFalse(PlacedOutLogic.showsPlaceOutButton(remindersOn = false, nextPickup = day("2026-11-11"), today = today))
    }

    /** Med egna utställda i stället för hushållets bockar. `expired` utgår, eftersom lagringen rensar passerade. */
    @Test
    fun bockGallerStockholmsDatum() {
        val pressed = LocalDateTime.of(2026, 11, 10, 23, 30).atZone(ZoneId.of("America/New_York")).toInstant()
        // Samma ögonblick är 05:30 den 11:e i Stockholm.
        assertEquals(day("2026-11-11"), StockholmClock.today(pressed))
        val placed = setOf(PlacedOut(home, day("2026-11-11")))
        val next = day("2026-11-11")
        assertEquals(next, PlacedOutLogic.currentMark(home, next, placed)?.date)
        assertNull(PlacedOutLogic.currentMark(home, null, placed))
        assertNull(PlacedOutLogic.currentMark(work, next, placed))
    }

    /** Bara titeln och "av dig". Andra i hushållet finns inte på Android. */
    @Test
    fun undertextenSagerVemOchNar() {
        val at = StockholmClock.dateOn(today, 19 * 60 + 42)
        assertEquals("Utställt", PlacedOutTexts.PLACED_OUT_TITLE)
        assertEquals("av dig · kl. 19:42", PlacedOutTexts.placedOutSubtitle(at))
    }

    // MARK: Ställa ut utan hushåll

    @Test
    fun knappenVisasForEgenAdressMedPaminnelser() {
        assertTrue(PlacedOutLogic.showsPlaceOutButton(remindersOn = true, nextPickup = day("2026-11-10"), today = today))
        assertTrue(PlacedOutLogic.showsPlaceOutButton(remindersOn = true, nextPickup = day("2026-11-11"), today = today))
        assertFalse(PlacedOutLogic.showsPlaceOutButton(remindersOn = true, nextPickup = day("2026-11-12"), today = today))
        assertFalse(PlacedOutLogic.showsPlaceOutButton(remindersOn = false, nextPickup = day("2026-11-10"), today = today))
    }

    /** Efter Ångra på tömningsdagen ska kärlen gå att ställa ut igen. */
    @Test
    fun egenAdressUtanBockFarKnappenNarPaminnelserArPa() {
        val line = assertNotNull(PlacedOutLine.make(home, nextPickup = today, today = today, remindersOn = true))
        assertTrue(line.showsButton)
        assertNull(line.placedOutText)
    }

    @Test
    fun egenAdressUtanPaminnelserFarIngenKnapp() {
        assertNull(PlacedOutLine.make(home, nextPickup = today, today = today, remindersOn = false))
    }

    @Test
    fun egenAdressLangtTillTomningFarIngenKnapp() {
        assertNull(PlacedOutLine.make(home, nextPickup = day("2026-11-12"), today = today, remindersOn = true))
    }

    @Test
    fun egenUtstalldAdressVisarBockenUtanKnapp() {
        val line = assertNotNull(PlacedOutLine.make(home, nextPickup = today, today = today, ownPlacedOut = setOf(PlacedOut(home, today)), remindersOn = true))
        assertFalse(line.showsButton)
        assertEquals(PlacedOutTexts.OWN_PLACED_OUT, line.placedOutText)
    }

    /** Android: raden heter Utställt, med "av dig" och klockslaget när det är känt. Hemskärmens rader visar "Kärlen är utställda". */
    @Test
    fun egenUtstalldAdressVisarAvDigOchKlockslaget() {
        val entry = PlacedOut(home, today)
        val at = StockholmClock.dateOn(today, 7 * 60 + 5)
        val line = assertNotNull(PlacedOutLine.make(home, nextPickup = today, today = today, ownPlacedOut = setOf(entry), remindersOn = false, placedOutTimes = mapOf(entry to at)))
        assertEquals("Utställt", line.placedOutTitle)
        assertEquals("av dig · kl. 07:05", line.placedOutSubtitle)
        assertEquals("Kärlen är utställda", line.placedOutText)
        // Utan känd tid står ingen undertext.
        assertNull(PlacedOutLine.make(home, nextPickup = today, today = today, ownPlacedOut = setOf(entry))?.placedOutSubtitle)
        // En utställd för en annan tömning räknas inte.
        assertNull(PlacedOutLine.make(home, nextPickup = today, today = today, ownPlacedOut = setOf(PlacedOut(home, day("2026-11-18")))))
    }
}
