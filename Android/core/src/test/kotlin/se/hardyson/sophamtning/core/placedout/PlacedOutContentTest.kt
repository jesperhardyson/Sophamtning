package se.hardyson.sophamtning.core.placedout

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.ActivityFraction
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.PlannerAddress
import se.hardyson.sophamtning.core.reminders.PlannerInput
import se.hardyson.sophamtning.core.reminders.ReminderPlanner
import se.hardyson.sophamtning.core.reminders.address
import se.hardyson.sophamtning.core.reminders.cached
import se.hardyson.sophamtning.core.reminders.detailLine
import se.hardyson.sophamtning.core.reminders.event
import se.hardyson.sophamtning.core.reminders.response
import se.hardyson.sophamtning.core.reminders.title
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.storeJson

/** PlacedOutContentTests på iOS, utan hushållets bockar. */
class PlacedOutContentTest {
    private fun content(placedOut: Boolean = false) = PickupActivityContent(
        addressName = "Hemma", dateText = "Måndag 9 november", shortDateText = "Mån 9 nov",
        fractions = listOf(ActivityFraction(id = "rest", name = "Restavfall", short = "Rest", color = "#111111", icon = "trash")),
        estimated = false, warning = null, placedOut = placedOut,
    )

    private fun decode(json: String) = storeJson.decodeFromString(PickupActivityContent.serializer(), json)
    private fun encode(content: PickupActivityContent) = storeJson.encodeToString(PickupActivityContent.serializer(), content)

    @Test fun standardarFalse() = assertEquals(false, content().placedOut)

    @Test
    fun aldreJsonUtanFaltetGerFalse() {
        // Innehåll som en schemalagd Live Update från en äldre version kan ha sparat.
        val decoded = decode("""{"addressName":"Hemma","dateText":"Måndag 9 november","shortDateText":"Mån 9 nov","fractions":[],"estimated":false}""")
        assertEquals(false, decoded.placedOut)
        assertEquals("Hemma", decoded.addressName)
    }

    @Test
    fun kodningBehallerVardet() {
        for (value in listOf(true, false)) {
            val decoded = decode(encode(content(placedOut = value)))
            assertEquals(value, decoded.placedOut, "$value")
            assertEquals(content(placedOut = value), decoded, "$value")
        }
    }

    @Test
    fun markeratSomUtstalltAndrarBaraFaltet() {
        val marked = content().markedPlacedOut()
        assertTrue(marked.placedOut)
        assertEquals(content(placedOut = true), marked)
        assertNotEquals(content(), marked)
    }

    @Test
    fun rubrikenOchRadenNarKarlenArUtstallda() {
        assertEquals("Ställ ut kärlen", content().title)
        assertEquals("Hemma · måndag 9 november", content().detailLine)
        // Utan känd tid står adressen och datumet kvar.
        assertEquals("Kärlen är utställda", content().markedPlacedOut().title)
        assertEquals("Hemma · måndag 9 november", content().markedPlacedOut().detailLine)
        assertEquals("av Sofie · kl. 19:42", content().markedPlacedOut(detail = "av Sofie · kl. 19:42").detailLine)
        assertEquals("Klart", PickupActivityContent.DONE_BUTTON)
    }

    @Test
    fun vemOchNarFoljerMedKodningenOchBaraNarUtstallt() {
        val marked = content().markedPlacedOut(detail = "av Sofie · kl. 19:42")
        val decoded = decode(encode(marked))
        assertEquals(marked, decoded)
        assertEquals("av Sofie · kl. 19:42", decoded.placedOutDetail)
        // Utan bock finns ingen rad om vem.
        val unmarked = PickupActivityContent(
            addressName = "Hemma", dateText = "Måndag 9 november", shortDateText = "Mån 9 nov", fractions = emptyList(),
            estimated = false, warning = null, placedOut = false, placedOutDetail = "av Sofie · kl. 19:42",
        )
        assertNull(unmarked.placedOutDetail)
    }

    /** Bara första kontrollen på iOS: den andra gäller en bock från hushållet. */
    @Test
    fun liveActivityUtanBockEllerMedAnnatDatumVisarInteBocken() {
        val homeKey = AddressKey(source = "kallor", id = "hem")
        val monday = day("2026-11-09")
        val fractions = mapOf("rest" to FractionInfo(name = "Restavfall", short = "Rest", color = "#111111", icon = "trash"))
        val input = PlannerInput(
            addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, addedAt = Instant.EPOCH), cached(response(homeKey, listOf(event("2026-11-09", listOf("rest"))), fractions), Instant.EPOCH))),
            settings = ReminderSettings(liveActivityOn = true), placedOut = emptySet(), now = StockholmClock.dateOn(monday, 7 * 60),
            liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
        )
        assertEquals(false, ReminderPlanner.activityContent(monday, input)?.placedOut)
    }
}
