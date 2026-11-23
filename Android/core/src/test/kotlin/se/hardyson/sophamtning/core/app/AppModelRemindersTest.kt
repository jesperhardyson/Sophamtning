package se.hardyson.sophamtning.core.app

import java.io.File
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.DisabledLiveActivities
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationDiff
import se.hardyson.sophamtning.core.reminders.PermissionResult
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.reminders.event
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.fixtureResponse
import se.hardyson.sophamtning.core.storage.tempDir

private class FixedApi(private val response: AddressResponse) : UnusedApi() {
    override suspend fun address(url: String) = response
}

private val key = AddressKey("orebro", "1")

/** Fredag 6 november 2026 12:00 svensk tid. Schemat i fixturen har hämtningar från 11 november. */
private val now = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)

private fun response(events: List<String>? = null): AddressResponse {
    val base = fixtureResponse()
    if (events == null) return base
    return base.copy(next = emptyList(), summary = "", events = events.map { event(it, listOf("rest")) }, bins = emptyList())
}

private fun savedForReminders() = SavedAddress(
    key = key, url = "https://sopor.hardyson.se/api/v1/adress/orebro/1", street = "Storgatan 1", locality = "Örebro", kommun = "Örebro",
    detail = null, selection = "address", displayName = "Hemma", isPrimary = true, addedAt = Instant.EPOCH,
)

private val AppModel.s: AppState get() = state.value

private fun TestScope.model(scheduler: FakeNotifications, dir: File, at: Instant = now, events: List<String>? = null) =
    AppModel(FixedApi(response(events)), LocalStore(dir), scheduler, DisabledLiveActivities, { at }, backgroundScope)

private suspend fun TestScope.makeModel(scheduler: FakeNotifications, dir: File): AppModel {
    val model = model(scheduler, dir)
    model.add(hit("1"))
    model.refreshAll(manual = false)
    model.settleReminders()
    return model
}

private fun File.garbage() = writeText("skräp")

private fun hasDamaged(dir: File) = dir.list()!!.any { it.contains(".skadad-") }

// Från AppModelRemindersTests på iOS.
class AppModelRemindersTest {
    @Test
    fun inteSchemalagtForstNarNotisenSlasPa() = runTest {
        val scheduler = FakeNotifications(NotificationAuthorization.NotDetermined, foreign = true)
        val model = makeModel(scheduler, tempDir())
        assertEquals(0, scheduler.requests)
        assertTrue(scheduler.planned.isEmpty())
        assertFalse(model.s.addresses[0].notificationsOn)
    }

    @Test
    fun paslagFragarSchemalaggerOchStangerAvTarBortAlltIgen() = runTest {
        val scheduler = FakeNotifications(NotificationAuthorization.NotDetermined, foreign = true)
        val model = makeModel(scheduler, tempDir())

        val result = model.setNotifications(true, key)
        model.settleReminders()
        assertEquals(PermissionResult.Granted, result)
        assertEquals(1, scheduler.requests)
        assertTrue(model.s.addresses[0].notificationsOn)
        assertTrue(scheduler.planned.isNotEmpty())
        assertTrue(scheduler.planned.all { NotificationDiff.isOwn(it.identifier) })

        val off = model.setNotifications(false, key)
        model.settleReminders()
        assertEquals(PermissionResult.Granted, off)
        assertTrue(scheduler.planned.isEmpty())
        assertFalse(model.s.addresses[0].notificationsOn)
    }

    @Test
    fun nekatTillstandLamnarReglagetAvOchIngetSchemalaggs() = runTest {
        val scheduler = FakeNotifications(NotificationAuthorization.NotDetermined, answer = false, foreign = true)
        val model = makeModel(scheduler, tempDir())

        val result = model.setNotifications(true, key)
        model.settleReminders()
        assertEquals(PermissionResult.Denied, result)
        assertFalse(model.s.addresses[0].notificationsOn)
        assertEquals(NotificationAuthorization.Denied, model.s.notificationAuthorization)
        assertTrue(scheduler.planned.isEmpty())
        // Ett nytt försök frågar inte igen, systemet svarar redan nej.
        assertEquals(PermissionResult.Denied, model.setNotifications(true, key))
        assertEquals(1, scheduler.requests)
    }

    @Test
    fun tillstandSomDragitsTillbakaBehallerValetOchNotiserna() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        assertTrue(before.isNotEmpty())

