package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.LiveActivityAction.End
import se.hardyson.sophamtning.core.reminders.LiveActivityAction.Remove
import se.hardyson.sophamtning.core.reminders.LiveActivityAction.Start
import se.hardyson.sophamtning.core.reminders.LiveActivityAction.Update
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

private val home = AddressKey("kallor", "hem")
private val other = AddressKey("kallor", "annan")
private val today = day("2026-11-08")
private val monday = day("2026-11-09")
private val thursday = day("2026-11-12")
private val start = StockholmClock.dateOn(today, 1080)

private fun content(name: String = "Hemma", date: String = "Måndag 9 november", estimated: Boolean = false, warning: String? = null) =
    PickupActivityContent(name, date, "Mån 9 nov", listOf(ActivityFraction("rest", "Restavfall", "Rest", "#111111", "trash")), estimated, warning)

private val plan = PlannedLiveActivity(home, monday, start, startsImmediately = false, content = content())

private fun existing(
    id: String,
    key: AddressKey = home,
    date: DayDate = monday,
    content: PickupActivityContent = content(),
    pending: Boolean = true,
    at: Instant = start,
) = ExistingActivity(id, key, date, content, pending, at)

private fun actions(
    desired: PlannedLiveActivity?,
    list: List<ExistingActivity>,
    enabled: Boolean = true,
    primary: AddressKey? = null,
    canStart: Boolean = true,
    now: Instant = start.minusSeconds(3600),
    todayContent: PickupActivityContent? = null,
    householdMarked: Set<PlacedOut> = emptySet(),
    householdSilenced: Set<PlacedOut> = emptySet(),
) = LiveActivityDiff.actions(
    desired, list, today, enabled, primary = primary, canStart = canStart, now = now, todayContent = todayContent,
    householdMarked = householdMarked, householdSilenced = householdSilenced,
)

private val mondayMarked = setOf(PlacedOut(home, monday))

// Från LiveActivityDiffTests på iOS, utom texttesterna, som finns i PickupActivityTextsTest.
class LiveActivityDiffTest {
    @Test
    fun ingenOnskadTarBortAlla() {
        assertEquals(listOf(Remove("a"), Remove("b")), actions(null, listOf(existing("a"), existing("b", date = thursday))))
    }

    @Test
    fun samma() {
        assertEquals(emptyList(), actions(plan, listOf(existing("a"))))
        assertEquals(emptyList(), actions(plan, listOf(existing("a", pending = false))))
    }

    @Test
    fun nyStartar() {
        assertEquals(listOf(Start(plan)), actions(plan, emptyList()))
    }

    @Test
    fun nyttDatumErsatter() {
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a", date = thursday))))
    }

    @Test
    fun nyttInnehallPaStartadUppdaterar() {
        val running = existing("a", content = content(warning = "Helgdag"), pending = false)
        assertEquals(listOf(Update("a", plan.content)), actions(plan, listOf(running)))
    }

    @Test
    fun nyttInnehallPaVantandeErsatter() {
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a", content = content("Stugan")))))
    }

    @Test
    fun nyTidPaVantandeErsatter() {
        // Användaren ändrar påminnelsetiden. Utan det här startar Live Updaten på den gamla tiden.
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a", at = start.plusSeconds(3600)))))
    }

    @Test
    fun nyTidPaStartadRorInget() {
        assertEquals(emptyList(), actions(plan, listOf(existing("a", pending = false, at = start.minusSeconds(3600)))))
    }

    @Test
    fun dubblettStadas() {
        assertEquals(listOf(Remove("b")), actions(plan, listOf(existing("a"), existing("b"))))
    }

    @Test
    fun dubblettBeharDenStartade() {
        assertEquals(listOf(Remove("a")), actions(plan, listOf(existing("a"), existing("b", pending = false))))
    }

    @Test
    fun dubblettMedNyttInnehallUppdaterarDenStartade() {
        val pending = existing("a", content = content("Stugan"))
        val running = existing("b", content = content("Stugan"), pending = false)
        assertEquals(listOf(Remove("a"), Update("b", plan.content)), actions(plan, listOf(pending, running)))
    }

    @Test
    fun pagaendeForIDagLeverKvar() {
        assertEquals(listOf(Start(plan)), actions(plan, listOf(existing("a", date = today, pending = false))))
    }

    @Test
    fun pagaendeForIDagLeverKvarUtanNastaTomning() {
        assertEquals(emptyList(), actions(null, listOf(existing("a", date = today, pending = false)), primary = home))
    }

    @Test
    fun vantandeForIDagTasBort() {
        // Den har inte startat och hinner inte starta i tid.
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a", date = today, pending = true))))
    }

