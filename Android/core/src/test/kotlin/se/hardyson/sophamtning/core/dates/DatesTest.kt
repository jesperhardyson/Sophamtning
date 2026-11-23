package se.hardyson.sophamtning.core.dates

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

private fun day(iso: String) = DayDate.parse(iso)!!

class DatesTest {
    @Test
    fun idagFoljerStockholmEfterMidnatt() {
        // 2026-11-08 23:30 UTC är 00:30 den 9 november i Sverige
        assertEquals(day("2026-11-09"), StockholmClock.today(Instant.parse("2026-11-08T23:30:00Z")))
    }

    @Test
    fun artonNollNollVidOmstallning() {
        assertEquals(Instant.parse("2026-11-08T17:00:00Z"), StockholmClock.dateOn(day("2026-11-08"), minutes = 1080))
        assertEquals(Instant.parse("2027-03-28T16:00:00Z"), StockholmClock.dateOn(day("2027-03-28"), minutes = 1080))
        assertEquals(Instant.parse("2027-10-31T17:00:00Z"), StockholmClock.dateOn(day("2027-10-31"), minutes = 1080))
    }

    @Test
    fun svenskaTexter() {
        assertEquals("Måndag 9 november", SwedishFormat.longDate(day("2026-11-09"), capitalized = true))
        assertEquals("måndag 9 november", SwedishFormat.longDate(day("2026-11-09"), capitalized = false))
        assertEquals("Mån 9 nov", SwedishFormat.shortDate(day("2026-11-09")))
        assertEquals("i dag", SwedishFormat.relative(0))
        assertEquals("i morgon", SwedishFormat.relative(1))
        assertEquals("i övermorgon", SwedishFormat.relative(2))
        assertEquals("om 3 dagar", SwedishFormat.relative(3))
        assertEquals("ca tors 12 nov", SwedishFormat.estimated("tors 12 nov", true))
        assertEquals("Tisdag 27 oktober 2026", SwedishFormat.longDateWithYear(day("2026-10-27")))
        assertEquals("10 januari 2027", SwedishFormat.dayMonthYear(day("2027-01-10")))
        assertEquals("13 okt", SwedishFormat.dayMonth(day("2026-10-13")))
        assertEquals("NOV", SwedishFormat.monthUppercased(day("2026-11-09")))
        assertEquals("18:00", SwedishFormat.clock(1080))
        assertEquals("06:05", SwedishFormat.clock(365))
    }

    @Test
    fun ogiltigtDatumGerNil() {
        assertNull(DayDate.parse("2026-13-40"))
        assertNull(DayDate.parse("2026-02-30"))
        assertNull(DayDate.parse("2026-1-05"))
        assertNull(DayDate.parse("２０２６-11-05"))
    }

    @Test
    fun isoTurOchRetur() {
        val start = day("2026-11-17")
        assertEquals("2026-11-17", start.iso)
        assertEquals(DayDate(2026, 12, 1), start.plusDays(14))
        assertEquals(14, start.daysUntil(DayDate(2026, 12, 1)))
        assertEquals(-14, DayDate(2026, 12, 1).daysUntil(start))
        assert(start < DayDate(2026, 12, 1))
    }

    @Test
    fun kodasSomText() {
        assertEquals("\"2026-11-17\"", Json.encodeToString(DayDate.serializer(), day("2026-11-17")))
        assertEquals(day("2026-11-17"), Json.decodeFromString(DayDate.serializer(), "\"2026-11-17\""))
        assertFailsWith<SerializationException> { Json.decodeFromString(DayDate.serializer(), "\"2026-02-30\"") }
    }
}

class DatesLocaleTest {
    @Test
    fun siffrornaBeroInteAvSpraket() {
        val before = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.forLanguageTag("ar-EG-u-nu-arab"))
            assertEquals("2026-11-09", DayDate(2026, 11, 9).iso)
            assertEquals("18:00", SwedishFormat.clock(1080))
        } finally {
            java.util.Locale.setDefault(before)
        }
    }
}
