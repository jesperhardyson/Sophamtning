package se.hardyson.sophamtning.core.reminders

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.Address
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.Links
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.ReminderSettings

// Texttesterna i LiveActivityDiffTests.swift. Resten finns i LiveActivityDiffTest.

private val home = AddressKey("kallor", "hem")
private val today = DayDate.parse("2026-11-08")!!
private val start = StockholmClock.dateOn(today, 1080)
private val rest = ActivityFraction("rest", "Restavfall", "Rest", "#111111", "trash")

private fun content(estimated: Boolean = false, warning: String? = null) =
    PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", listOf(rest), estimated, warning)

private fun fractions(count: Int) = (0 until count).map { ActivityFraction("f$it", "Namn $it", "K$it", "#111111", "trash") }

private fun withFractions(count: Int) = PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", fractions(count), false, null)

class PickupActivityTextsTest {
    @Test
    fun aviseringensText() {
        assertEquals("Ställ ut kärlen", PickupActivityContent.ALERT_TITLE)
        val two = PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", listOf(rest, ActivityFraction("mat", "Matavfall", "Mat", "#222222", "leaf")), false, null)
        assertEquals("Hemma: Restavfall och Matavfall töms måndag 9 november.", two.alertBody)
        val estimated = PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", two.fractions, true, "Hämtning på helgdag.")
        assertEquals("Hemma: Restavfall och Matavfall töms ca måndag 9 november. Hämtning på helgdag.", estimated.alertBody)
    }

    @Test
    fun vyernasTexter() {
        val plain = content()
        assertEquals("Hemma · måndag 9 november", plain.subtitle)
        assertEquals("Mån 9 nov", plain.shortDate)
        assertEquals("Mån", plain.compactDate)
        assertEquals("Hemma: Restavfall", plain.fractionsLine)
        val estimated = content(estimated = true)
        assertEquals("Hemma · ca måndag 9 november", estimated.subtitle)
        assertEquals("ca mån 9 nov", estimated.shortDate)
        assertEquals("ca mån", estimated.compactDate)
    }

    @Test
    fun aktivitetensTextSagerAldrigIMorgon() {
        // Söndag kväll, tömning måndag: alltså i morgon. Innehållet uppdateras inte under natten.
        val tomorrow = PickupEvent(DayDate.parse("2026-11-09")!!, listOf("rest"), estimated = true, deviation = null, warning = null, labels = emptyMap())
        val saved = address(home, "x".repeat(80), primary = true)
        val response = AddressResponse(
            today = today,
            address = Address(home.id, "Gatan 1", "Orten", "Kommunen", home.source, null, "address", null),
            next = emptyList(), summary = "", events = listOf(tomorrow), bins = emptyList(),
            fractions = mapOf("rest" to FractionInfo("Restavfall", "Rest", "#111111", "trash")),
            links = Links("https://example.com/a.ics", "https://example.com/a"),
            updatedAt = today,
        )
        val plan = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(PlannerAddress(saved, CachedSchedule(response = response))),
                settings = ReminderSettings(liveActivityOn = true), placedOut = emptySet(), now = start.plusSeconds(60),
                liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
            ),
        )
        val c = assertNotNull(plan.liveActivity).content
        assertEquals(60, c.addressName.length)
        for (text in listOf(c.alertBody, c.subtitle, c.shortDate, c.compactDate, c.fractionsLine, c.dateText)) {
            assertFalse("i morgon" in text.lowercase(), text)
            assertFalse("i dag" in text.lowercase(), text)
        }
    }

    @Test
    fun varningenKortas() {
        val long = PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", emptyList(), false, "x".repeat(500))
        assertEquals(200, long.warning?.length)
        assertTrue(long.warning!!.endsWith("…"))
        assertEquals("x".repeat(200), content(warning = "x".repeat(200)).warning)
    }

    @Test
    fun allaFraktionerRymsPaHogstTvaRader() {
        for (count in 1..8) {
            val rows = withFractions(count).fractionRows
            assertTrue(rows.size <= 2, "$count")
            // Ingen fraktion försvinner, och ordningen är kvar.
            assertEquals(fractions(count).map { it.id }, rows.flatten().map { it.id }, "$count")
        }
        assertEquals(listOf(3), withFractions(3).fractionRows.map { it.size })
        assertEquals(listOf(2, 2), withFractions(4).fractionRows.map { it.size })
        assertEquals(listOf(3, 2), withFractions(5).fractionRows.map { it.size })
        assertEquals(listOf(3, 3), withFractions(6).fractionRows.map { it.size })
    }

    @Test
    fun varningenFarEnRadNarFraktionernaTarTvaRader() {
        assertEquals(2, withFractions(3).warningLineLimit)
        assertEquals(1, withFractions(4).warningLineLimit)
        assertEquals(1, withFractions(6).warningLineLimit)
    }
}
