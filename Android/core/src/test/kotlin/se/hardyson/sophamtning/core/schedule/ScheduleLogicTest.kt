package se.hardyson.sophamtning.core.schedule

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate

internal fun day(iso: String) = DayDate.parse(iso)!!

private fun event(iso: String, fractions: List<String>, estimated: Boolean = false, warning: String? = null) =
    PickupEvent(day(iso), fractions, estimated, deviation = null, warning = warning, labels = emptyMap())

private val events = listOf(event("2026-11-01", listOf("rest")), event("2026-11-09", listOf("rest", "plast")), event("2026-11-12", listOf("glas")))

class ScheduleLogicTest {
    @Test
    fun filtrerarBortPasseradeDatum() {
        assertEquals(listOf(day("2026-11-09"), day("2026-11-12")), ScheduleLogic.upcoming(events, day("2026-11-09")).map { it.date })
    }

    @Test
    fun upcomingSortererarPaDatum() {
        assertEquals(listOf(day("2026-11-09"), day("2026-11-12")), ScheduleLogic.upcoming(listOf(events[2], events[1]), day("2026-11-01")).map { it.date })
    }

    @Test
    fun nastaHamtningArForstaKommande() {
        assertEquals(day("2026-11-12"), ScheduleLogic.nextPickup(events, day("2026-11-10"))?.date)
    }

    @Test
    fun baraPasseradeDatumGerIngenNastaHamtning() {
        assertNull(ScheduleLogic.nextPickup(events, day("2027-01-10")))
        assertTrue(ScheduleLogic.nextByFraction(events, day("2027-01-10")).isEmpty())
    }

    @Test
    fun dagarKvarRaknasFranGivenDag() {
        val list = listOf(event("2026-11-11", listOf("plast")))
        assertEquals(3, ScheduleLogic.nextByFraction(list, day("2026-11-08")).first().daysUntil)
        assertEquals(1, ScheduleLogic.nextByFraction(list, day("2026-11-10")).first().daysUntil)
    }

    @Test
    fun nastaPerFraktionGerForstaDatumSorteratMedStabilOrdning() {
        val list = listOf(
            event("2026-11-12", listOf("rest", "glas"), warning = "Sen tömning"),
            event("2026-11-10", listOf("plast", "papper"), estimated = true),
            event("2026-11-20", listOf("plast")),
        )
        val result = ScheduleLogic.nextByFraction(list, day("2026-11-09"))
        assertEquals(listOf("papper", "plast", "glas", "rest"), result.map { it.fraction })
        assertEquals(listOf(1, 1, 3, 3), result.map { it.daysUntil })
        assertTrue(result[1].estimated)
        assertNull(result[1].warning)
        assertFalse(result[2].estimated)
        assertEquals("Sen tömning", result[2].warning)
    }

    @Test
    fun dagensDatumRaknasSomNollDagar() {
        assertEquals(0, ScheduleLogic.nextByFraction(listOf(event("2026-11-09", listOf("rest"))), day("2026-11-09")).first().daysUntil)
    }

    @Test
    fun okandFraktionGarTillIdEfterNamn() {
        val info = ScheduleLogic.displayInfo("tradgard", emptyMap())
        assertEquals(FractionInfo("tradgard", "tradgard", "#526158", "recycle"), info)
    }

    @Test
    fun kandFraktionAnvandsOforandrad() {
        val glas = FractionInfo("Glas", "Glas", "#1F6A7A", "wine")
        assertEquals(glas, ScheduleLogic.displayInfo("glas", mapOf("glas" to glas)))
    }
}
