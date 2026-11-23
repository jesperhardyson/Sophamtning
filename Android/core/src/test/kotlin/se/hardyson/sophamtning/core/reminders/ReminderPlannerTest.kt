package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming

private val homeKey = AddressKey(source = "kallor", id = "hem/1")
private val otherKey = AddressKey(source = "kallor", id = "annan 2")

private val fractionInfo = mapOf(
    "rest" to FractionInfo(name = "Restavfall", short = "Rest", color = "#111111", icon = "trash"),
    "mat" to FractionInfo(name = "Matavfall", short = "Mat", color = "#222222", icon = "leaf"),
    "papper" to FractionInfo(name = "Pappersförpackningar", short = "Papper", color = "#333333", icon = "doc"),
    "glas" to FractionInfo(name = "Glasförpackningar", short = "Glas", color = "#444444", icon = "wineglass"),
)

private fun schedule(key: AddressKey, events: List<PickupEvent>, fractions: Map<String, FractionInfo> = fractionInfo) =
    cached(response(key, events, fractions))

private val standardEvents = listOf(
    event("2026-11-09", listOf("rest", "mat")),
    event("2026-11-12", listOf("papper")),
)

/** Fredag 2026-11-06 kl. 12:00 svensk tid. */
private val friday = stockholm("2026-11-06T12:00")

private fun plan(
    notifications: Boolean = false,
    live: Boolean = false,
    allowed: Boolean = true,
    primaryIsOther: Boolean = false,
    now: Instant = friday,
    events: List<PickupEvent> = standardEvents,
    otherEvents: List<PickupEvent> = listOf(event("2026-11-10", listOf("glas"))),
    placedOut: Set<PlacedOut> = emptySet(),
    existing: Set<PlacedOut> = emptySet(),
    shown: Set<PlacedOut> = emptySet(),
    withPrimary: Boolean = true,
    reminderMinutes: Int = 1080,
    timing: ReminderTiming = ReminderTiming.EveningBefore,
    morningMinutes: Int = 360,
    starts: Map<PlacedOut, Instant> = emptyMap(),
): ReminderPlan {
    val home = address(homeKey, name = "Hemma", primary = withPrimary && !primaryIsOther, notifications = notifications)
    val other = address(otherKey, name = "Stugan", primary = withPrimary && primaryIsOther, notifications = notifications)
    return ReminderPlanner.plan(
        PlannerInput(
            addresses = listOf(
                PlannerAddress(home, schedule(homeKey, events)),
                PlannerAddress(other, schedule(otherKey, otherEvents)),
            ),
            settings = ReminderSettings(
                eveningOn = timing == ReminderTiming.EveningBefore, morningOn = timing == ReminderTiming.SameMorning,
                reminderMinutes = reminderMinutes, morningMinutes = morningMinutes, liveActivityTiming = timing, liveActivityOn = live,
            ),
            placedOut = placedOut,
            now = now,
            liveActivitiesAllowed = allowed,
            existingActivities = existing,
            shownActivities = shown,
            activityStarts = starts,
        ),
    )
}

private fun plannerInput(
    notifications: Boolean,
    now: Instant,
    placedOut: Set<PlacedOut> = emptySet(),
    shown: Set<PlacedOut> = emptySet(),
    timing: ReminderTiming = ReminderTiming.EveningBefore,
) = PlannerInput(
    addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = notifications), schedule(homeKey, standardEvents))),
    settings = ReminderSettings(eveningOn = timing == ReminderTiming.EveningBefore, morningOn = timing == ReminderTiming.SameMorning, liveActivityTiming = timing, liveActivityOn = true),
    placedOut = placedOut, now = now, liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = shown,
)

/** En enda adress, för tester av innehållet. */
private fun single(
    events: List<PickupEvent>,
    notifications: Boolean = true,
    now: Instant = friday,
    fractions: Map<String, FractionInfo> = fractionInfo,
) = ReminderPlanner.plan(
    PlannerInput(
        addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = notifications), schedule(homeKey, events, fractions))),
        settings = ReminderSettings(), placedOut = emptySet(), now = now, liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
    ),
)

private fun body(estimated: Boolean = false, warning: String? = null) =
    single(listOf(event("2026-11-09", listOf("rest", "mat"), estimated = estimated, warning = warning))).notifications[0].body

private val homeMonday = setOf(PlacedOut(homeKey, day("2026-11-09")))

private fun mondayNotification(p: ReminderPlan) = p.notifications.firstOrNull { it.key == homeKey && it.pickupDate == day("2026-11-09") }

private fun homeNotification(plan: ReminderPlan, date: String) = plan.notifications.firstOrNull { it.key == homeKey && it.pickupDate == day(date) }

private val wed = day("2026-11-11")
private val wedId = PlacedOut(homeKey, wed)

private fun twoInput(
    settings: ReminderSettings,
    now: Instant,
    events: List<PickupEvent> = listOf(event("2026-11-11", listOf("rest"))),
    placedOut: Set<PlacedOut> = emptySet(),
    existing: Set<PlacedOut> = emptySet(),
    shown: Set<PlacedOut> = emptySet(),
    starts: Map<PlacedOut, Instant> = emptyMap(),
) = PlannerInput(
    addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = true), schedule(homeKey, events))),
    settings = settings, placedOut = placedOut, now = now, liveActivitiesAllowed = true, existingActivities = existing, shownActivities = shown, activityStarts = starts,
)

private val eveningId = PlannedNotification.identifier(homeKey, wed, ReminderTiming.EveningBefore)
private val morningId = PlannedNotification.identifier(homeKey, wed, ReminderTiming.SameMorning)

