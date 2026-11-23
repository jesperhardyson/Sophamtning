package se.hardyson.sophamtning.core.schedule

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.dates.StockholmClock

private val today = day("2026-12-27")
private fun period(daysLeft: Int, reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget.") =
    SchedulePeriod(today.plusDays(daysLeft), reason)

class ScheduleEndingTest {
    @Test fun femtonDagarKvarVisasInte() = assertNull(ScheduleEnding.make(period(15), today))

    @Test
    fun fjortonDagarKvarVisas() {
        val ending = assertNotNull(ScheduleEnding.make(period(14), today))
        assertEquals(14, ending.daysLeft)
        assertEquals(day("2027-01-10"), ending.until)
    }

    @Test fun enDagKvarVisas() = assertEquals(1, ScheduleEnding.make(period(1), today)?.daysLeft)

    @Test fun sistaDagenArInraknad() = assertEquals(0, ScheduleEnding.make(period(0), today)?.daysLeft)

    @Test
    fun passeratDatumVisasInte() {
        assertNull(ScheduleEnding.make(period(-1), today))
        assertNull(ScheduleEnding.make(period(-60), today))
    }

    @Test fun utanPeriodVisasInte() = assertNull(ScheduleEnding.make(null, today))

    @Test
    fun kortRadenHarKortDatumUtanAr() {
        val ending = assertNotNull(ScheduleEnding.make(period(14), today))
        assertEquals("Schemat slutar 10 jan", ending.shortText)
        assertEquals("Schemat slutar 10 januari", ending.spokenText)
    }

    @Test
    fun rutanSagerBaraAttNyaTiderKommer() {
        val ending = assertNotNull(ScheduleEnding.make(period(10), today))
        assertEquals("Schemat tar snart slut", ending.title)
        assertEquals("Nya tider visas när källan publicerar dem.", ending.message)
    }

    @Test
    fun rutanUpprepaInteKallansOrsak() {
        val withReason = assertNotNull(ScheduleEnding.make(period(10), today))
        val without = assertNotNull(ScheduleEnding.make(period(10, reason = null), today))
        assertEquals(withReason.message, without.message)
        assertFalse("Avesta Vatten" in withReason.message)
    }

    @Test
    fun lovarAldrigAttPaminnelserFortsatter() {
        assertFalse("påminnelse" in assertNotNull(ScheduleEnding.make(period(3), today)).message.lowercase())
    }

    @Test
    fun dagenRaknasISvenskTidOavsettTelefonensTidszon() {
        // 00:30 den 27 dec i Stockholm är 18:30 den 26:e i New York. Dagen är ändå den 27:e, så 10 jan är 14 dagar kvar.
        val early = StockholmClock.dateOn(day("2026-12-27"), 30)
        val d = StockholmClock.today(early)
        assertEquals(day("2026-12-27"), d)
        assertEquals(14, ScheduleEnding.make(SchedulePeriod(day("2027-01-10"), null), d)?.daysLeft)
    }

    @Test
    fun dateOnRullarOverTillNastaDag() {
        assertEquals(java.time.Instant.parse("2026-11-09T05:00:00Z"), StockholmClock.dateOn(day("2026-11-08"), 1440 + 360))
        assertEquals(java.time.Instant.parse("2026-11-07T22:00:00Z"), StockholmClock.dateOn(day("2026-11-08"), -60))
    }
}