        scheduler.status = NotificationAuthorization.Denied
        model.applyReminders()
        model.settleReminders()
        assertEquals(NotificationAuthorization.Denied, model.s.notificationAuthorization)
        // Valet är kvar, men det visade läget är av.
        assertTrue(model.s.addresses[0].notificationsOn)
        assertFalse(model.s.remindersOn(model.s.addresses[0]))
        assertTrue(LocalStore(dir).addresses()[0].notificationsOn)
        assertEquals(before, scheduler.planned)

        // Kommer tillståndet tillbaka planeras notiserna igen, även om de försvunnit under tiden.
        scheduler.cancel(before.map { it.identifier })
        scheduler.status = NotificationAuthorization.Authorized
        model.applyReminders()
        model.settleReminders()
        assertEquals(before, scheduler.planned)
        assertTrue(model.s.remindersOn(model.s.addresses[0]))
    }

    @Test
    fun valAvMedOavgjortTillstandVisasSomAvOchFragarVidPaslag() = runTest {
        val dir = tempDir()
        // Valet är sparat som på, men systemet har inte fått frågan.
        LocalStore(dir).setAddresses(listOf(savedForReminders().copy(notificationsOn = true)))
        val scheduler = FakeNotifications(NotificationAuthorization.NotDetermined, foreign = true)
        val model = model(scheduler, dir)
        model.applyReminders()
        model.settleReminders()
        assertEquals(NotificationAuthorization.NotDetermined, model.s.notificationAuthorization)
        assertFalse(model.s.remindersOn(model.s.addresses[0]))
        assertTrue(scheduler.planned.isEmpty())
        assertTrue(scheduler.cancelled.isEmpty())

        assertEquals(PermissionResult.Granted, model.setNotifications(true, key))
        assertEquals(1, scheduler.requests)
        assertTrue(model.s.remindersOn(model.s.addresses[0]))
    }

    @Test
    fun framlingsnotiserRorsAldrig() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        model.setNotifications(false, key)
        model.settleReminders()
        assertTrue(scheduler.planned.isEmpty())
        assertFalse(scheduler.foreignId in scheduler.cancelled)
        model.remove(key)
        model.settleReminders()
        assertFalse(scheduler.foreignId in scheduler.cancelled)
    }

    @Test
    fun omkorningUtanAndringGerVarkenAddEllerCancel() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        scheduler.resetCalls()
        model.applyReminders()
        model.settleReminders()
        model.applyReminders()
        model.settleReminders()
        assertEquals(0, scheduler.scheduleCalls)
        assertTrue(scheduler.cancelled.isEmpty())
    }

    @Test
    fun ersattNotisTasInteBortForstOchNyaFelenSynsOchForsoks() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        scheduler.resetCalls()

        // Den nya tiden går inte att lägga in: den gamla notisen står kvar, och felet visas.
        scheduler.failAll(true, before.map { it.identifier })
        assertTrue(model.setReminderMinutes(19 * 60, ReminderTiming.EveningBefore))
        model.settleReminders()
        assertTrue(scheduler.cancelled.isEmpty())
        assertEquals(before, scheduler.planned)
        assertNotNull(model.s.reminderError)

        scheduler.failAll(false, emptyList())
        model.applyReminders()
        model.settleReminders()
        assertNull(model.s.reminderError)
        assertEquals(before.map { it.identifier }, scheduler.planned.map { it.identifier })
        assertTrue(scheduler.planned.all { it.fireDate.atZone(StockholmClock.zone).hour == 19 })
    }

    @Test
    fun skadadSchemafilTarInteBortNotiserMedValetPa() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        assertTrue(before.size > 1)

        // Appen startas om och schemafilen går inte att läsa.
        File(dir, "schedules").listFiles()!!.forEach { it.garbage() }
        val restarted = model(scheduler, dir)
        restarted.applyReminders()
        restarted.settleReminders()
        assertEquals(before, scheduler.planned)
        assertTrue(scheduler.cancelled.isEmpty())
        assertTrue(restarted.s.addresses[0].notificationsOn)
    }

    @Test
    fun skadadAdressfilTarInteBortNotiserOchSkrivsInteOver() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        val file = File(dir, "addresses.json")
        val good = file.readBytes()
        file.garbage()

        val restarted = model(scheduler, dir)
        assertTrue(restarted.s.addresses.isEmpty())
        restarted.applyReminders()
        restarted.settleReminders()
        assertEquals(before, scheduler.planned)
        assertTrue(scheduler.cancelled.isEmpty())
        // Att lägga till en adress skriver inte över filen.
        assertFalse(restarted.add(hit("1")))
        assertNotNull(restarted.s.lastStorageError)
        assertEquals("skräp", file.readText())

        // När filen går att läsa igen läses den om, och notiserna är kvar.
        file.writeBytes(good)
        restarted.applyReminders()
        restarted.settleReminders()
        assertEquals(1, restarted.s.addresses.size)
        assertTrue(restarted.s.addresses[0].notificationsOn)
        assertTrue(scheduler.cancelled.isEmpty())
    }

    @Test
    fun skadadInstallningsfilTarInteBortNotiserOchSkrivsInteOver() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        assertTrue(model.setReminderMinutes(19 * 60, ReminderTiming.EveningBefore))
        model.settleReminders()
        val before = scheduler.planned
        val file = File(dir, "settings.json")
        val good = file.readBytes()
        file.garbage()

        val restarted = model(scheduler, dir)
        restarted.applyReminders()
        restarted.settleReminders()
        assertEquals(before, scheduler.planned)
        assertFalse(restarted.setReminderMinutes(20 * 60, ReminderTiming.EveningBefore))
        assertEquals("skräp", file.readText())

        file.writeBytes(good)
        restarted.applyReminders()
        restarted.settleReminders()
        assertEquals(19 * 60, restarted.s.settings.reminderMinutes)
        assertEquals(before, scheduler.planned)
    }

    @Test
    fun sparfelVidPaslagOchOkandAdressGerFailed() = runTest {
        val dir = tempDir()
        val model = makeModel(FakeNotifications(foreign = true), dir)
        assertEquals(PermissionResult.Failed, model.setNotifications(true, AddressKey("x", "y")))
        assertEquals(PermissionResult.Failed, model.setNotifications(false, AddressKey("x", "y")))

        val failing = model(FakeNotifications(foreign = true), dir)
        // Katalogen blir en fil efter att adressen lästs in, så att sparandet misslyckas.
        dir.deleteRecursively()
        dir.writeBytes(ByteArray(0))
        assertEquals(PermissionResult.Failed, failing.setNotifications(true, key))
        assertNotNull(failing.s.lastStorageError)
        assertFalse(failing.s.addresses[0].notificationsOn)
    }

    @Test
    fun ersattAdressBehallerNamnHuvudadressOchNotisval() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        assertTrue(scheduler.planned.isNotEmpty())

        model.add(hit("2").copy(street = "Ny gata 1", url = hit("1").url))
        val new = AddressKey("orebro", "2")
        assertTrue(model.replace(key, new))
        model.settleReminders()
        assertEquals(listOf(new), model.s.addresses.map { it.key })
        assertEquals("Hemma", model.s.addresses[0].displayName)
        assertTrue(model.s.addresses[0].isPrimary)
        assertTrue(model.s.addresses[0].notificationsOn)
        // Den gamla adressens notiser är borta, och den nya har inget schema än.
        assertTrue(scheduler.planned.isEmpty())
        assertFalse(model.replace(key, new))
    }

    @Test
    fun missadPaminnelseVisasBaraMedNotiserPa() = runTest {
        // Fredag 6 nov 19:00, och schemat har tömning lördag 7 nov.
        val late = StockholmClock.dateOn(day("2026-11-06"), 19 * 60)
        val scheduler = FakeNotifications(foreign = true)
        val model = model(scheduler, tempDir(), at = late, events = listOf("2026-11-07"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.settleReminders()
        assertNull(model.s.missedReminderText(late))
        model.setNotifications(true, key)
        model.settleReminders()
        assertEquals("Tömning i morgon. Påminnelsen för i kväll har redan passerat.", model.s.missedReminderText(late))
        // Passerad tid skickar ingen ersättningsnotis.
        assertFalse(scheduler.planned.any { it.pickupDate == day("2026-11-07") })
    }

    @Test
    fun andradTidErsatterNotiserna() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        assertTrue(before.isNotEmpty())

        assertTrue(model.setReminderMinutes(20 * 60 + 15, ReminderTiming.EveningBefore))
        model.settleReminders()
        val after = scheduler.planned
        assertEquals(before.map { it.identifier }, after.map { it.identifier })
        assertTrue(before.zip(after).all { (b, a) -> a.fireDate.epochSecond - b.fireDate.epochSecond == 2L * 3600 + 15 * 60 })
        assertEquals(20 * 60 + 15, LocalStore(dir).settings().reminderMinutes)
    }

    @Test
    fun ogiltigTidSparasInte() = runTest {
        val model = makeModel(FakeNotifications(foreign = true), tempDir())
        assertFalse(model.setReminderMinutes(14 * 60 + 45, ReminderTiming.EveningBefore))
        assertFalse(model.setReminderMinutes(23 * 60 + 15, ReminderTiming.EveningBefore))
        assertFalse(model.setReminderMinutes(17 * 60 + 5, ReminderTiming.EveningBefore))
        assertEquals(1080, model.s.settings.reminderMinutes)
    }

    @Test
    fun sparfelPaTidenLamnarVardetOchVisarFel() = runTest {
        val blocked = File(tempDir(), "blockerad").apply { writeBytes(ByteArray(0)) }
        val model = model(FakeNotifications(foreign = true), blocked)
        assertFalse(model.setReminderMinutes(19 * 60, ReminderTiming.EveningBefore))
        assertEquals(1080, model.s.settings.reminderMinutes)
        assertNotNull(model.s.lastStorageError)
    }

    @Test
    fun valetForLiveActivitySparasOchNotisenStarKvarUtanSystemetsAktiviteter() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned

        model.setLiveActivity(true)
        model.settleReminders()
        assertTrue(model.s.settings.liveActivityOn)
        assertTrue(LocalStore(dir).settings().liveActivityOn)
        // Här finns inga Live Updates hos systemet, så notiserna står kvar.
        assertEquals(before, scheduler.planned)
    }

    @Test
    fun nyttNamnUppdaterarVantandeNotiser() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        assertTrue(scheduler.planned.all { it.body.startsWith("Hemma:") })

        assertTrue(model.rename(key, " Stugan "))
        model.settleReminders()
        assertEquals("Stugan", model.s.addresses[0].displayName)
        assertTrue(scheduler.planned.all { it.body.startsWith("Stugan:") })
        assertFalse(model.rename(key, "   "))
        assertEquals("Stugan", model.s.addresses[0].displayName)
    }

    @Test
    fun borttagenAdressTarBortSinaNotiser() = runTest {
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, tempDir())
        model.setNotifications(true, key)
        model.settleReminders()
        assertTrue(scheduler.planned.isNotEmpty())

        model.remove(key)
        model.settleReminders()
        assertTrue(scheduler.planned.isEmpty())
    }

    @Test
    fun nyHuvudadressSparas() = runTest {
        val dir = tempDir()
        val model = makeModel(FakeNotifications(foreign = true), dir)
        model.add(hit("2"))
        val other = AddressKey("orebro", "2")
        model.setPrimary(other)
        assertEquals(other, model.s.addresses.first { it.isPrimary }.key)
        assertEquals(other, LocalStore(dir).addresses().first { it.isPrimary }.key)
    }

    @Test
    fun trycketMedIndragetTillstandRorInteValetOchNotiserna() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        assertTrue(before.size > 1)

        scheduler.status = NotificationAuthorization.Denied
        model.applyReminders()
        model.settleReminders()
        // Ett tryck på reglaget medan tillståndet är indraget ändrar ingenting, och ingen ny fråga ställs.
        assertEquals(PermissionResult.Denied, model.setNotifications(true, key))
        model.settleReminders()
        assertEquals(0, scheduler.requests)
        assertTrue(model.s.addresses[0].notificationsOn)
        assertTrue(LocalStore(dir).addresses()[0].notificationsOn)
        assertEquals(before, scheduler.planned)

        scheduler.status = NotificationAuthorization.Authorized
        model.applyReminders()
        model.settleReminders()
        assertEquals(before, scheduler.planned)
        assertTrue(scheduler.cancelled.isEmpty())
        assertTrue(model.s.remindersOn(model.s.addresses[0]))
    }

    @Test
    fun skadadAdressfilGerEgetLageDarForsokIgenLaserOm() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        val file = File(dir, "addresses.json")
        val good = file.readBytes()
        file.garbage()

        val restarted = model(scheduler, dir)
        assertEquals(StorageProblem.AddressesUnreadable, restarted.s.storageProblem)
        restarted.retryStorage()
        restarted.settleReminders()
        assertEquals(StorageProblem.AddressesUnreadable, restarted.s.storageProblem)
        assertEquals("skräp", file.readText())

        file.writeBytes(good)
        restarted.retryStorage()
        restarted.settleReminders()
        assertNull(restarted.s.storageProblem)
        assertEquals(1, restarted.s.addresses.size)
        assertEquals(before, scheduler.planned)
    }

    @Test
    fun borjaOmFlyttarSkadadFilTarBortEgnaNotiserOchLaterAnvandarenLaggaTill() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        assertTrue(scheduler.planned.isNotEmpty())
        val file = File(dir, "addresses.json")
        file.garbage()

        val restarted = model(scheduler, dir)
        assertEquals(StorageProblem.AddressesUnreadable, restarted.s.storageProblem)
        restarted.startOver()
        restarted.settleReminders()
        assertNull(restarted.s.storageProblem)
        assertTrue(restarted.s.addresses.isEmpty())
        // Den skadade filen finns kvar åt sidan, och den ursprungliga platsen är ledig.
        val aside = dir.list()!!.first { it.startsWith("addresses.json.skadad-") }
        assertEquals("skräp", File(dir, aside).readText())
        assertFalse(file.exists())
        // Appens notiser är borta, främmande notiser rördes inte.
        assertTrue(scheduler.planned.isEmpty())
        assertFalse(scheduler.foreignId in scheduler.cancelled)
        // Nu går det att lägga till en adress igen.
        assertTrue(restarted.add(hit("1")))
        assertEquals(1, restarted.s.addresses.size)
    }

    @Test
    fun borjaOmMedSkadadeInstallningarAnvanderStandardOchBehallerAdresserna() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        assertTrue(model.setReminderMinutes(19 * 60, ReminderTiming.EveningBefore))
        model.setNotifications(true, key)
        model.settleReminders()
        File(dir, "settings.json").garbage()

        val restarted = model(scheduler, dir)
        assertEquals(StorageProblem.SettingsUnreadable, restarted.s.storageProblem)
        restarted.startOver()
        restarted.settleReminders()
        assertNull(restarted.s.storageProblem)
        assertEquals(ReminderSettings(), restarted.s.settings)
        assertEquals(1, restarted.s.addresses.size)
        assertTrue(dir.list()!!.any { it.startsWith("settings.json.skadad-") })
        assertTrue(restarted.setReminderMinutes(20 * 60, ReminderTiming.EveningBefore))
    }

    @Test
    fun borjaOmFlyttarInteEnFilSomRepareratsSedanFlaggan() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        val file = File(dir, "addresses.json")
        val good = file.readBytes()
        file.garbage()

        val restarted = model(scheduler, dir)
        assertEquals(StorageProblem.AddressesUnreadable, restarted.s.storageProblem)
        // Filen blir läsbar igen, men appen har inte läst om den. Börja om läser om först och flyttar inget.
        file.writeBytes(good)
        restarted.startOver()
        restarted.settleReminders()
        assertNull(restarted.s.storageProblem)
        assertEquals(1, restarted.s.addresses.size)
        assertTrue(good.contentEquals(file.readBytes()))
        assertFalse(hasDamaged(dir))
        assertEquals(before, scheduler.planned)
        assertTrue(scheduler.cancelled.isEmpty())
    }

    @Test
    fun tillfalligtOtillgangligFilFlyttasAldrigAvBorjaOm() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(foreign = true)
        val model = makeModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = scheduler.planned
        val file = File(dir, "addresses.json")
        val good = file.readBytes()
        // Filen finns och är hel men går inte att läsa just nu.
        file.setReadable(false, false)
        try {
            val restarted = model(scheduler, dir)
            assertEquals(StorageProblem.AddressesUnavailable, restarted.s.storageProblem)
            restarted.startOver()
            restarted.settleReminders()
            assertEquals(StorageProblem.AddressesUnavailable, restarted.s.storageProblem)
            assertTrue(file.exists())
            assertFalse(hasDamaged(dir))
            assertEquals(before, scheduler.planned)
            assertTrue(scheduler.cancelled.isEmpty())

            // Efter upplåsning går det att läsa, och allt är kvar.
            file.setReadable(true, false)
            restarted.retryStorage()
            restarted.settleReminders()
            assertNull(restarted.s.storageProblem)
            assertEquals(1, restarted.s.addresses.size)
            assertTrue(good.contentEquals(file.readBytes()))
        } finally {
            file.setReadable(true, false)
        }
    }

    // Förslaget om påminnelse

    @Test
    fun forslagetVisasEfterForstaAdressen() = runTest {
        val model = makeModel(FakeNotifications(NotificationAuthorization.NotDetermined), tempDir())
        assertTrue(model.s.showsReminderOffer(now))
    }

    @Test
    fun forslagetVisasInteUtanAdress() = runTest {
        val model = model(FakeNotifications(NotificationAuthorization.NotDetermined), tempDir())
        assertFalse(model.s.showsReminderOffer(now))
    }

    @Test
    fun forslagetForsvinnerNarPaminnelsenSlasPaOchKommerInteTillbaka() = runTest {
        val model = makeModel(FakeNotifications(NotificationAuthorization.NotDetermined), tempDir())
        assertEquals(PermissionResult.Granted, model.setNotifications(true, key))
        assertFalse(model.s.showsReminderOffer(now))
        model.setNotifications(false, key)
        assertFalse(model.s.showsReminderOffer(now), "Förslaget visas bara en gång")
    }

    @Test
    fun inteNuDoljerForslagetAvenEfterOmstart() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications(NotificationAuthorization.NotDetermined)
        val model = makeModel(scheduler, dir)
        model.dismissReminderOffer()
        assertFalse(model.s.showsReminderOffer(now))
        assertEquals(0, scheduler.requests, "Inte nu frågar aldrig om tillstånd")
        assertFalse(model(scheduler, dir).s.showsReminderOffer(now))
    }

    @Test
    fun forslagetVisasInteNarNotiserArNekade() = runTest {
        val model = makeModel(FakeNotifications(NotificationAuthorization.Denied), tempDir())
        assertFalse(model.s.showsReminderOffer(now))
    }

    @Test
    fun forslagetVisasInteUtanKommandeHamtning() = runTest {
        // Huvudkortet har bara reglaget för påminnelsen när en hämtning kommer.
        val model = model(FakeNotifications(NotificationAuthorization.NotDetermined), tempDir(), events = listOf("2026-11-02"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.settleReminders()
        assertFalse(model.s.showsReminderOffer(now))
    }

    @Test
    fun paslagenPaminnelseGerIngetFelNarForslagetInteKanSparas() = runTest {
        // Påminnelsen är sparad även om inställningsfilen inte går att skriva. Då ska inget fel säga att inget ändrats.
        val dir = tempDir()
        val model = makeModel(FakeNotifications(NotificationAuthorization.NotDetermined), dir)
        File(dir, "settings.json").delete()
        File(dir, "settings.json").mkdirs()
        assertEquals(PermissionResult.Granted, model.setNotifications(true, key))
        assertTrue(model.s.addresses[0].notificationsOn)
        assertNull(model.s.lastStorageError)
        assertFalse(model.s.showsReminderOffer(now))
    }

    @Test
    fun missadMorgonGallerDagensTomning() = runTest {
        // Lördag 7 nov 07:00 med samma morgon 06:00, och schemat har tömning lördag 7 nov.
        val morning = StockholmClock.dateOn(day("2026-11-07"), 7 * 60)
        val dir = tempDir()
        LocalStore(dir).setSettings(ReminderSettings(eveningOn = false, morningOn = true, morningMinutes = 360, liveActivityTiming = ReminderTiming.SameMorning))
        val scheduler = FakeNotifications()
        val model = model(scheduler, dir, at = morning, events = listOf("2026-11-07"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.setNotifications(true, key)
        model.settleReminders()
        assertEquals("Tömning i dag. Påminnelsen för i morse har redan passerat.", model.s.missedReminderText(morning))
        assertFalse(scheduler.planned.any { it.pickupDate == day("2026-11-07") })
    }

    @Test
    fun missadGallerSenasteValet() = runTest {
        // Tisdag 10 nov 19:00 med båda valen på, och schemat har tömning onsdag 11 nov. Kvällens 18:00 har passerat, men morgonen är senast.
        val evening = StockholmClock.dateOn(day("2026-11-10"), 19 * 60)
        val dir = tempDir()
        LocalStore(dir).setSettings(ReminderSettings(eveningOn = true, morningOn = true))
        val model = model(FakeNotifications(), dir, at = evening, events = listOf("2026-11-11"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.setNotifications(true, key)
        model.settleReminders()
        assertNull(model.s.missedReminderText(evening))
    }

    // Kvällen före eller samma morgon

    private suspend fun TestScope.wednesdayModel(scheduler: FakeNotifications, dir: File): AppModel {
        val model = model(scheduler, dir, at = StockholmClock.dateOn(day("2026-11-10"), 12 * 60), events = listOf("2026-11-11"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.settleReminders()
        return model
    }

    @Test
    fun bytTillMorgonFlyttarNotisen() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications()
        val model = wednesdayModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        assertEquals(listOf(StockholmClock.dateOn(day("2026-11-10"), 18 * 60)), scheduler.planned.map { it.fireDate })
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, false))
        model.settleReminders()
        assertEquals(listOf(StockholmClock.dateOn(day("2026-11-11"), 6 * 60)), scheduler.planned.map { it.fireDate })
        assertTrue(LocalStore(dir).settings().morningOn)
    }

    @Test
    fun tidernaArOberoendeAvVarandra() = runTest {
        val model = wednesdayModel(FakeNotifications(), tempDir())
        assertTrue(model.setReminderMinutes(20 * 60, ReminderTiming.EveningBefore))
        assertTrue(model.setReminderMinutes(7 * 60, ReminderTiming.SameMorning))
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, false))
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, true))
        assertEquals(20 * 60, model.s.settings.minutes(ReminderTiming.EveningBefore))
        assertEquals(7 * 60, model.s.settings.morningMinutes)
    }

    @Test
    fun tidenKontrollerasMotValet() = runTest {
        val model = wednesdayModel(FakeNotifications(), tempDir())
        assertFalse(model.setReminderMinutes(6 * 60, ReminderTiming.EveningBefore))
        assertFalse(model.setReminderMinutes(18 * 60, ReminderTiming.SameMorning))
        assertEquals(1080, model.s.settings.reminderMinutes)
        assertEquals(360, model.s.settings.morningMinutes)
    }

    // Två påminnelser

    @Test
    fun sistaValetGarInteAttStangaAv() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications()
        val model = wednesdayModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        val before = model.s.settings

        assertFalse(model.setReminder(ReminderTiming.EveningBefore, false))
        assertEquals(before, model.s.settings)
        assertEquals(before, LocalStore(dir).settings())

        // Med båda på går det, och kvällens notis tas bort vid nästa planering.
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        model.settleReminders()
        assertEquals(2, scheduler.planned.size)
        assertTrue(model.setReminder(ReminderTiming.EveningBefore, false))
        model.settleReminders()
        assertEquals(listOf(StockholmClock.dateOn(day("2026-11-11"), 6 * 60)), scheduler.planned.map { it.fireDate })
        assertFalse(model.s.settings.eveningOn)
        // Nu är morgonen det sista valet.
        assertFalse(model.setReminder(ReminderTiming.SameMorning, false))
        assertTrue(model.s.settings.morningOn)
    }

    @Test
    fun morgonSlasPa() = runTest {
        val dir = tempDir()
        val scheduler = FakeNotifications()
        val model = wednesdayModel(scheduler, dir)
        model.setNotifications(true, key)
        model.settleReminders()
        assertEquals(listOf(StockholmClock.dateOn(day("2026-11-10"), 18 * 60)), scheduler.planned.map { it.fireDate })

        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        model.settleReminders()
        assertEquals(
            setOf(StockholmClock.dateOn(day("2026-11-10"), 18 * 60), StockholmClock.dateOn(day("2026-11-11"), 6 * 60)),
            scheduler.planned.map { it.fireDate }.toSet(),
        )
        assertTrue(LocalStore(dir).settings().morningOn)
    }

    @Test
    fun morgonSlasPaUtanNotiserSchemalagger() = runTest {
        val scheduler = FakeNotifications()
        val model = wednesdayModel(scheduler, tempDir())
        assertTrue(model.setReminder(ReminderTiming.SameMorning, true))
        model.settleReminders()
        assertTrue(scheduler.planned.isEmpty())
        assertEquals(0, scheduler.requests)
    }

    @Test
    fun tidForValet() = runTest {
        val model = wednesdayModel(FakeNotifications(), tempDir())
        assertTrue(model.setReminderMinutes(420, ReminderTiming.SameMorning))
        assertEquals(420, model.s.settings.morningMinutes)
        assertEquals(1080, model.s.settings.reminderMinutes)
        assertFalse(model.setReminderMinutes(420, ReminderTiming.EveningBefore))
        assertFalse(model.setReminderMinutes(18 * 60, ReminderTiming.SameMorning))
        assertEquals(1080, model.s.settings.reminderMinutes)
        assertEquals(420, model.s.settings.morningMinutes)
    }

    @Test
    fun liveActivityValetSparas() = runTest {
        val dir = tempDir()
        val model = wednesdayModel(FakeNotifications(), dir)
        assertTrue(model.setLiveActivityTiming(ReminderTiming.EveningBefore))
        assertTrue(model.setLiveActivityTiming(ReminderTiming.SameMorning))
        assertEquals(ReminderTiming.SameMorning, model.s.settings.liveActivityTiming)
        assertEquals(ReminderTiming.SameMorning, LocalStore(dir).settings().liveActivityTiming)
    }

    @Test
    fun lagringsfelVidReglageOchValBehallerInstallningen() = runTest {
        val blocked = File(tempDir(), "blockerad").apply { writeBytes(ByteArray(0)) }
        val model = model(FakeNotifications(), blocked)
        assertFalse(model.setReminder(ReminderTiming.SameMorning, true))
        assertFalse(model.setLiveActivityTiming(ReminderTiming.SameMorning))
        assertFalse(model.s.settings.morningOn)
        assertEquals(ReminderTiming.EveningBefore, model.s.settings.liveActivityTiming)
        assertNotNull(model.s.lastStorageError)
    }

    @Test
    fun uppgraderingFranEttValByterGammalNotisMotMorgonNotisen() = runTest {
        val dir = tempDir()
        // Fil sparad av en äldre version, med det enda valet "timing", och en väntande notis med det gamla id:t utan ändelse.
        File(dir, "settings.json").writeText("""{"timing":"sameMorning","reminderMinutes":1080,"morningMinutes":360,"liveActivityOn":false}""")
        val monday = day("2026-11-09")
        val sixAM = StockholmClock.dateOn(monday, 6 * 60)
        val oldId = "${key.fileName}-${monday.iso}"
        val scheduler = FakeNotifications()
        scheduler.schedule(listOf(PlannedNotification(oldId, sixAM, "Ställ ut kärlen", "Gammal", key, monday)))

        val model = model(scheduler, dir, events = listOf("2026-11-09"))
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.setNotifications(true, key)
        model.settleReminders()

        assertEquals(listOf(ReminderTiming.SameMorning), model.s.settings.enabledTimings)
        // Exakt en notis för tömningen: den nya med -morgon, kl. 06:00. Den gamla är borta.
        val forMonday = scheduler.planned.filter { it.pickupDate == monday }
        assertEquals(listOf(PlannedNotification.identifier(key, monday, ReminderTiming.SameMorning)), forMonday.map { it.identifier })
        assertEquals(sixAM, forMonday.first().fireDate)
        assertFalse(scheduler.planned.any { it.identifier == oldId })
    }

    @Test
    fun kvarlamnadNotisKallasInteReservUtanLiveActivity() = runTest {
        val sunday = day("2026-11-08")
        val clock = TestClock(StockholmClock.dateOn(sunday, 12 * 60))
        val scheduler = FakeNotifications()
        val model = AppModel(FixedApi(response(listOf("2026-11-09"))), LocalStore(tempDir()), scheduler, DisabledLiveActivities, { clock.now }, backgroundScope)
        model.add(hit("1"))
        model.refreshAll(manual = false)
        model.setNotifications(true, key)
        model.settleReminders()
        assertEquals(listOf(StockholmClock.dateOn(sunday, 18 * 60)), scheduler.planned.map { it.fireDate })

        // Kvällstiden flyttas till 17:00 klockan 17:30: den väntande notisen 18:00 står kvar, men är ingen reserv.
        clock.set(StockholmClock.dateOn(sunday, 17 * 60 + 30))
        assertTrue(model.setReminderMinutes(17 * 60, ReminderTiming.EveningBefore))
        model.settleReminders()
        assertNull(model.s.reserveNotificationDate(model.s.addresses[0], clock.now))
    }
}