/** ReminderPlannerTests på iOS. */
class ReminderPlannerTest {
    @Test fun alltAvGerTomPlan() = assertEquals(ReminderPlan.empty, plan(notifications = false, live = false))

    @Test
    fun notisKvallenFore() {
        val n = plan(notifications = true).notifications[0]
        assertEquals(utc("2026-11-08T17:00:00Z"), n.fireDate)
        assertEquals("Ställ ut kärlen", n.title)
        assertEquals("Hemma: Restavfall och Matavfall töms måndag 9 november.", n.body)
        assertEquals(homeKey, n.key)
        assertEquals(day("2026-11-09"), n.pickupDate)
    }

    @Test
    fun beraknatDatumOchVarningINotis() {
        assertTrue(body(estimated = true).contains("töms ca måndag 9 november"))
        assertTrue(body(warning = "Hämtning på helgdag.").endsWith("november. Hämtning på helgdag."))
    }

    @Test fun tomVarningLaggsInteTill() = assertEquals("Hemma: Restavfall och Matavfall töms måndag 9 november.", body(warning = "  "))

    @Test
    fun fraktionsnamnBindsMedKommaOchOch() {
        assertEquals("Hemma: Restavfall töms måndag 9 november.", single(listOf(event("2026-11-09", listOf("rest")))).notifications[0].body)
        assertEquals(
            "Hemma: Restavfall, Matavfall och Pappersförpackningar töms måndag 9 november.",
            single(listOf(event("2026-11-09", listOf("rest", "mat", "papper")))).notifications[0].body,
        )
    }

    @Test
    fun okandFraktionFaarIdSomNamn() {
        assertEquals("Hemma: nytt töms måndag 9 november.", single(listOf(event("2026-11-09", listOf("nytt")))).notifications[0].body)
    }

    @Test
    fun passeradFireDateHoppasOver() {
        val p = plan(notifications = true, now = stockholm("2026-11-08T18:01"))
        assertFalse(p.notifications.any { it.pickupDate == day("2026-11-09") })
        assertTrue(p.notifications.any { it.pickupDate == day("2026-11-12") })
    }

