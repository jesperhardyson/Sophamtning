package se.hardyson.sophamtning.core.app

import java.io.File
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.reminders.ActivityFraction
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.LiveActivityNotInForeground
import se.hardyson.sophamtning.core.reminders.LiveActivityPhase
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.SystemActivity
import se.hardyson.sophamtning.core.reminders.address
import se.hardyson.sophamtning.core.reminders.cached
import se.hardyson.sophamtning.core.reminders.event
import se.hardyson.sophamtning.core.reminders.response
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.tempDir

private fun sundayAt(minutes: Int): Instant = StockholmClock.dateOn(day("2026-11-08"), minutes)

private val rest = FractionInfo("Restavfall", "Rest", "#111111", "trash")

private fun pickupContent(name: String = "Hemma") =
    PickupActivityContent(name, "Måndag 9 november", "Mån 9 nov", listOf(ActivityFraction("rest", "Restavfall", "Rest", "#111111", "trash")), false, null)

private val homeKey = AddressKey("orebro", "1")
private val otherKey = AddressKey("orebro", "2")
private val monday = day("2026-11-09")
private val thursday = day("2026-11-12")

/** Fredag 6 november 12:00. Tömning måndag 9 och torsdag 12 november. `sundayEvening` är söndag 8 november 19:00. */
private val friday = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)
private val sundayEvening = StockholmClock.dateOn(day("2026-11-08"), 19 * 60)

private fun schedule(key: AddressKey, dates: List<DayDate>, warning: String? = null): AddressResponse =
    response(key, dates.map { event(it.iso, listOf("rest"), warning = warning) }, mapOf("rest" to rest))

/** Ett API som aldrig svarar: allt planeras från lagringen. */
private class OfflineApi : UnusedApi() {
    override suspend fun address(url: String): AddressResponse = throw ApiError.Network
}

/** Två adresser med sparade scheman och sparade val. Testerna styr tiden med `clock`. */
private class Fixture(
    private val scope: CoroutineScope,
    now: Instant = friday,
    liveOn: Boolean = true,
    systemEnabled: Boolean = true,
    notificationStatus: NotificationAuthorization = NotificationAuthorization.Authorized,
    dates: List<DayDate> = listOf(monday, thursday),
    homeNotifications: Boolean = true,
) {
    val dir: File = tempDir()
    val log = Log()
    val notifications = FakeNotifications(notificationStatus, log = log)
    val activities = FakeActivities(log, systemEnabled)
    val clock = TestClock(now)
    val store = LocalStore(dir)

    init {
        store.setAddresses(listOf(address(homeKey, "Hemma", primary = true, notifications = homeNotifications), address(otherKey, "Stugan", primary = false)))
        store.setSchedule(cached(schedule(homeKey, dates), fetchedAt = now), homeKey)
        store.setSchedule(cached(schedule(otherKey, listOf(thursday)), fetchedAt = now), otherKey)
        store.setSettings(ReminderSettings(reminderMinutes = 1080, liveActivityOn = liveOn))
    }

    fun model() = AppModel(OfflineApi(), store, notifications, activities, { clock.now }, scope)
}

private fun TestScope.fixture(
    now: Instant = friday,
    liveOn: Boolean = true,
    systemEnabled: Boolean = true,
    notificationStatus: NotificationAuthorization = NotificationAuthorization.Authorized,
    homeNotifications: Boolean = true,
) = Fixture(backgroundScope, now, liveOn, systemEnabled, notificationStatus, homeNotifications = homeNotifications)

private suspend fun apply(model: AppModel, startingActivities: Boolean = true) {
    model.applyReminders(startingActivities)
    model.settleReminders()
}

private val AppModel.s: AppState get() = state.value

private fun AppModel.home() = s.addresses.first { it.key == homeKey }

/** Söndag 18:10. Live Updaten för måndag skulle ha startat 18:00, mer än marginalen sedan, och väntar fortfarande. */
private val sundayPastStart = sundayAt(18 * 60 + 10)

private fun overdue(f: Fixture) {
    f.activities.insert(SystemActivity(ExistingActivity("gammal", homeKey, monday, pickupContent(), true, sundayAt(18 * 60)), LiveActivityPhase.Pending))
}

/** Reserven väntar 18:45. Klockan är sedan 18:10: ordinarie tid 18:00 har passerat, och en ny planering ger ingen vanlig notis. */
private suspend fun withReserve(f: Fixture): AppModel {
    val model = f.model()
    apply(model)
    assertTrue(f.notifications.isFallback("2026-11-09"))
    f.clock.set(sundayAt(18 * 60 + 10))
    return model
}

