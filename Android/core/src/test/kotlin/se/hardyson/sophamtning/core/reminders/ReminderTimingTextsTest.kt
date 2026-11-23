package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming

private val wednesday = day("2026-11-11")
private val nextWednesday = day("2026-11-18")
private val morning = ReminderSettings(eveningOn = false, morningOn = true, morningMinutes = 360, liveActivityTiming = ReminderTiming.SameMorning)
private val both = ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 1080, morningMinutes = 360)

private fun at(day: String, hour: Int): Instant = StockholmClock.dateOn(DayDate.parse(day)!!, hour * 60)

/**
 * ReminderTimingTextsTests på iOS: texterna för valen, inställningarna och adressvyn. Testerna för hemskärmen
 * (`reglagetsNamn`, `fotenNotisFöreAktivitet` och `huvudkortetPåMorgonen`) står i HomeContentTest.
 */
class ReminderTimingTextsTest {
    @Test
    fun delarnasTexter() {
        assertEquals("Dagen före tömningen kl. 15:00.", ReminderTiming.EveningBefore.sectionFooter(900))
        assertEquals("Samma dag som tömningen kl. 06:00. Minst en påminnelse är på. Notiser slår du av under Adresser.", ReminderTiming.SameMorning.sectionFooter(360))
    }

    @Test
    fun tidslistansText() {
        assertEquals("Välj en tid mellan 15:00 och 23:00.", ReminderTiming.EveningBefore.timesFooter)
        assertEquals("Välj en tid mellan 05:00 och 09:00.", ReminderTiming.SameMorning.timesFooter)
    }

    @Test
    fun radenVisarNästa() {
        val events = listOf(event(wednesday))
        assertEquals("Tisdag kl. 18:00 inför onsdagens tömning.", AddressDetail.reminderText(events, both, at("2026-11-10", 12)))
        assertEquals("Onsdag kl. 06:00, samma dag som tömningen.", AddressDetail.reminderText(events, both, at("2026-11-10", 19)))
    }

    @Test
    fun radenUtanKommandeTömningNämnerVarjeVal() {
        assertEquals("Kvällen före varje tömning kl. 18:00. Samma morgon som varje tömning kl. 06:00.", AddressDetail.reminderText(emptyList(), both, at("2026-11-10", 12)))
    }

    @Test
    fun passeradMedBåda() {
        val events = listOf(event(wednesday))
        assertEquals("Tömning i dag. Påminnelsen för i morse har redan passerat.", AddressDetail.missedReminder(events, both, at("2026-11-11", 7)))
        assertNull(AddressDetail.missedReminder(events, both, at("2026-11-10", 19)))
    }

    @Test
    fun passeradBaraKväll() {
        assertEquals("Tömning i morgon. Påminnelsen för i kväll har redan passerat.", AddressDetail.missedReminder(listOf(event(wednesday)), ReminderSettings(), at("2026-11-10", 19)))
    }

    @Test
    fun liveActivityTextFöljerSittVal() {
        val settings = ReminderSettings(eveningOn = true, morningOn = false, liveActivityTiming = ReminderTiming.SameMorning)
        assertEquals("Visas på låsskärmen kl. 06:00–18:00 samma dag.", AddressDetail.liveActivityText(settings))
    }

    @Test
    fun inställningensTexter() {
        assertEquals("Kvällen före", ReminderTiming.EveningBefore.title)
        assertEquals("Samma morgon", ReminderTiming.SameMorning.title)
    }

    @Test
    fun radenUnderReglagetPåMorgonen() {
        val events = listOf(event(wednesday), event(nextWednesday))
        assertEquals("Onsdag kl. 06:00, samma dag som tömningen.", AddressDetail.reminderText(events, morning, at("2026-11-10", 20)))
        // Dagens tid har passerat, så nästa tömning gäller.
        assertEquals("Onsdag kl. 06:00, samma dag som tömningen.", AddressDetail.reminderText(events, morning, at("2026-11-11", 7)))
        assertEquals("Samma morgon som varje tömning kl. 06:00.", AddressDetail.reminderText(emptyList(), morning, at("2026-11-11", 7)))
        // Kvällen är oförändrad.
        assertEquals("Tisdag kl. 18:00 inför onsdagens tömning.", AddressDetail.reminderText(events, ReminderSettings(), at("2026-11-10", 12)))
    }

