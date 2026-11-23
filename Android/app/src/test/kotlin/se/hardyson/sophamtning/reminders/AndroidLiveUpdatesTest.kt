package se.hardyson.sophamtning.reminders

import android.Manifest
import android.app.Notification
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.placedout.PlacedOutAction
import se.hardyson.sophamtning.core.reminders.ActivityFraction
import se.hardyson.sophamtning.core.reminders.LiveActivityPhase
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.PlannedLiveActivity
import se.hardyson.sophamtning.core.reminders.alertBody
import se.hardyson.sophamtning.core.reminders.compactDate
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.TestClock
import se.hardyson.sophamtning.ui.day
import se.hardyson.sophamtning.ui.testHit

private val content = PickupActivityContent(
    "Hemma", "Måndag 9 november", "Mån 9 nov", listOf(ActivityFraction("rest", "Restavfall", "Rest", "#111111", "trash")), false, null,
)

@RunWith(AndroidJUnit4::class)
class AndroidLiveUpdatesTest {
    private val systemCheck = AndroidLiveUpdates.canPostPromoted

    @Before
    fun setUp() {
        shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        // Systemet tillåter framhävda notiser för appen.
        AndroidLiveUpdates.canPostPromoted = { true }
    }

    @After
    fun tearDown() {
        AndroidLiveUpdates.canPostPromoted = systemCheck
    }

    /** Live Updates i appens lagring, som mottagarna läser. */
    private fun liveUpdates(clock: () -> Instant = Instant::now) = AndroidLiveUpdates(application, appStore, clock)

    /** En Live Update för tömningen i morgon, med start om en timme. */
    private fun planned(startsIn: Long = 3600, immediately: Boolean = false) = PlannedLiveActivity(
        testKey, StockholmClock.today().plusDays(1), Instant.ofEpochSecond(Instant.now().epochSecond + startsIn), immediately, content,
    )

    private fun shown(id: String): Notification? = notificationManager.getNotification(id, notificationId(id))