private fun reserveKvar(f: Fixture) {
    assertTrue(f.notifications.isFallback("2026-11-09"))
    assertEquals(sundayAt(18 * 60 + 45), f.notifications.notification("2026-11-09")?.fireDate)
    assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
}

// Från AppModelLiveActivityTests på iOS, utan hushållets bockar. Android har inget hushåll än.
class AppModelLiveActivityTest {
    // Opt-in

    @Test
    fun ingetSchemalaggsForranValetArPa() = runTest {
        val f = fixture(liveOn = false)
        apply(f.model())
        assertTrue(f.activities.starts.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
    }

    @Test
    fun valetPaStartarOchErsatterNotisenForTomningenMedReserv() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        assertEquals(listOf(monday), f.activities.starts.map { it.pickupDate })
        assertEquals(false, f.activities.starts.first().startsImmediately)
        // En enda notis för måndagen, och det är reserven 45 minuter efter starten. Torsdagen har en vanlig.
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        assertEquals(sundayAt(18 * 60 + 45), f.notifications.notification("2026-11-09")?.fireDate)
        assertFalse(f.notifications.isFallback("2026-11-12"))
        assertEquals(monday, model.s.currentLiveActivity?.pickupDate)
        assertNull(model.s.liveActivityError)
    }

    @Test
    fun ordningenMedAppenOppen() = runTest {
        val f = fixture(liveOn = false)
        val model = f.model()
        apply(model)
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        f.log.clear()
        model.setLiveActivity(true)
        model.settleReminders()
        // Notisen ersätts av reserven först när Live Updaten faktiskt finns. Samma identifierare, så ingen tas bort.
        assertEquals(listOf("start 2026-11-09", "notis+ 2026-11-09"), f.log.all)
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
    }

    @Test
    fun misslyckadStartLamnarNotisenKvar() = runTest {
        val f = fixture(liveOn = false)
        val model = f.model()
        apply(model)
        f.activities.setFailing(true)
        f.log.clear()
        model.setLiveActivity(true)
        model.settleReminders()
        assertTrue(f.activities.starts.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertFalse("notis- 2026-11-09" in f.log.all)
        // Misslyckad start: den vanliga notisen på ordinarie tid, inte reserven.
        assertFalse(f.notifications.isFallback("2026-11-09"))
        assertEquals(sundayAt(18 * 60), f.notifications.notification("2026-11-09")?.fireDate)
        assertNotNull(model.s.liveActivityError)
        assertNull(model.s.currentLiveActivity)
        // Nästa försök lyckas, och felet försvinner. Notisen blir reserven.
        f.activities.setFailing(false)
        apply(model)
        assertEquals(1, f.activities.starts.size)
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        assertNull(model.s.liveActivityError)
    }

    @Test
    fun samkorningGerIngenDubbelstart() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.log.clear()
        apply(model)
        assertEquals(1, f.activities.starts.size)
        assertTrue(f.log.all.isEmpty())
    }

    // Lägen

    @Test
    fun avslutadeAktiviteterRaknasInte() = runTest {
        for (phase in listOf(LiveActivityPhase.Ended, LiveActivityPhase.Dismissed, LiveActivityPhase.Stale)) {
            val f = fixture(liveOn = true)
            // Live Updaten för måndag finns i listan men gäller inte längre. Notisen får inte försvinna tyst.
            f.activities.setFailing(true)
            val content = PickupActivityContent("Hemma", "Måndag 9 november", "Mån 9 nov", emptyList(), false, null)
            f.activities.insert(SystemActivity(ExistingActivity("x", homeKey, monday, content, false, friday), phase))
            val model = f.model()
            apply(model)
            assertTrue("2026-11-09" in f.notifications.dates, "$phase")
            assertNull(model.s.currentLiveActivity, "$phase")
            // Bara en inaktuell behöver tas bort, en avslutad är redan borta.
            assertEquals(phase == LiveActivityPhase.Stale, "remove x" in f.log.all, "$phase")
        }
    }

    // Valet av

    @Test
    fun avstangtValLaggerInNotisenForeBorttagningen() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        val id = f.activities.ids.first()
        f.log.clear()
        model.setLiveActivity(false)
        model.settleReminders()
        val log = f.log.all
        assertTrue(log.indexOf("notis+ 2026-11-09") in 0 until log.indexOf("remove $id"))
        assertTrue(f.activities.ids.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertNull(model.s.currentLiveActivity)
    }