    @Test
    fun fireDateExaktNuHoppasOver() {
        val p = plan(notifications = true, now = stockholm("2026-11-08T18:00"))
        assertFalse(p.notifications.any { it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun baraPasseratSchemaGerIngetAlls() = assertEquals(ReminderPlan.empty, plan(notifications = true, live = true, now = stockholm("2027-02-01T12:00")))

    @Test
    fun tomtSchemaGerIngetAlls() {
        assertEquals(ReminderPlan.empty, plan(notifications = true, live = true, events = emptyList(), otherEvents = emptyList()))
        val noResponse = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(
                    PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = true), null),
                    PlannerAddress(address(otherKey, name = "Stugan", primary = false, notifications = true), CachedSchedule()),
                ),
                settings = ReminderSettings(liveActivityOn = true), placedOut = emptySet(), now = friday, liveActivitiesAllowed = true,
                existingActivities = emptySet(), shownActivities = emptySet(),
            ),
        )
        assertEquals(ReminderPlan.empty, noResponse)
    }

    @Test
    fun handelseUtanFraktionerPlanerasInte() {
        val events = listOf(event("2026-11-09", emptyList()), event("2026-11-12", listOf("papper")))
        assertEquals(listOf(day("2026-11-12")), single(events).notifications.map { it.pickupDate })
        assertEquals(day("2026-11-12"), plan(live = true, events = events).liveActivity?.pickupDate)
    }

    @Test
    fun hogst60NarmastForst() {
        // 100 tömningar, varannan dag, i blandad ordning.
        val start = day("2026-11-10")
        val events = (0 until 100).map { event(start.plusDays(it * 2).iso, listOf("rest")) }.reversed()
        val p = single(events)
        assertEquals(60, p.notifications.size)
        assertEquals(p.notifications.map { it.fireDate }.sorted(), p.notifications.map { it.fireDate })
        assertEquals(day("2026-11-10"), p.notifications.first().pickupDate)
        assertEquals(start.plusDays(59 * 2), p.notifications.last().pickupDate)
    }

    @Test
    fun stabilaIdentifierare() {
        val a = plan(notifications = true)
        val b = plan(notifications = true)
        assertEquals(b.notifications.map { it.identifier }, a.notifications.map { it.identifier })
        assertEquals(a.notifications.size, a.notifications.map { it.identifier }.toSet().size)
        assertEquals("${homeKey.fileName}-2026-11-09", a.notifications[0].identifier)
    }

    @Test
    fun tvaHandelserSammaDagSlasIhop() {
        val p = single(listOf(event("2026-11-09", listOf("rest")), event("2026-11-09", listOf("mat"), warning = "Varning.")))
        assertEquals(1, p.notifications.size)
        assertEquals("Hemma: Restavfall och Matavfall töms måndag 9 november. Varning.", p.notifications[0].body)
    }

    @Test
    fun notisBaraForAdressMedValPa() {
        val home = address(homeKey, name = "Hemma", primary = true, notifications = false)
        val other = address(otherKey, name = "Stugan", primary = false, notifications = true)
        val p = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(PlannerAddress(home, schedule(homeKey, standardEvents)), PlannerAddress(other, schedule(otherKey, listOf(event("2026-11-10", listOf("glas")))))),
                settings = ReminderSettings(), placedOut = emptySet(), now = friday, liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
            ),
        )
        assertEquals(listOf(otherKey), p.notifications.map { it.key })
    }

    @Test
    fun paverkarPaminnelsetiden() {
        assertEquals(utc("2026-11-08T14:45:00Z"), plan(notifications = true, reminderMinutes = 15 * 60 + 45).notifications[0].fireDate)
    }

    @Test
    fun sommartidGerRattUtcTid() {
        // Omställning till sommartid sker 2026-03-29: kvällen den 29:e är UTC+2 och kvällen den 28:e UTC+1.
        assertEquals(utc("2026-03-29T16:00:00Z"), single(listOf(event("2026-03-30", listOf("rest"))), now = stockholm("2026-03-01T12:00")).notifications[0].fireDate)
        assertEquals(utc("2026-03-28T17:00:00Z"), single(listOf(event("2026-03-29", listOf("rest"))), now = stockholm("2026-03-01T12:00")).notifications[0].fireDate)
    }

    @Test
    fun liveActivityBaraForHuvudadressNastaTomning() {
        val la = plan(live = true).liveActivity
        assertEquals(day("2026-11-09"), la?.pickupDate)
        assertEquals(utc("2026-11-08T17:00:00Z"), la?.start)
        assertEquals(false, la?.startsImmediately)
        assertEquals(homeKey, la?.key)
        assertEquals(otherKey, plan(live = true, primaryIsOther = true).liveActivity?.key)
        assertEquals(day("2026-11-10"), plan(live = true, primaryIsOther = true).liveActivity?.pickupDate)
    }

    @Test
    fun liveActivityBerorInteAvAdressensNotisval() {
        assertNotNull(plan(notifications = false, live = true).liveActivity)
    }

    @Test
    fun liveActivityKraverBadaValen() {
        assertNull(plan(live = false).liveActivity)
        assertNull(plan(live = true, allowed = false).liveActivity)
    }

    @Test
    fun passeradStarttidStartarDirektOmTomningArImorgon() {
        val la = plan(live = true, now = stockholm("2026-11-08T20:00")).liveActivity
        assertEquals(day("2026-11-09"), la?.pickupDate)
        assertEquals(true, la?.startsImmediately)
        assertEquals(utc("2026-11-08T17:00:00Z"), la?.start)
    }

    @Test
    fun starttidenExaktNuStartarDirekt() {
        assertEquals(true, plan(live = true, now = stockholm("2026-11-08T18:00")).liveActivity?.startsImmediately)
        assertEquals(false, plan(live = true, now = stockholm("2026-11-08T17:59")).liveActivity?.startsImmediately)
    }

    @Test
    fun paTomningsdagenPlanerasNastaTomning() {
        assertEquals(day("2026-11-12"), plan(live = true, now = stockholm("2026-11-09T07:00")).liveActivity?.pickupDate)
        assertNull(plan(live = true, now = stockholm("2026-11-09T07:00"), events = listOf(event("2026-11-09", listOf("rest")))).liveActivity)
    }

    @Test
    fun innehallSagerInteImorgon() {
        val content = assertNotNull(plan(live = true).liveActivity?.content)
        assertEquals("Hemma", content.addressName)
        assertEquals("Måndag 9 november", content.dateText)
        assertEquals("Mån 9 nov", content.shortDateText)
        assertFalse(content.dateText.lowercase().contains("morgon"))
        assertFalse(content.shortDateText.lowercase().contains("morgon"))
        assertEquals(
            listOf(
                ActivityFraction(id = "rest", name = "Restavfall", short = "Rest", color = "#111111", icon = "trash"),
                ActivityFraction(id = "mat", name = "Matavfall", short = "Mat", color = "#222222", icon = "leaf"),
            ),
            content.fractions,
        )
        assertFalse(content.estimated)
    }

    @Test
    fun beraknatDatumBlirEgetFaltOchTextenArOforandrad() {
        val content = assertNotNull(plan(live = true, events = listOf(event("2026-11-09", listOf("rest"), estimated = true))).liveActivity?.content)
        assertTrue(content.estimated)
        assertEquals("Måndag 9 november", content.dateText)
        assertEquals("Mån 9 nov", content.shortDateText)
    }

    @Test
    fun okandFraktionIAktivitetenFaarNeutralVisning() {
        val content = assertNotNull(plan(live = true, events = listOf(event("2026-11-09", listOf("nytt")))).liveActivity?.content)
        assertEquals(listOf("nytt"), content.fractions.map { it.id })
        assertEquals("nytt", content.fractions[0].name)
        assertTrue(content.fractions[0].color.isNotEmpty() && content.fractions[0].icon.isNotEmpty())
    }

    @Test
    fun utstalltStopparAktiviteten() {
        val la = plan(live = true, placedOut = homeMonday).liveActivity
        assertEquals(day("2026-11-12"), la?.pickupDate)
        assertEquals(utc("2026-11-11T17:00:00Z"), la?.start)
        // Utställt för en annan adress eller ett annat datum påverkar inte.
        assertEquals(day("2026-11-09"), plan(live = true, placedOut = setOf(PlacedOut(otherKey, day("2026-11-09")))).liveActivity?.pickupDate)
        assertEquals(day("2026-11-09"), plan(live = true, placedOut = setOf(PlacedOut(homeKey, day("2026-11-12")))).liveActivity?.pickupDate)
    }

    @Test
    fun utstalldTomningIDagGerNastaTomning() {
        assertEquals(day("2026-11-12"), plan(live = true, now = stockholm("2026-11-09T07:00"), placedOut = homeMonday).liveActivity?.pickupDate)
    }

    @Test
    fun badaPaBehallerNotisUtanSchemalagdAktivitet() {
        val p = plan(notifications = true, live = true, existing = emptySet())
        assertEquals(day("2026-11-09"), p.liveActivity?.pickupDate)
        assertTrue(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun badaPaGerReservnotisEfterStart() {
        val p = plan(notifications = true, live = true, existing = homeMonday)
        val fallback = assertNotNull(mondayNotification(p))
        // Starten är 18:00, så reserven är 18:45 och inte 18:00.
        assertEquals(stockholm("2026-11-08T18:45"), fallback.fireDate)
        assertNotEquals(p.liveActivity?.start, fallback.fireDate)
        assertEquals("Har du ställt ut kärlen?", fallback.title)
        // Samma innehåll som den vanliga notisen.
        val ordinary = assertNotNull(mondayNotification(plan(notifications = true, live = false)))
        assertEquals(ordinary.body, fallback.body)
        assertNotEquals(ordinary.title, fallback.title)
        assertEquals("Ställ ut kärlen", ordinary.title)
        assertTrue(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-12") })
        // Aktivitetsplanen beror inte på vad som finns.
        assertEquals(plan(notifications = true, live = true, existing = emptySet()).liveActivity, p.liveActivity)
    }

    @Test
    fun reservnotisenHarSammaIdentifierareSomVanligNotis() {
        val fallback = assertNotNull(mondayNotification(plan(notifications = true, live = true, existing = homeMonday)))
        val ordinary = assertNotNull(mondayNotification(plan(notifications = true, live = true, existing = emptySet())))
        assertEquals(ordinary.identifier, fallback.identifier)
        assertTrue(NotificationDiff.isOwn(fallback.identifier))
        // En enda notis för tömningen, aldrig både ordinarie och reserv.
        val p = plan(notifications = true, live = true, existing = homeMonday)
        assertEquals(1, p.notifications.count { it.identifier == fallback.identifier })
        // Diffen ersätter den ordinarie notisen i stället för att lägga till en andra.
        val changes = NotificationDiff.diff(listOf(fallback), pendingIds = setOf(ordinary.identifier), pendingFireDates = mapOf(ordinary.identifier to ordinary.fireDate))
        assertEquals(listOf(fallback), changes.add)
        assertEquals(listOf(fallback.identifier), changes.removeIds)
    }

    @Test
    fun reservnotisensTidHarTak() {
        // Start 22:59 ger 23:44, 23:00 ger 23:45 och en senare start ger aldrig mer än 23:45.
        assertEquals(stockholm("2026-11-08T15:45"), ReminderPlanner.fallbackDate(stockholm("2026-11-08T15:00")))
        assertEquals(stockholm("2026-11-08T23:44"), ReminderPlanner.fallbackDate(stockholm("2026-11-08T22:59")))
        assertEquals(stockholm("2026-11-08T23:45"), ReminderPlanner.fallbackDate(stockholm("2026-11-08T23:00")))
        assertEquals(stockholm("2026-11-08T23:45"), ReminderPlanner.fallbackDate(stockholm("2026-11-08T23:30")))
    }

    @Test
    fun reserventRaknasFranAktivitetensEgenStart() {
        // Aktiviteten väntar med start 17:00 (en äldre påminnelsetid), fast inställningen nu är 20:00.
        val id = PlacedOut(homeKey, day("2026-11-09"))
        val p = plan(notifications = true, live = true, existing = setOf(id), reminderMinutes = 20 * 60, starts = mapOf(id to stockholm("2026-11-08T17:00")))
        assertEquals(stockholm("2026-11-08T17:45"), assertNotNull(mondayNotification(p)).fireDate)
        // Utan känd start används påminnelsetiden.
        val q = plan(notifications = true, live = true, existing = setOf(id), reminderMinutes = 20 * 60)
        assertEquals(stockholm("2026-11-08T20:45"), assertNotNull(mondayNotification(q)).fireDate)
    }

    @Test
    fun passeradOrdinarieTidUtanAktivitetGerIngenNotisMenGeRetainable() {
        val now = stockholm("2026-11-08T18:10")
        assertNull(mondayNotification(plan(notifications = true, live = true, now = now, existing = emptySet())))
        val id = PlannedNotification.identifier(homeKey, day("2026-11-09"), ReminderTiming.EveningBefore)
        assertEquals(PlacedOut(homeKey, day("2026-11-09")), ReminderPlanner.retainable(plannerInput(notifications = true, now = now))[id])
    }

    @Test
    fun retainableUtelamnarUtstalldVisadOchAvstangdaNotiser() {
        val now = stockholm("2026-11-08T18:10")
        val id = PlannedNotification.identifier(homeKey, day("2026-11-09"), ReminderTiming.EveningBefore)
        assertNull(ReminderPlanner.retainable(plannerInput(notifications = true, now = now, placedOut = homeMonday))[id])
        assertNull(ReminderPlanner.retainable(plannerInput(notifications = true, now = now, shown = homeMonday))[id])
        // Användaren har stängt av notiserna: inget behålls.
        assertTrue(ReminderPlanner.retainable(plannerInput(notifications = false, now = now)).isEmpty())
        // Före ordinarie tid planeras den vanliga notisen, och inget behöver behållas.
        assertNull(ReminderPlanner.retainable(plannerInput(notifications = true, now = stockholm("2026-11-08T17:00")))[id])
    }

    @Test
    fun reservnotisenTakasKlockan2345() {
        // 23:00 är sista tillåtna påminnelsetid.
        val p = plan(notifications = true, live = true, existing = homeMonday, reminderMinutes = 23 * 60)
        assertEquals(stockholm("2026-11-08T23:45"), assertNotNull(mondayNotification(p)).fireDate)
    }

    @Test
    fun reservnotisenFolkerSvenskTidOavsettTelefonensZon() {
        // Sommartid och vintertid: väggklockan är densamma. Telefonens zon läses aldrig, vilket körningen med TZ=America/New_York prövar.
        val p = plan(notifications = true, live = true, existing = homeMonday)
        assertEquals(utc("2026-11-08T17:45:00Z"), assertNotNull(mondayNotification(p)).fireDate)
        val spring = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = true), schedule(homeKey, listOf(event("2026-03-30", listOf("rest")))))),
                settings = ReminderSettings(reminderMinutes = 23 * 60, liveActivityOn = true), placedOut = emptySet(), now = stockholm("2026-03-01T12:00"),
                liveActivitiesAllowed = true, existingActivities = setOf(PlacedOut(homeKey, day("2026-03-30"))), shownActivities = emptySet(),
            ),
        )
        assertEquals(utc("2026-03-29T21:45:00Z"), spring.notifications.firstOrNull()?.fireDate)
    }

    @Test
    fun reservnotisenHoppasOverNarTidenPasserat() {
        // Söndag 18:50: reserven 18:45 har passerat.
        assertNull(mondayNotification(plan(notifications = true, live = true, now = stockholm("2026-11-08T18:50"), existing = homeMonday)))
        // Strax före reserven finns den kvar.
        val before = plan(notifications = true, live = true, now = stockholm("2026-11-08T18:44"), existing = homeMonday)
        assertEquals(stockholm("2026-11-08T18:45"), mondayNotification(before)?.fireDate)
    }

    @Test
    fun visadTomningGerIngenReservnotis() {
        val p = plan(notifications = true, live = true, existing = homeMonday, shown = homeMonday)
        assertNull(mondayNotification(p))
        assertTrue(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-12") })
    }

    @Test
    fun utstalldTomningMedAktivitetGerIngenReservnotis() {
        assertNull(mondayNotification(plan(notifications = true, live = true, placedOut = homeMonday, existing = homeMonday)))
    }

    @Test
    fun visadUtanAktivitetGerOrdinarieNotis() {
        // Den bortsvepta aktiviteten finns inte kvar, och då är det den vanliga notisen som gäller.
        val p = plan(notifications = true, live = true, existing = emptySet(), shown = homeMonday)
        assertEquals(stockholm("2026-11-08T18:00"), assertNotNull(mondayNotification(p)).fireDate)
    }

    @Test
    fun bastaLiveActivityUtanNotiserGerIngenNotis() {
        val p = plan(notifications = false, live = true, existing = homeMonday)
        assertTrue(p.notifications.isEmpty())
        assertNotNull(p.liveActivity)
    }

    @Test
    fun aktivitetForAnnatDatumHindrarInteNotis() {
        val otherDate = setOf(PlacedOut(homeKey, day("2026-11-12")))
        assertTrue(plan(notifications = true, live = true, existing = otherDate).notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
        val otherAddress = setOf(PlacedOut(otherKey, day("2026-11-09")))
        assertTrue(plan(notifications = true, live = true, existing = otherAddress).notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun existerandeAktivitetUtanValPaHindrarInteNotis() {
        assertTrue(plan(notifications = true, live = false, existing = homeMonday).notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
        assertTrue(plan(notifications = true, live = true, allowed = false, existing = homeMonday).notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun notisForAnnanAdressSammaDatumBehalls() {
        val p = plan(notifications = true, live = true, otherEvents = listOf(event("2026-11-09", listOf("glas"))), existing = homeMonday)
        val other = assertNotNull(p.notifications.firstOrNull { it.key == otherKey && it.pickupDate == day("2026-11-09") })
        assertEquals("Ställ ut kärlen", other.title)
        assertEquals(stockholm("2026-11-08T18:00"), other.fireDate)
        assertEquals("Har du ställt ut kärlen?", assertNotNull(mondayNotification(p)).title)
    }

    @Test
    fun utstalldTomningGerIngenNotis() {
        val p = plan(notifications = true, live = true, placedOut = homeMonday)
        assertEquals(day("2026-11-12"), p.liveActivity?.pickupDate)
        assertFalse(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
        assertTrue(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-12") })
        assertTrue(p.notifications.any { it.key == otherKey })
    }

    @Test
    fun ogiltigPaminnelsetidGerStandardtid() {
        for (minutes in listOf(0, -1, 2880, 899, 1381, 1000)) {
            assertEquals(utc("2026-11-08T17:00:00Z"), plan(notifications = true, reminderMinutes = minutes).notifications[0].fireDate, "$minutes")
            assertEquals(utc("2026-11-08T17:00:00Z"), plan(live = true, reminderMinutes = minutes).liveActivity?.start, "$minutes")
        }
    }

    @Test
    fun varningFolkerMedIAktiviteten() {
        assertEquals("Helgdag.", plan(live = true, events = listOf(event("2026-11-09", listOf("rest"), warning = "Helgdag."))).liveActivity?.content?.warning)
        assertNull(plan(live = true).liveActivity?.content?.warning)
    }

    @Test
    fun langtAdressnamnKortasTill60Tecken() {
        val home = address(homeKey, name = "å".repeat(100), primary = true, notifications = false)
        val p = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(PlannerAddress(home, schedule(homeKey, standardEvents))),
                settings = ReminderSettings(liveActivityOn = true), placedOut = emptySet(), now = friday, liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
            ),
        )
        assertEquals("å".repeat(60), p.liveActivity?.content?.addressName)
        val short = ReminderPlanner.plan(
            PlannerInput(
                addresses = listOf(PlannerAddress(address(homeKey, name = "Hemma", primary = true, notifications = false), schedule(homeKey, standardEvents))),
                settings = ReminderSettings(liveActivityOn = true), placedOut = emptySet(), now = friday, liveActivitiesAllowed = true, existingActivities = emptySet(), shownActivities = emptySet(),
            ),
        )
        assertEquals("Hemma", short.liveActivity?.content?.addressName)
    }

    @Test
    fun hogst60MedFleraAdresser() {
        val entries = (0 until 4).map { n ->
            val key = AddressKey(source = "s", id = "a$n")
            val events = (0 until 30).map { event(day("2026-11-10").plusDays(it * 2 + n).iso, listOf("rest")) }
            PlannerAddress(address(key, name = "A$n", primary = n == 0, notifications = true), schedule(key, events))
        }
        val p = ReminderPlanner.plan(PlannerInput(entries, ReminderSettings(), emptySet(), friday, true, emptySet(), emptySet()))
        assertEquals(60, p.notifications.size)
        assertEquals(p.notifications.map { it.fireDate }.sorted(), p.notifications.map { it.fireDate })
        assertEquals(60, p.notifications.map { it.identifier }.toSet().size)
        // 120 tömningar finns. De 60 närmaste ryms före 2026-11-10 + 30 dagar.
        assertTrue(p.notifications.last().pickupDate <= day("2026-11-10").plusDays(31))
    }

    @Test
    fun liveActivityNekadBehallerNotisen() {
        val p = plan(notifications = true, live = true, allowed = false)
        assertNull(p.liveActivity)
        assertEquals(day("2026-11-09"), p.notifications[0].pickupDate)
    }

    @Test
    fun liveActivityAvBehallerNotisen() {
        assertTrue(plan(notifications = true, live = false).notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun paTomningsdagenGerNastaAktivitetOchNotisenStarKvarUtanExisterandeAktivitet() {
        val p = plan(notifications = true, live = true, now = stockholm("2026-11-09T07:00"))
        assertEquals(day("2026-11-12"), p.liveActivity?.pickupDate)
        assertTrue(p.notifications.any { it.key == homeKey && it.pickupDate == day("2026-11-12") })
    }

    @Test
    fun borttagenHuvudadressGerInteAktivitetForDen() {
        assertNull(plan(live = true, withPrimary = false).liveActivity)
        // Notiserna påverkas inte.
        assertTrue(plan(notifications = true, live = true, withPrimary = false).notifications.any { it.pickupDate == day("2026-11-09") })
    }

    @Test
    fun planenAnvanderTidenFranNowOchInteSvarets_today() {
        // Svaret är hämtat 6 nov, men "i dag" är 11 nov: 9 nov är passerad.
        val la = plan(live = true, now = stockholm("2026-11-11T12:00")).liveActivity
        assertEquals(day("2026-11-12"), la?.pickupDate)
        assertEquals(false, la?.startsImmediately)
    }

    /** Ändrar processens tidszon. Telefonens tidszon får inte påverka planen. */
    @Test
    fun telefonensTidszonSpelarIngenRoll() {
        val saved = TimeZone.getDefault()
        try {
            fun run(zone: String): ReminderPlan {
                TimeZone.setDefault(TimeZone.getTimeZone(zone))
                return plan(notifications = true, live = true, now = stockholm("2026-11-08T20:00"))
            }
            val stockholmPlan = run("Europe/Stockholm")
            val newYorkPlan = run("America/New_York")
            val tokyoPlan = run("Asia/Tokyo")
            assertEquals(newYorkPlan, stockholmPlan)
            assertEquals(tokyoPlan, stockholmPlan)
            assertEquals(utc("2026-11-08T17:00:00Z"), stockholmPlan.liveActivity?.start)
            assertEquals(utc("2026-11-09T17:00:00Z"), stockholmPlan.notifications.firstOrNull()?.fireDate)
        } finally {
            TimeZone.setDefault(saved)
        }
    }

    // MARK: Samma morgon

    @Test
    fun morgonNotisSammaDag() {
        val p = plan(notifications = true, timing = ReminderTiming.SameMorning)
        assertEquals(stockholm("2026-11-09T06:00"), assertNotNull(homeNotification(p, "2026-11-09")).fireDate)
        assertEquals(stockholm("2026-11-12T06:00"), assertNotNull(homeNotification(p, "2026-11-12")).fireDate)
    }

    @Test
    fun morgonPasseradHoppasÖver() {
        val p = plan(notifications = true, now = stockholm("2026-11-09T07:00"), timing = ReminderTiming.SameMorning)
        assertNull(homeNotification(p, "2026-11-09"))
        assertEquals(stockholm("2026-11-12T06:00"), assertNotNull(homeNotification(p, "2026-11-12")).fireDate)
    }

    @Test
    fun morgonBockTystar() {
        val monday = PlacedOut(homeKey, day("2026-11-09"))
        val now = stockholm("2026-11-09T05:00")
        assertNull(homeNotification(plan(notifications = true, now = now, placedOut = setOf(monday), timing = ReminderTiming.SameMorning), "2026-11-09"))
        // Ångras bocken före tiden kommer påminnelsen tillbaka.
        assertEquals(stockholm("2026-11-09T06:00"), homeNotification(plan(notifications = true, now = now, timing = ReminderTiming.SameMorning), "2026-11-09")?.fireDate)
    }

    @Test
    fun morgonReserv() {
        val id = PlacedOut(homeKey, day("2026-11-09"))
        val p = plan(notifications = true, live = true, existing = setOf(id), timing = ReminderTiming.SameMorning, starts = mapOf(id to stockholm("2026-11-09T06:00")))
        val note = assertNotNull(homeNotification(p, "2026-11-09"))
        assertEquals(stockholm("2026-11-09T06:45"), note.fireDate)
        assertEquals(ReminderPlanner.FALLBACK_TITLE, note.title)
    }

    @Test
    fun reservensTakPåMorgonen() {
        assertEquals(stockholm("2026-11-09T12:00"), ReminderPlanner.fallbackDate(stockholm("2026-11-09T11:30")))
        assertEquals(stockholm("2026-11-09T09:45"), ReminderPlanner.fallbackDate(stockholm("2026-11-09T09:00")))
    }

    @Test
    fun morgonRetainable() {
        val id = PlannedNotification.identifier(homeKey, day("2026-11-09"), ReminderTiming.SameMorning)
        assertEquals(PlacedOut(homeKey, day("2026-11-09")), ReminderPlanner.retainable(plannerInput(notifications = true, now = stockholm("2026-11-09T06:30"), timing = ReminderTiming.SameMorning))[id])
        assertNull(ReminderPlanner.retainable(plannerInput(notifications = true, now = stockholm("2026-11-09T05:30"), timing = ReminderTiming.SameMorning))[id])
    }

    @Test
    fun morgonAktivitetIDagFöreTolv() {
        val activity = assertNotNull(plan(live = true, now = stockholm("2026-11-09T07:30"), timing = ReminderTiming.SameMorning).liveActivity)
        assertEquals(day("2026-11-09"), activity.pickupDate)
        assertEquals(stockholm("2026-11-09T06:00"), activity.start)
        assertTrue(activity.startsImmediately)
    }

    @Test
    fun morgonAktivitetIDagEfterTolv() {
        val activity = assertNotNull(plan(live = true, now = stockholm("2026-11-09T12:00"), timing = ReminderTiming.SameMorning).liveActivity)
        assertEquals(day("2026-11-12"), activity.pickupDate)
        assertEquals(stockholm("2026-11-12T06:00"), activity.start)
        assertFalse(activity.startsImmediately)
    }

    @Test
    fun morgonAktivitetKvällenFöreSchemaläggs() {
        val activity = assertNotNull(plan(live = true, now = stockholm("2026-11-08T20:00"), timing = ReminderTiming.SameMorning).liveActivity)
        assertEquals(day("2026-11-09"), activity.pickupDate)
        assertEquals(stockholm("2026-11-09T06:00"), activity.start)
        assertFalse(activity.startsImmediately)
    }

    @Test
    fun morgonUtställdIDag() {
        val p = plan(live = true, now = stockholm("2026-11-09T07:30"), placedOut = setOf(PlacedOut(homeKey, day("2026-11-09"))), timing = ReminderTiming.SameMorning)
        assertEquals(day("2026-11-12"), assertNotNull(p.liveActivity).pickupDate)
    }

    @Test
    fun reservenFöljerAktivitetensStartEfterBytTillMorgon() {
        // Kvällens väntande aktivitet står kvar efter bytet till samma morgon, till exempel när den nya inte kunde startas.
        val id = PlacedOut(homeKey, day("2026-11-09"))
        val p = plan(notifications = true, live = true, now = stockholm("2026-11-08T10:00"), existing = setOf(id), timing = ReminderTiming.SameMorning, starts = mapOf(id to stockholm("2026-11-08T18:00")))
        assertEquals(stockholm("2026-11-08T18:45"), assertNotNull(homeNotification(p, "2026-11-09")).fireDate)
    }

    @Test
    fun tömningsdagenFrånPåminnelsensKlockslag() {
        assertEquals(day("2026-11-09"), ReminderTime.pickupDay(stockholm("2026-11-09T06:00")))
        assertEquals(day("2026-11-09"), ReminderTime.pickupDay(stockholm("2026-11-09T11:59")))
        assertEquals(day("2026-11-09"), ReminderTime.pickupDay(stockholm("2026-11-08T18:45")))
        assertEquals(day("2026-11-09"), ReminderTime.pickupDay(stockholm("2026-11-08T23:45")))
    }

    // MARK: Två påminnelser

    @Test
    fun bådaValenGerTvåNotiser() {
        val p = ReminderPlanner.plan(twoInput(ReminderSettings(morningOn = true), now = stockholm("2026-11-10T12:00")))
        assertEquals(listOf(stockholm("2026-11-10T18:00"), stockholm("2026-11-11T06:00")), p.notifications.map { it.fireDate })
        assertEquals(listOf(eveningId, morningId), p.notifications.map { it.identifier })
        assertNotEquals(morningId, eveningId)
    }

    @Test
    fun kvällenPasseradMorgonenKvar() {
        val p = ReminderPlanner.plan(twoInput(ReminderSettings(morningOn = true), now = stockholm("2026-11-10T19:00")))
        assertEquals(listOf(morningId), p.notifications.map { it.identifier })
    }

    @Test
    fun bockMellanKvällOchMorgon() {
        val now = stockholm("2026-11-10T19:00")
        assertTrue(ReminderPlanner.plan(twoInput(ReminderSettings(morningOn = true), now = now, placedOut = setOf(wedId))).notifications.isEmpty())
        assertEquals(listOf(morningId), ReminderPlanner.plan(twoInput(ReminderSettings(morningOn = true), now = now)).notifications.map { it.identifier })
    }

    @Test
    fun reservenGällerAktivitetensVal() {
        val settings = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.EveningBefore, liveActivityOn = true)
        val now = stockholm("2026-11-10T12:00")
        val starts = mapOf(wedId to stockholm("2026-11-10T18:00"))
        val p = ReminderPlanner.plan(twoInput(settings, now = now, existing = setOf(wedId), starts = starts))
        val evening = p.notifications.firstOrNull { it.identifier == eveningId }
        val morning = p.notifications.firstOrNull { it.identifier == morningId }
        assertEquals(stockholm("2026-11-10T18:45"), evening?.fireDate)
        assertEquals(ReminderPlanner.FALLBACK_TITLE, evening?.title)
        assertEquals(stockholm("2026-11-11T06:00"), morning?.fireDate)
        assertEquals(ReminderPlanner.ORDINARY_TITLE, morning?.title)

        val shown = ReminderPlanner.plan(twoInput(settings, now = now, existing = setOf(wedId), shown = setOf(wedId), starts = starts))
        assertEquals(listOf(morningId), shown.notifications.map { it.identifier })
    }

    @Test
    fun ingenReservUtanAktivitetensVal() {
        val settings = ReminderSettings(eveningOn = true, morningOn = false, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true)
        val starts = mapOf(wedId to stockholm("2026-11-11T06:00"))
        val p = ReminderPlanner.plan(twoInput(settings, now = stockholm("2026-11-10T12:00"), existing = setOf(wedId), starts = starts))
        assertEquals(1, p.notifications.size)
        assertEquals(stockholm("2026-11-10T18:00"), p.notifications.firstOrNull()?.fireDate)
        assertEquals(ReminderPlanner.ORDINARY_TITLE, p.notifications.firstOrNull()?.title)
        assertFalse(p.notifications.any { it.fireDate == stockholm("2026-11-11T06:45") })
    }

    @Test
    fun aktivitetenFöljerSittVal() {
        val settings = ReminderSettings(eveningOn = true, morningOn = false, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true)
        val activity = assertNotNull(ReminderPlanner.plan(twoInput(settings, now = stockholm("2026-11-10T12:00"))).liveActivity)
        assertEquals(wed, activity.pickupDate)
        assertEquals(stockholm("2026-11-11T06:00"), activity.start)
    }

    @Test
    fun taketRäknarVarjeNotis() {
        val events = (0 until 40).map { event(wed.plusDays(it * 2).iso, listOf("rest")) }
        val p = ReminderPlanner.plan(twoInput(ReminderSettings(morningOn = true), now = stockholm("2026-11-10T12:00"), events = events))
        assertEquals(60, p.notifications.size)
        assertEquals(p.notifications.map { it.fireDate }.sorted(), p.notifications.map { it.fireDate })
        assertEquals(stockholm("2026-11-10T18:00"), p.notifications.firstOrNull()?.fireDate)
        assertEquals(wed.plusDays(29 * 2), p.notifications.lastOrNull()?.pickupDate)
    }

    @Test
    fun retainablePerVal() {
        // Bara aktivitetens val kan ha en reserv, så kvällens id behålls och morgonens (som inte passerat) inte.
        val r = ReminderPlanner.retainable(twoInput(ReminderSettings(morningOn = true, liveActivityOn = true), now = stockholm("2026-11-10T19:00")))
        assertEquals(setOf(eveningId), r.keys)
    }

    @Test
    fun retainableBehållerBaraAktivitetensVal() {
        val on = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.EveningBefore, liveActivityOn = true)
        // Kvällen före är aktivitetens val och dess tid har passerat: bara kvällens id kan vara en reserv.
        assertEquals(setOf(eveningId), ReminderPlanner.retainable(twoInput(on, now = stockholm("2026-11-10T19:00"))).keys)
        val morning = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true)
        assertEquals(setOf(morningId), ReminderPlanner.retainable(twoInput(morning, now = stockholm("2026-11-11T07:00"))).keys)
        assertTrue(ReminderPlanner.retainable(twoInput(morning, now = stockholm("2026-11-10T19:00"))).isEmpty())
    }

    @Test
    fun retainableBehållerBaraAktivitetensValÄvenMedAktivitetenAv() {
        // Slås aktiviteten av står reserven kvar, men det andra valets passerade notis blir aldrig en reserv.
        val off = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.EveningBefore, liveActivityOn = false)
        assertEquals(setOf(eveningId), ReminderPlanner.retainable(twoInput(off, now = stockholm("2026-11-10T19:00"))).keys)
        val morningOff = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = false)
        assertTrue(ReminderPlanner.retainable(twoInput(morningOff, now = stockholm("2026-11-10T19:00"))).isEmpty())
        assertEquals(setOf(morningId), ReminderPlanner.retainable(twoInput(morningOff, now = stockholm("2026-11-11T07:00"))).keys)
    }

    @Test
    fun retainableBehållerInteValetNärAktivitetensValÄrAvslaget() {
        // Aktiviteten följer morgonen men morgonen är avslagen: inget val har en reserv att behålla.
        val s = ReminderSettings(eveningOn = true, morningOn = false, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true)
        assertTrue(ReminderPlanner.retainable(twoInput(s, now = stockholm("2026-11-10T19:00"))).isEmpty())
    }

    @Test
    fun ingenReservNärAktivitetenHarAnnanTid() {
        // Notisen 15:00 och aktiviteten 21:00 samma kväll: notisen kommer som vanligt, och aktiviteten aviserar själv.
        val settings = ReminderSettings(reminderMinutes = 900, liveActivityMinutes = 1260, liveActivityOn = true)
        val starts = mapOf(wedId to stockholm("2026-11-10T21:00"))
        val p = ReminderPlanner.plan(twoInput(settings, now = stockholm("2026-11-10T12:00"), existing = setOf(wedId), starts = starts))
        val evening = p.notifications.firstOrNull { it.identifier == eveningId }
        assertEquals(stockholm("2026-11-10T15:00"), evening?.fireDate)
        assertEquals(ReminderPlanner.ORDINARY_TITLE, evening?.title)
        assertEquals(stockholm("2026-11-10T21:00"), p.liveActivity?.start)
        // Ingen kvarlämnad notis räknas som reserv när tiderna skiljer sig.
        assertTrue(ReminderPlanner.retainable(twoInput(settings, now = stockholm("2026-11-10T16:00"), existing = setOf(wedId), starts = starts)).isEmpty())
    }
}