    @Test
    fun passeradMorgon() {
        val events = listOf(event(wednesday))
        assertEquals("Tömning i dag. Påminnelsen för i morse har redan passerat.", AddressDetail.missedReminder(events, morning, at("2026-11-11", 7)))
        assertNull(AddressDetail.missedReminder(events, morning, at("2026-11-11", 5)))
        // Morgonvalet säger inget om morgondagen kvällen före.
        assertNull(AddressDetail.missedReminder(events, morning, at("2026-11-10", 20)))
    }

    @Test
    fun reservenPåMorgonen() {
        assertEquals("Onsdag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns.", AddressDetail.reserveText(StockholmClock.dateOn(wednesday, 6 * 60 + 45)))
        assertEquals("Tisdag kl. 18:45 inför onsdagens tömning, om aktiviteten inte syns.", AddressDetail.reserveText(StockholmClock.dateOn(day("2026-11-10"), 18 * 60 + 45)))
    }

    @Test
    fun liveActivityPåMorgonen() {
        assertEquals("Visas på låsskärmen kl. 06:00–18:00 samma dag.", AddressDetail.liveActivityText(morning))
    }

    @Test
    fun reservtextenFöljerNotisensDagEfterByte() {
        // Morgonens notis står kvar som reserv efter bytet tillbaka till kvällen. Den gäller ändå onsdagens tömning.
        assertEquals("Onsdag kl. 06:00, samma dag som tömningen, om aktiviteten inte syns.", AddressDetail.reserveText(StockholmClock.dateOn(wednesday, 6 * 60)))
        assertEquals("Tisdag kl. 18:45 inför onsdagens tömning, om aktiviteten inte syns.", AddressDetail.reserveText(StockholmClock.dateOn(day("2026-11-10"), 18 * 60 + 45)))
    }

    // MARK: Inställningarnas texter

    @Test
    fun notiserGällerAdresserna() {
        assertEquals("Ingen adress har notiser på. Slå på Påminn mig i adressen.", ReminderSettingsTexts.notificationsFooter(emptyList()))
        assertEquals("Gäller Hemma. Slå på eller av i varje adress.", ReminderSettingsTexts.notificationsFooter(listOf("Hemma")))
        assertEquals("Gäller Hemma och Jobbet. Slå på eller av i varje adress.", ReminderSettingsTexts.notificationsFooter(listOf("Hemma", "Jobbet")))
        assertEquals("Gäller Hemma, Jobbet och Stugan. Slå på eller av i varje adress.", ReminderSettingsTexts.notificationsFooter(listOf("Hemma", "Jobbet", "Stugan")))
    }

    @Test
    fun liveActivityOchHuvudadressensTexter() {
        assertEquals("Visas för huvudadressen, Hemma.", ReminderSettingsTexts.liveActivityFooter("Hemma"))
        // Android har varken Siri eller Live Activity: huvudadressen används av Live Update, widgetar och snabbinställningarna.
        assertEquals("Används av Live Update, widgetar och snabbinställningar.", ReminderSettingsTexts.PRIMARY_FOOTER)
        assertEquals("Samma som Påminn mig i varje adress. Stäng av alla för att inte få några notiser.", ReminderSettingsTexts.ADDRESSES_FOOTER)
    }

    @Test
    fun adressernaIHemskärmensOrdning() {
        fun saved(name: String, primary: Boolean) = address(AddressKey("s", name), name = name, primary = primary, addedAt = Instant.EPOCH)
        val order = ReminderSettingsTexts.homeOrder(listOf(saved("Jobbet", false), saved("Hemma", true), saved("Stugan", false)))
        assertEquals(listOf("Hemma", "Jobbet", "Stugan"), order.map { it.displayName })
        assertTrue(ReminderSettingsTexts.homeOrder(emptyList()).isEmpty())
    }

    /** `textenUnderReglaget` från SourceMessagesTests på iOS. Android säger "för appen" i stället för "i iOS". */
    @Test
    fun textenUnderReglaget() {
        assertEquals(
            "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna.",
            ReminderSettingsTexts.sourceMessagesFooter(authorized = true),
        )
        assertEquals(
            "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna. Notiser är avstängda för appen.",
            ReminderSettingsTexts.sourceMessagesFooter(authorized = false),
        )
    }
}