    @Test
    fun avstangtValTarBortPagaendeForIDag() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        f.activities.promote()
        f.clock.set(StockholmClock.dateOn(monday, 8 * 60))
        apply(model)
        // Dagens lever kvar, och nästa är schemalagd.
        assertEquals(2, f.activities.ids.size)
        model.setLiveActivity(false)
        model.settleReminders()
        assertTrue(f.activities.ids.isEmpty())
    }

    @Test
    fun bytHuvudadressTarBortPagaendeOchLaggerInNotisForst() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.promote()
        val id = f.activities.ids.first()
        f.log.clear()
        model.setPrimary(otherKey)
        model.settleReminders()
        val log = f.log.all
        assertTrue(log.indexOf("notis+ 2026-11-09") in 0 until log.indexOf("remove $id"))
        assertFalse(f.activities.activities.any { it.key == homeKey })
        assertTrue(f.activities.activities.any { it.key == otherKey })
        assertTrue("2026-11-09" in f.notifications.dates)
    }

    @Test
    fun namnbytePaVantandeErsatterDenMedNyttNamn() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        val old = f.activities.ids.first()
        model.rename(homeKey, "Stugan")
        model.settleReminders()
        assertFalse(old in f.activities.ids)
        assertEquals(listOf("Stugan"), f.activities.activities.map { it.content.addressName })
        assertEquals(2, f.activities.starts.size)
    }

    // Ersätta en väntande

    @Test
    fun nyStartasForeBorttagningenAvGamla() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        val old = f.activities.ids.first()
        f.log.clear()
        model.rename(homeKey, "Stugan")
        model.settleReminders()
        val log = f.log.all
        assertTrue(log.indexOf("start 2026-11-09") in 0 until log.indexOf("remove $old"))
    }

    @Test
    fun misslyckadErsattningLamnarDenGamlaKvar() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        val old = f.activities.ids.first()
        f.activities.setFailing(true)
        model.rename(homeKey, "Stugan")
        model.settleReminders()
        assertEquals(listOf(old), f.activities.ids)
        assertNotNull(model.s.liveActivityError)
        // Den gamla aviserar, och reserven ligger kvar bakom den.
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        assertEquals(old, model.s.currentLiveActivity?.id)
    }

    @Test
    fun utanForgrundGerStartenIngetFelmeddelande() = runTest {
        val f = fixture()
        f.activities.setFailing(true, LiveActivityNotInForeground())
        val model = f.model()
        apply(model)
        assertNull(model.s.liveActivityError)
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
    }

    // Väntande vars start har passerat

    @Test
    fun passeradVantandeErsattsMedAppenOppen() = runTest {
        val f = fixture(now = sundayPastStart)
        overdue(f)
        apply(f.model())
        assertFalse("gammal" in f.activities.ids)
        assertEquals(listOf(monday), f.activities.starts.map { it.pickupDate })
        // Den nya syns direkt, och då behövs ingen reserv för måndagen.
        assertNull(f.notifications.notification("2026-11-09"))
    }

    @Test
    fun passeradVantandeTackasAvReservnotisenIBakgrunden() = runTest {
        val f = fixture(now = sundayPastStart)
        overdue(f)
        val model = f.model()
        apply(model, startingActivities = false)
        assertEquals(listOf("gammal"), f.activities.ids)
        // Den vanliga tiden 18:00 har passerat, och reserven 18:45 är den riktiga notisen.
        assertTrue(f.notifications.isFallback("2026-11-09"))
        assertEquals(sundayAt(18 * 60 + 45), f.notifications.notification("2026-11-09")?.fireDate)
        // Kortet lovar ingen tid som redan passerat.
        assertNull(model.s.currentLiveActivity)
    }

    @Test
    fun passeradVantandeNarReserventidenOcksaPasseratGerIngenNotis() = runTest {
        val f = fixture(now = sundayAt(18 * 60 + 50))
        overdue(f)
        apply(f.model(), startingActivities = false)
        assertNull(f.notifications.notification("2026-11-09"))
    }

    // Bortsvept

    @Test
    fun bortsveptStartasInteOmForSammaTomning() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        f.activities.setPhase(LiveActivityPhase.Dismissed, f.activities.ids.first())
        apply(model)
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
        assertTrue(model.s.handledPickup(homeKey, monday))
    }

    @Test
    fun avslutadOchBortaUrListanStartasInteOmNarDenSetts() = runTest {
        // Sedd som pågående av en tidigare körning, och sedan borta utan spår hos systemet.
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.promote()
        apply(model)
        f.activities.clearAll()
        apply(f.model())
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
    }

    @Test
    fun direktstartRaknasSomVisad() = runTest {
        val f = fixture(now = sundayEvening)
        apply(f.model())
        f.activities.clearAll()
        apply(f.model())
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
    }

    @Test
    fun utanBevisStartasDenIgen() = runTest {
        // Väntande som försvunnit utan att ha setts som pågående: säkra riktningen är att starta.
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.clearAll()
        apply(model)
        assertEquals(listOf(monday, monday), f.activities.starts.map { it.pickupDate })
    }

    @Test
    fun avslutadVantandeForeStarttidenStopparInte() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.setPhase(LiveActivityPhase.Ended, f.activities.ids.first())
        apply(model)
        assertEquals(listOf(monday, monday), f.activities.starts.map { it.pickupDate })
    }

    @Test
    fun egenBorttagningRaknasInteSomBortsvept() = runTest {
        val f = fixture(now = sundayEvening)
        f.activities.keepsRemoved = true
        val model = f.model()
        apply(model)
        model.setLiveActivity(false)
        model.settleReminders()
        model.setLiveActivity(true)
        model.settleReminders()
        // Valet stängdes av och på igen. Det är inget svep, så samma tömning startas på nytt.
        assertEquals(listOf(monday, monday), f.activities.starts.map { it.pickupDate })
    }

    @Test
    fun bortsveptBehallerNotisenOmDenLiggerFramfor() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.promote()
        apply(model)
        f.activities.setPhase(LiveActivityPhase.Dismissed, f.activities.ids.first())
        apply(model)
        // Bara omstarten stoppas. Notisen får aldrig försvinna tyst.
        assertTrue("2026-11-09" in f.notifications.dates)
    }

    // Dagens innehåll

    @Test
    fun dagensPagaendeFarNyttNamn() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        f.activities.promote()
        val id = f.activities.ids.first()
        f.clock.set(StockholmClock.dateOn(monday, 8 * 60))
        apply(model)
        model.rename(homeKey, "Stugan")
        model.settleReminders()
        assertEquals("Stugan", f.activities.activities.first { it.id == id }.content.addressName)
    }

    // Passerad påminnelse

    @Test
    fun passeradPaminnelseVisasInteNarAktivitetenVisas() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        assertEquals(true, f.activities.starts.first().startsImmediately)
        assertNull(model.s.missedReminderText(f.clock.now))
        assertFalse(model.s.missedReminderApplies(model.home(), f.clock.now))
    }

    @Test
    fun passeradPaminnelseVisasInteEfterUtstallt() = runTest {
        val f = fixture(now = sundayEvening, liveOn = false)
        f.store.setPlacedOut(listOf(PlacedOut(homeKey, monday)))
        val model = f.model()
        apply(model)
        assertNull(model.s.missedReminderText(f.clock.now))
    }

    @Test
    fun misslyckadDirektstartMedNotiserVisarFelOchPasseradPaminnelse() = runTest {
        val f = fixture(now = sundayEvening)
        f.activities.setFailing(true)
        val model = f.model()
        apply(model)
        val home = model.home()
        assertTrue(f.activities.ids.isEmpty())
        assertFalse("2026-11-09" in f.notifications.dates)
        assertNotNull(model.s.liveActivityError)
        val missed = model.s.missedReminderText(home, f.clock.now)
        assertNotNull(missed)
        val s = model.s
        val content = HomeContent.make(
            s.addresses, s.schedules, s.settings, f.clock.now, remindersAllowed = true, liveActivity = s.currentLiveActivity,
            liveActivitiesEnabled = s.liveActivitiesEnabled, liveActivityError = s.liveActivityError, missedReminder = missed,
        )
        assertEquals(s.liveActivityError, content.primary?.reminder?.detail)
    }

    @Test
    fun passeradPaminnelseVisasUtanAktivitet() = runTest {
        val f = fixture(now = sundayEvening, liveOn = false)
        val model = f.model()
        apply(model)
        assertNotNull(model.s.missedReminderText(f.clock.now))
    }

    // Utan start, som i bakgrunden på iOS

    @Test
    fun bakgrundenStartarAldrigOchLaggerNotisen() = runTest {
        val f = fixture()
        apply(f.model(), startingActivities = false)
        assertTrue(f.activities.starts.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
    }

    @Test
    fun bakgrundenFarTaBortOchUppdatera() = runTest {
        val f = fixture(now = sundayEvening)
        apply(f.model())
        f.activities.promote()
        val id = f.activities.ids.first()
        // Ny varning från källan: en pågående Live Update uppdateras även utan start.
        f.store.setSchedule(cached(schedule(homeKey, listOf(monday, thursday), warning = "Helgdag"), fetchedAt = sundayEvening), homeKey)
        apply(f.model(), startingActivities = false)
        assertEquals(listOf(id), f.activities.updates)
        // Tömningen försvinner ur schemat: Live Updaten tas bort, ingen ny startas och notisen för nästa tömning läggs in.
        f.store.setSchedule(cached(schedule(homeKey, listOf(thursday)), fetchedAt = sundayEvening), homeKey)
        apply(f.model(), startingActivities = false)
        assertTrue(f.activities.ids.isEmpty())
        assertEquals(1, f.activities.starts.size)
        assertEquals(listOf("2026-11-12"), f.notifications.dates)
    }

    @Test
    fun bakgrundenBehandlarBefintligAktivitetSomBefintlig() = runTest {
        val f = fixture()
        apply(f.model())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        apply(f.model(), startingActivities = false)
        // Reserven planeras ändå, eftersom den bara är en notis.
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        assertEquals(1, f.activities.starts.size)
    }

    @Test
    fun bakgrundskorningenStartarAldrig() = runTest {
        val f = fixture()
        val model = f.model()
        BackgroundRefreshRun(model, startingActivities = false).run()
        model.settleReminders()
        assertTrue(f.activities.starts.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
    }

    // Utställt

    @Test
    fun utstalltStartasInteIgen() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        assertEquals(true, f.activities.starts.first().startsImmediately)
        // Knappen trycks: posten sparas och Live Updaten avslutas utanför appen.
        LocalStore(f.dir).markPlacedOut(PlacedOut(homeKey, monday), day("2026-11-08"))
        f.activities.clearAll()
        apply(model)
        // Nästa tömning schemaläggs, och den utställda startas inte igen.
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
        assertFalse("2026-11-09" in f.notifications.dates)
    }

    @Test
    fun avslutadMenFortfarandeVisadAktivitetOmstartasInteOchRorInteReserven() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        val id = f.activities.ids.first()
        f.activities.promote()
        apply(model)
        // Klart trycks: valet sparas, och Live Updaten avslutas men visas med bock i tre sekunder till.
        f.store.markPlacedOut(PlacedOut(homeKey, monday), day("2026-11-08"))
        f.activities.setPhase(LiveActivityPhase.Ended, id)
        f.log.clear()
        repeat(2) {
            apply(model)
            apply(f.model())
        }
        assertNotEquals(monday, model.s.currentLiveActivity?.pickupDate)
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
        assertFalse(f.log.all.any { it.startsWith("remove") || it.startsWith("update") })
        assertFalse(f.log.all.any { it.startsWith("start ${monday.iso}") })
        assertFalse("2026-11-09" in f.notifications.dates)
    }

    /** Sparandet av Utställt misslyckades, men Live Updaten är avslutad och visas med bock en stund till. */
    @Test
    fun utstalltUtanSparadPostStartarInteOmOchReserventFoljerBeviset() = runTest {
        // Aldrig sedd som visad: reserven ligger kvar, och samma tömning startas inte om.
        val unseen = fixture()
        val unseenModel = withReserve(unseen)
        unseen.activities.setPhase(LiveActivityPhase.Ended, unseen.activities.ids.first())
        unseen.log.clear()
        repeat(2) { apply(unseenModel); apply(unseen.model()) }
        assertTrue(unseen.store.placedOut().isEmpty())
        assertEquals(listOf(monday, thursday), unseen.activities.starts.map { it.pickupDate })
        assertFalse(unseen.log.all.any { it.startsWith("start ${monday.iso}") })
        reserveKvar(unseen)

        // Sedd som visad innan: den bevisat visade släcker reserven, men startas ändå inte om.
        val seen = fixture(now = sundayEvening)
        val seenModel = seen.model()
        apply(seenModel)
        val seenId = seen.activities.ids.first()
        seen.activities.promote()
        apply(seenModel)
        seen.activities.setPhase(LiveActivityPhase.Ended, seenId)
        seen.log.clear()
        repeat(2) { apply(seenModel); apply(seen.model()) }
        assertTrue(seen.store.placedOut().isEmpty())
        assertFalse(seen.log.all.any { it.startsWith("start ${monday.iso}") })
        assertFalse("2026-11-09" in seen.notifications.dates)
    }

    @Test
    fun gamlaPosterRensasVidPlanering() = runTest {
        val f = fixture()
        f.store.setPlacedOut(listOf(PlacedOut(homeKey, day("2026-11-01")), PlacedOut(homeKey, monday)))
        apply(f.model())
        assertEquals(listOf(PlacedOut(homeKey, monday)), f.store.placedOut())
    }

    // Dagens Live Update

    @Test
    fun dagensAktivitetLeverKvarNarNastaPlaneras() = runTest {
        val f = fixture(now = sundayEvening)
        val model = f.model()
        apply(model)
        f.activities.promote()
        val id = f.activities.ids.first()
        f.clock.set(StockholmClock.dateOn(monday, 8 * 60))
        apply(model)
        assertEquals(id, f.activities.ids.first())
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
        // Pågående visas före den väntande.
        assertEquals(id, model.s.currentLiveActivity?.id)
    }

    // Reservnotis

    @Test
    fun reserventasBortNarAktivitetenVisats() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        // Alarmet går kl. 18:00, och appen ser Live Updaten vid nästa planering.
        f.clock.set(sundayAt(18 * 60 + 1))
        f.activities.promote()
        apply(model)
        assertEquals(listOf("2026-11-12"), f.notifications.dates)
        assertTrue(model.s.handledPickup(homeKey, monday))
    }

    @Test
    fun reserventKommerInteTillbakaEfterAttAktivitetenSettsPagaende() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.clock.set(sundayAt(18 * 60 + 20))
        f.activities.promote()
        apply(model)
        // Användaren sveper bort den. Den har visats, och reserven kommer inte tillbaka.
        f.activities.setPhase(LiveActivityPhase.Dismissed, f.activities.ids.first())
        apply(model)
        assertNull(f.notifications.notification("2026-11-09"))
    }

    @Test
    fun reserventStarKvarNarAktivitetenForsvunnitIBakgrunden() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.activities.clearAll()
        apply(model, startingActivities = false)
        reserveKvar(f)
        assertFalse("notis- 2026-11-09" in f.log.all)
    }

    @Test
    fun reserventStarKvarNarLiveActivityStangsAv() = runTest {
        val f = fixture()
        val model = withReserve(f)
        apply(model, startingActivities = false)
        model.setLiveActivity(false)
        model.settleReminders()
        assertTrue(f.activities.ids.isEmpty())
        reserveKvar(f)
    }

    @Test
    fun reserventStarKvarNarAktivitetenForsvunnitOchStartenMisslyckas() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.activities.clearAll()
        f.activities.setFailing(true)
        apply(model)
        assertTrue(f.activities.ids.isEmpty())
        reserveKvar(f)
    }

    @Test
    fun reserventStarKvarNarErsattningenMisslyckasIForgrunden() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.activities.setFailing(true)
        apply(model)
        assertEquals(1, f.activities.ids.size)
        reserveKvar(f)
    }

    @Test
    fun ingenNyReservSkapasNarIngenVantar() = runTest {
        // Ordinarie tid har passerat och inget väntar: den som inte fick någon notis får ingen reserv heller.
        val f = fixture(now = sundayAt(18 * 60 + 10))
        f.activities.setFailing(true)
        apply(f.model())
        assertNull(f.notifications.notification("2026-11-09"))
        assertEquals(listOf("2026-11-12"), f.notifications.dates)
    }

    @Test
    fun avstangdaNotiserTarBortReserventAvenEfterOrdinarieTid() = runTest {
        val f = fixture()
        val model = withReserve(f)
        model.setNotifications(false, homeKey)
        model.settleReminders()
        assertTrue(f.notifications.dates.isEmpty())
    }

    @Test
    fun utstalldTarBortReserventAvenEfterOrdinarieTid() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.store.markPlacedOut(PlacedOut(homeKey, monday), day("2026-11-06"))
        apply(model)
        assertEquals(listOf("2026-11-12"), f.notifications.dates)
    }

    @Test
    fun avslutadUtanBevisStoppasOmstartMenInteReserven() = runTest {
        val f = fixture()
        val model = withReserve(f)
        // Alarmet har gått och Live Updaten svepts bort, men appen har aldrig sett den pågå.
        f.activities.setPhase(LiveActivityPhase.Dismissed, f.activities.ids.first())
        apply(model)
        assertTrue(f.store.shownActivities().isEmpty())
        assertEquals(listOf(PlacedOut(homeKey, monday)), f.store.endedActivities())
        // Ingen omstart för måndagen, och reserven står kvar.
        assertEquals(listOf(monday, thursday), f.activities.starts.map { it.pickupDate })
        reserveKvar(f)
        // Efter en omstart av appen är det fortfarande så.
        apply(f.model())
        assertTrue(f.store.shownActivities().isEmpty())
        reserveKvar(f)
    }

    @Test
    fun ersattAktivitetMarkerarInteTomningenSomVisadEfterOmstart() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.activities.keepsRemoved = true
        model.rename(homeKey, "Stugan")
        model.settleReminders()
        // Den nya visas direkt (starttiden har passerat), och den gamla ligger kvar som avslutad hos systemet.
        apply(f.model())
        assertEquals(listOf(PlacedOut(homeKey, monday)), f.store.shownActivities())
        f.activities.clearAll()
        f.store.clearShown()
        apply(f.model(), startingActivities = false)
        assertTrue(f.store.shownActivities().isEmpty())
    }

    @Test
    fun hemkortetNamnerReserventNarDenLiggerFramfor() = runTest {
        val f = fixture()
        val model = withReserve(f)
        f.activities.clearAll()
        apply(model, startingActivities = false)
        val home = model.home()
        val reserve = model.s.reserveNotificationDate(home, f.clock.now)
        assertEquals(sundayAt(18 * 60 + 45), reserve)
        // "Påminnelsen har passerat" gäller inte när en reserv ligger framför.
        assertNull(model.s.missedReminderText(home, f.clock.now))
        val s = model.s
        val content = HomeContent.make(
            s.addresses, s.schedules, s.settings, f.clock.now, remindersAllowed = true, liveActivity = null, liveActivitiesEnabled = true,
            liveActivityError = null, missedReminder = null, reserveAt = reserve,
        )
        assertEquals("Reservpåminnelse kl. 18:45", content.primary?.reminder?.detail)
    }

    @Test
    fun utstalltTarBortReserventVidNastaPlanering() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        f.store.markPlacedOut(PlacedOut(homeKey, monday), day("2026-11-06"))
        apply(model)
        assertEquals(listOf("2026-11-12"), f.notifications.dates)
        assertTrue("notis- 2026-11-09" in f.log.all)
    }

    @Test
    fun bastaLiveActivityUtanNotiserGerIngenNotis() = runTest {
        val f = fixture(homeNotifications = false)
        apply(f.model())
        assertEquals(listOf(monday), f.activities.starts.map { it.pickupDate })
        // Den andra adressen har notiser av, så ingen notis alls.
        assertTrue(f.notifications.dates.isEmpty())
    }

    @Test
    fun reserventasBortNarNotiserSlasAv() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        assertTrue(f.notifications.isFallback("2026-11-09"))
        model.setNotifications(false, homeKey)
        model.settleReminders()
        assertTrue(f.notifications.dates.isEmpty())
    }

    // Systemets val

    @Test
    fun avstangtISystemetBehallerValetOchNotisen() = runTest {
        val f = fixture(systemEnabled = false)
        val model = f.model()
        apply(model)
        assertFalse(model.s.liveActivitiesEnabled)
        assertTrue(model.s.settings.liveActivityOn)
        assertTrue(f.activities.starts.isEmpty())
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        // Avstängt i systemet: den vanliga notisen tillbaka på ordinarie tid.
        assertFalse(f.notifications.isFallback("2026-11-09"))
        assertEquals(sundayAt(18 * 60), f.notifications.notification("2026-11-09")?.fireDate)
        // Slås det på igen tas notisen över av Live Updaten.
        f.activities.enabled = true
        apply(model)
        assertTrue(model.s.liveActivitiesEnabled)
        assertEquals(listOf(monday), f.activities.starts.map { it.pickupDate })
        assertEquals(listOf("2026-11-09", "2026-11-12"), f.notifications.dates)
        assertTrue(f.notifications.isFallback("2026-11-09"))
    }

    @Test
    fun avstangtISystemetNarAktivitetVantarLaggerInNotisen() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        f.activities.enabled = false
        f.log.clear()
        apply(model)
        val log = f.log.all
        assertTrue(log.indexOf("notis+ 2026-11-09") in 0 until log.indexOfFirst { it.startsWith("remove") })
        assertTrue("2026-11-09" in f.notifications.dates)
        // Den vanliga notisen ersätter reserven, med samma identifierare.
        assertFalse(f.notifications.isFallback("2026-11-09"))
        assertEquals(sundayAt(18 * 60), f.notifications.notification("2026-11-09")?.fireDate)
    }

    @Test
    fun nekadeNotiserHindrarInteAktiviteten() = runTest {
        val f = fixture(notificationStatus = NotificationAuthorization.Denied)
        apply(f.model())
        assertEquals(listOf(monday), f.activities.starts.map { it.pickupDate })
        assertTrue(f.notifications.dates.isEmpty())
    }

    // Läsbarhet

    @Test
    fun olasbartSchemaTarInteBortAktiviteten() = runTest {
        val f = fixture()
        apply(f.model())
        val id = f.activities.ids.first()
        // Schemat går inte att läsa. Då finns inget att planera en ny påminnelse från, och Live Updaten får inte försvinna.
        f.store.removeSchedule(homeKey)
        apply(f.model())
        assertEquals(listOf(id), f.activities.ids)
    }

    @Test
    fun olasbaraInstallningarRorInteAktiviteter() = runTest {
        val f = fixture()
        apply(f.model())
        val id = f.activities.ids.first()
        File(f.dir, "settings.json").writeText("inte json")
        apply(f.model())
        assertEquals(listOf(id), f.activities.ids)
    }

    // Samma morgon

    @Test
    fun bytTillMorgonErsatterVantandeAktivitet() = runTest {
        val f = fixture()
        val model = f.model()
        apply(model)
        val evening = f.activities.activities.first()
        assertEquals(sundayAt(18 * 60), evening.start)
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, false))
        assertTrue(model.setLiveActivityTiming(ReminderTiming.SameMorning))
        model.settleReminders()
        assertFalse(evening.id in f.activities.ids)
        assertEquals(listOf(StockholmClock.dateOn(monday, 6 * 60)), f.activities.activities.map { it.start })
        assertEquals(listOf(monday), f.activities.activities.map { it.pickupDate })
    }

    @Test
    fun bytAvAktivitetensValGlommerStoppade() = runTest {
        val f = fixture()
        f.store.markEnded(listOf(PlacedOut(homeKey, monday)), day("2026-11-08"))
        val model = f.model()
        assertTrue(f.store.endedActivities().isNotEmpty())
        assertTrue(model.setLiveActivityTiming(ReminderTiming.SameMorning))
        assertTrue(f.store.endedActivities().isEmpty())
    }

    @Test
    fun notisensTidGlommerInteStoppade() = runTest {
        // Live Update har en egen tid, så en ändrad notistid är inget nytt val för den.
        val f = fixture()
        f.store.setSettings(ReminderSettings(eveningOn = true, morningOn = true, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true))
        f.store.markEnded(listOf(PlacedOut(homeKey, monday)), day("2026-11-08"))
        val model = f.model()
        assertTrue(model.setReminderMinutes(1140, ReminderTiming.EveningBefore))
        assertTrue(model.setReminderMinutes(420, ReminderTiming.SameMorning))
        assertTrue(f.store.endedActivities().isNotEmpty())
        assertEquals(360, model.s.settings.liveActivityStartMinutes)
    }

    @Test
    fun aktivitetensTidGlommerStoppade() = runTest {
        val f = fixture()
        f.store.setSettings(ReminderSettings(liveActivityOn = true))
        f.store.markEnded(listOf(PlacedOut(homeKey, monday)), day("2026-11-08"))
        val model = f.model()
        // 07:00 går inte kvällen före, och inget ändras.
        assertFalse(model.setLiveActivityMinutes(420))
        assertTrue(f.store.endedActivities().isNotEmpty())
        assertTrue(model.setLiveActivityMinutes(1260))
        assertEquals(1260, model.s.settings.liveActivityMinutes)
        assertEquals(1080, model.s.settings.reminderMinutes)
        assertTrue(f.store.endedActivities().isEmpty())
    }

    @Test
    fun bytAvValFarNotisensTid() = runTest {
        val f = fixture()
        f.store.setSettings(ReminderSettings(morningMinutes = 420, liveActivityMinutes = 1260, liveActivityOn = true))
        val model = f.model()
        assertTrue(model.setLiveActivityTiming(ReminderTiming.SameMorning))
        assertEquals(420, model.s.settings.liveActivityStartMinutes)
    }

    @Test
    fun sammaTidIgenGlommerInteStoppade() = runTest {
        val f = fixture()
        f.store.setSettings(ReminderSettings(eveningOn = true, morningOn = false, reminderMinutes = 1080, liveActivityTiming = ReminderTiming.EveningBefore, liveActivityOn = true))
        f.store.markEnded(listOf(PlacedOut(homeKey, monday)), day("2026-11-08"))
        val model = f.model()
        assertTrue(model.setLiveActivityMinutes(1080))
        assertTrue(f.store.endedActivities().isNotEmpty())
    }

    @Test
    fun reglageGlommerInteStoppade() = runTest {
        val f = fixture()
        f.store.markEnded(listOf(PlacedOut(homeKey, monday)), day("2026-11-08"))
        val model = f.model()
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, false))
        assertTrue(f.store.endedActivities().isNotEmpty())
    }
}