    private fun fireAll() {
        for (alarm in alarms.scheduledAlarms) alarms.fireAlarm(alarm)
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun startalarmetVisarFramhavdPagaendeNotis() = runBlocking {
        val updates = liveUpdates()
        updates.start(planned())
        val id = updates.current().single().activity.id
        assertNull(shown(id))
        assertEquals(planned().start.toEpochMilli(), alarms.scheduledAlarms.single().triggerAtMs)

        fireAll()
        val notification = requireNotNull(shown(id)) { "Live Updaten visas inte" }
        assertEquals(PickupActivityContent.ALERT_TITLE, notification.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertEquals(content.alertBody, notification.extras.getCharSequence(NotificationCompat.EXTRA_TEXT).toString())
        assertEquals(content.compactDate, NotificationCompat.getShortCriticalText(notification))
        assertTrue(notification.extras.getBoolean(NotificationCompat.EXTRA_REQUEST_PROMOTED_ONGOING))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertFalse(notification.extras.getBoolean(NotificationCompat.EXTRA_COLORIZED))
        assertEquals(NotificationChannels.LIVE_UPDATE, notification.channelId)
        assertEquals(12L * 3600 * 1000, notification.timeoutAfter)
        assertEquals(listOf(PickupActivityContent.DONE_BUTTON), notification.actions.map { it.title.toString() })
        assertEquals(LiveActivityPhase.Active, updates.current().single().phase)
    }

    @Test
    fun klartSparasVisarBockenOchTarBortNotisen() = runBlocking {
        // Appens modell används av knappen, med samma Live Updates som här.
        val updates = liveUpdates()
        updates.start(planned(immediately = true))
        val id = updates.current().single().activity.id
        val notification = requireNotNull(shown(id)) { "Live Updaten visas inte" }

        notification.actions.single().actionIntent.send()
        idleUntil { appStore.placedOut().isNotEmpty() && ScheduledReminders(appStore).read().liveUpdates.isEmpty() }

        assertEquals(listOf(PlacedOut(testKey, planned().pickupDate)), appStore.placedOut())
        // Bocken visas, utan knapp, och notisen försvinner av sig själv efter tre sekunder.
        val done = requireNotNull(shown(id)) { "Bocken visas inte" }
        assertEquals(PickupActivityContent.PLACED_OUT_TITLE, done.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertTrue(done.actions.isNullOrEmpty())
        assertEquals(PlacedOutAction.checkmarkDuration.toMillis(), done.timeoutAfter)
        assertNull(shadowOf(application).nextStartedActivity)
    }

    @Test
    fun bortsveptBlirDismissedOchStartasInteIgen() {
        // Tisdag 10 november 19:00. Tömningen är onsdag, så Live Updaten för kvällen före startar direkt.
        val dir: File = SophamtningApplication.storeDirectory(application)
        val clock = TestClock(StockholmClock.dateOn(day("2026-11-10"), 19 * 60))
        val updates = liveUpdates { clock.now }
        val app = TestApp(clock = clock, dir = dir, liveActivities = updates)
        onMain {
            app.model.add(testHit("Testgatan 1"))
            app.model.refreshAll(manual = false)
            app.model.setLiveActivity(true)
            app.model.settleReminders()
        }
        val id = onMain { updates.current() }.single().activity.id
        val notification = requireNotNull(shown(id)) { "Live Updaten visas inte" }

        // Användaren sveper bort den.
        notification.deleteIntent.send()
        shadowOf(Looper.getMainLooper()).idle()
        NotificationManagerCompat.from(application).cancel(id, notificationId(id))
        assertEquals(LiveActivityPhase.Dismissed, onMain { updates.current() }.single().phase)

        onMain {
            app.model.applyReminders()
            app.model.settleReminders()
        }
        // Samma tömning startas inte igen. Nästa tömning, torsdag, får en egen som väntar på sitt alarm.
        val current = onMain { updates.current() }
        val wednesday = current.filter { it.activity.pickupDate == day("2026-11-11") }
        assertEquals(listOf(id), wednesday.map { it.activity.id })
        assertEquals(LiveActivityPhase.Dismissed, wednesday.single().phase)
        assertNull(shown(id))
        assertEquals(listOf(day("2026-11-11")), app.store.endedActivities().map { it.date })
        assertEquals(listOf(LiveActivityPhase.Pending), current.filter { it.activity.pickupDate == day("2026-11-12") }.map { it.phase })
    }

    @Test
    fun currentSkiljerSchemalagdaFranVisade() = runBlocking {
        val updates = liveUpdates()
        updates.start(planned(startsIn = 3600))
        updates.start(planned(immediately = true).copy(pickupDate = StockholmClock.today().plusDays(2)))
        val phases = updates.current().associate { it.activity.pickupDate to it.phase }
        assertEquals(LiveActivityPhase.Pending, phases[StockholmClock.today().plusDays(1)])
        assertEquals(LiveActivityPhase.Active, phases[StockholmClock.today().plusDays(2)])
        assertTrue(updates.current().single { it.phase == LiveActivityPhase.Pending }.activity.isPending)
        assertFalse(updates.current().single { it.phase == LiveActivityPhase.Active }.activity.isPending)

        // Den som visas tas bort av systemet, till exempel efter tidsgränsen: den är inte längre pågående.
        val active = updates.current().single { it.phase == LiveActivityPhase.Active }.activity.id
        NotificationManagerCompat.from(application).cancel(active, notificationId(active))
        assertEquals(LiveActivityPhase.Ended, updates.current().single { it.activity.id == active }.phase)

        // Borttagen tas bort helt, också alarmet.
        val pending = updates.current().single { it.phase == LiveActivityPhase.Pending }.activity.id
        updates.remove(pending)
        assertTrue(alarms.scheduledAlarms.isEmpty())
        assertFalse(updates.current().any { it.activity.id == pending })
    }

    @Test
    @Config(sdk = [35])
    fun aldreAndroidGerVanligPagaendeNotis() = runBlocking {
        val updates = liveUpdates()
        updates.start(planned(immediately = true))
        val notification = requireNotNull(shown(updates.current().single().activity.id)) { "Live Updaten visas inte" }
        assertFalse(notification.extras.getBoolean(NotificationCompat.EXTRA_REQUEST_PROMOTED_ONGOING))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(PickupActivityContent.ALERT_TITLE, notification.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertEquals(listOf(PickupActivityContent.DONE_BUTTON), notification.actions.map { it.title.toString() })
    }

    @Test
    fun uppdateringSomInteKanSparasKraschar() = runBlocking {
        // Lagringens katalog är en fil, så inget går att spara.
        val blocked = java.io.File(application.cacheDir, "blockerad").apply { writeBytes(ByteArray(0)) }
        AndroidLiveUpdates(application, LocalStore(blocked)).update("live.x", content)
    }

    @Test
    fun visadFoeOmstartenFarBaraResterandeTid() {
        val now = Instant.now()
        val entry = ScheduledLiveUpdate("live.efter-omstart", testKey, StockholmClock.today(), now.minus(java.time.Duration.ofHours(11)).toEpochMilli(), content, started = true)
        val expired = ScheduledLiveUpdate("live.utgangen", testKey, StockholmClock.today(), now.minus(java.time.Duration.ofHours(13)).toEpochMilli(), content, started = true)
        ScheduledReminders(appStore).update { it.copy(liveUpdates = listOf(entry, expired)) }

        AndroidLiveUpdates.rescheduleAll(application, appStore, now)
        // Tidsgränsen räknas från starten, inte från omstarten: ungefär en timme kvar.
        val timeout = requireNotNull(shown(entry.id)) { "Live Updaten visas inte igen" }.timeoutAfter
        assertTrue("$timeout", timeout in java.time.Duration.ofMinutes(59).toMillis()..java.time.Duration.ofHours(1).toMillis())
        assertNull(shown(expired.id))
    }
}