    @Test
    fun gardagensTasBort() {
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a", date = today.plusDays(-1), pending = false))))
    }

    @Test
    fun avstangtValTarBortAvenPagaende() {
        val running = existing("a", date = today, pending = false)
        assertEquals(listOf(Remove("a"), Remove("b")), actions(plan, listOf(running, existing("b")), enabled = false))
        assertEquals(listOf(Remove("a")), actions(null, listOf(running), enabled = false, primary = home))
    }

    @Test
    fun bytHuvudadressTarBortPagaendeForIDag() {
        val running = existing("a", key = other, date = today, pending = false)
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(running)))
        assertEquals(listOf(Remove("a")), actions(null, listOf(running), primary = home))
    }

    @Test
    fun ingenHuvudadressTarBortPagaendeForIDag() {
        assertEquals(listOf(Remove("a")), actions(null, listOf(existing("a", date = today, pending = false)), primary = null))
    }

    // Utan start

    @Test
    fun utanStartStartasIngen() {
        assertEquals(emptyList(), actions(plan, emptyList(), canStart = false))
        assertEquals(listOf(Remove("a")), actions(plan, listOf(existing("a", date = thursday)), canStart = false))
    }

    @Test
    fun utanStartBehallsVantandeMedSammaDatum() {
        // Det går inte att lägga in en ny, så den gamla är bättre än ingen alls.
        assertEquals(emptyList(), actions(plan, listOf(existing("a", content = content(warning = "Helgdag"))), canStart = false))
        assertEquals(emptyList(), actions(plan, listOf(existing("a", at = start.plusSeconds(3600))), canStart = false))
    }

    @Test
    fun utanStartUppdaterasStartad() {
        val running = existing("a", content = content(warning = "Helgdag"), pending = false)
        assertEquals(listOf(Update("a", plan.content)), actions(plan, listOf(running), canStart = false))
    }

    // Väntande vars start har passerat

    @Test
    fun passeradVantandeErsattsOmDetGar() {
        val late = start.plus(LiveActivityDiff.overdueMargin).plusSeconds(1)
        assertEquals(listOf(Remove("a"), Start(plan)), actions(plan, listOf(existing("a")), now = late))
        assertEquals(emptyList(), actions(plan, listOf(existing("a")), canStart = false, now = late))
    }

    @Test
    fun vantandeInomMarginalenRorsInte() {
        val within = start.plus(LiveActivityDiff.overdueMargin)
        assertEquals(emptyList(), actions(plan, listOf(existing("a")), now = within))
        assertFalse(LiveActivityDiff.isOverdue(existing("a"), within))
        assertTrue(LiveActivityDiff.isOverdue(existing("a"), within.plusSeconds(1)))
        assertFalse(LiveActivityDiff.isOverdue(existing("a", pending = false), within.plusSeconds(1)))
    }

    // Dagens pågående

    @Test
    fun tvaPagaendeForIDagStadas() {
        val first = existing("a", date = today, pending = false)
        val second = existing("b", date = today, pending = false)
        assertEquals(listOf(Remove("b"), Start(plan)), actions(plan, listOf(first, second)))
    }

    @Test
    fun dagensPagaendeUppdaterasMedNyttInnehall() {
        val running = existing("a", date = today, pending = false)
        val updated = content("Nytt namn", warning = "Helgdag")
        assertEquals(listOf(Update("a", updated)), actions(null, listOf(running), primary = home, todayContent = updated))
        assertEquals(emptyList(), actions(null, listOf(running), primary = home, todayContent = content()))
        assertEquals(listOf(Update("a", updated)), actions(null, listOf(running), primary = home, canStart = false, todayContent = updated))
    }

    // Lägen

    @Test
    fun baraVantandeOchPagaendeRaknasSomBefintliga() {
        assertTrue(LiveActivityPhase.Pending.countsAsExisting)
        assertTrue(LiveActivityPhase.Active.countsAsExisting)
        assertFalse(LiveActivityPhase.Ended.countsAsExisting)
        assertFalse(LiveActivityPhase.Dismissed.countsAsExisting)
        assertFalse(LiveActivityPhase.Stale.countsAsExisting)
    }

    // Start

    @Test
    fun startlage() {
        val scheduled = PlannedLiveActivity(home, monday, start, startsImmediately = false, content = content())
        assertEquals(StartMode.Scheduled(start), scheduled.startMode(start.minusSeconds(60)))
        // Tiden hann passera mellan planeringen och anropet: en start i det förflutna får aldrig läggas in.
        assertEquals(StartMode.Immediately, scheduled.startMode(start))
        assertEquals(StartMode.Immediately, scheduled.startMode(start.plusSeconds(1)))
        val immediate = PlannedLiveActivity(home, monday, start, startsImmediately = true, content = content())
        assertEquals(StartMode.Immediately, immediate.startMode(start.plusSeconds(60)))
    }

    // Hushållets bockar. Android har inget hushåll än, men diffen tar emot dem som på iOS.

    @Test
    fun andrasBockUppdaterarPagaendeKvallenFore() {
        val running = existing("a", pending = false)
        assertEquals(listOf(Update("a", content().markedPlacedOut())), actions(plan, listOf(running), householdMarked = mondayMarked))
    }

    @Test
    fun andrasBockVisarVemOchNar() {
        val running = existing("a", pending = false)
        val detail = mapOf(PlacedOut(home, monday) to "av Sofie · kl. 19:42")
        val result = LiveActivityDiff.actions(
            plan, listOf(running), today, enabled = true, now = start.minusSeconds(3600), householdMarked = mondayMarked, householdMarkDetails = detail,
        )
        assertEquals(listOf(Update("a", content().markedPlacedOut("av Sofie · kl. 19:42"))), result)
    }

    @Test
    fun andrasBockStartarMedBock() {
        val marked = PlannedLiveActivity(home, monday, start, startsImmediately = false, content = content().markedPlacedOut())
        assertEquals(listOf(Start(marked)), actions(plan, emptyList(), householdMarked = mondayMarked))
    }

    @Test
    fun andrasBockAvslutarPagaendeMedBock() {
        val next = PlannedLiveActivity(home, thursday, start.plusSeconds(3 * 86_400), startsImmediately = false, content = content(date = "Torsdag 12 november"))
        val running = existing("a", pending = false)
        assertEquals(listOf(End("a", content().markedPlacedOut()), Start(next)), actions(next, listOf(running), householdMarked = mondayMarked))
        assertEquals(listOf(End("a", content().markedPlacedOut())), actions(null, listOf(running), householdMarked = mondayMarked))
    }

    @Test
    fun andrasBockTarBortVantandeUtanBock() {
        assertEquals(listOf(Remove("a")), actions(null, listOf(existing("a")), householdMarked = mondayMarked))
    }

    @Test
    fun utanHushalletAvslutasIngetMedBock() {
        assertEquals(listOf(Remove("a")), actions(null, listOf(existing("a", pending = false))))
    }

    // Samma morgon

    @Test
    fun bytTillMorgonErsatterVantande() {
        val morning = PlannedLiveActivity(home, monday, StockholmClock.dateOn(monday, 360), startsImmediately = false, content = content())
        assertEquals(listOf(Remove("a"), Start(morning)), actions(morning, listOf(existing("a"))))
    }

    @Test
    fun pagaendeIDagLeverEfterTolv() {
        val next = PlannedLiveActivity(home, thursday, StockholmClock.dateOn(thursday, 360), startsImmediately = false, content = content())
        val running = existing("a", date = today, pending = false, at = StockholmClock.dateOn(today, 360))
        assertEquals(listOf(Start(next)), actions(next, listOf(running), primary = home, now = StockholmClock.dateOn(today, 13 * 60)))
    }

    @Test
    fun andrasBockUppdaterarPagaendeSammaMorgon() {
        val morningStart = StockholmClock.dateOn(today, 360)
        val desired = PlannedLiveActivity(home, today, morningStart, startsImmediately = true, content = content())
        val running = existing("a", date = today, pending = false, at = morningStart)
        val marked = setOf(PlacedOut(home, today))
        assertEquals(
            listOf(Update("a", content().markedPlacedOut())),
            actions(desired, listOf(running), now = morningStart.plusSeconds(3600), householdMarked = marked),
        )
    }

    @Test
    fun andrasBockAvslutarDagensMedTystaPa() {
        val morningStart = StockholmClock.dateOn(today, 360)
        val next = PlannedLiveActivity(home, thursday, StockholmClock.dateOn(thursday, 360), startsImmediately = false, content = content(date = "Torsdag 12 november"))
        val running = existing("a", date = today, pending = false, at = morningStart)
        val marked = setOf(PlacedOut(home, today))
        assertEquals(
            listOf(End("a", content().markedPlacedOut()), Start(next)),
            actions(next, listOf(running), primary = home, now = morningStart.plusSeconds(3600), householdMarked = marked, householdSilenced = marked),
        )
        // Utan tystnad lever den kvar som förut, med bocken.
        assertEquals(
            listOf(Update("a", content().markedPlacedOut()), Start(next)),
            actions(next, listOf(running), primary = home, now = morningStart.plusSeconds(3600), todayContent = content().markedPlacedOut(), householdMarked = marked),
        )
    }
}
