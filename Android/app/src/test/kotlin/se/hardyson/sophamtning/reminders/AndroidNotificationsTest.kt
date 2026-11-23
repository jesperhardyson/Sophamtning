package se.hardyson.sophamtning.reminders

import android.Manifest
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.PlacedOutNotification
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderTiming

// Tömningarna ligger framför i dag, eftersom mottagarna räknar med den riktiga klockan.
private val monday = StockholmClock.today().plusDays(1)
private val thursday = StockholmClock.today().plusDays(4)

@RunWith(AndroidJUnit4::class)
class AndroidNotificationsTest {
    private val notifications by lazy { AndroidNotifications(application, appStore, NotificationPermission(application)) }

    @Before
    fun setUp() {
        shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun fire(notification: PlannedNotification) {
        val alarm = alarms.scheduledAlarms.single { it.triggerAtMs == notification.fireDate.toEpochMilli() }
        alarms.fireAlarm(alarm)
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun shown(identifier: String) = notificationManager.getNotification(identifier, notificationId(identifier))

    @Test
    fun schemalaggerExaktNarDetArTillatet() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        val notification = planned(monday)
        assertEquals(emptyList<String>(), notifications.schedule(listOf(notification)))
        val alarm = alarms.scheduledAlarms.single()
        assertEquals(notification.fireDate.toEpochMilli(), alarm.triggerAtMs)
        assertEquals(ShadowAlarmManager.WINDOW_EXACT, alarm.windowLengthMs)
        assertTrue(alarm.isAllowWhileIdle)
    }

    @Test
    fun schemalaggerUtanExaktTidNarExaktaTiderInteArTillatna() = runBlocking {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        val notification = planned(monday)
        notifications.schedule(listOf(notification))
        val alarm = alarms.scheduledAlarms.single()
        // Ett inexakt alarm från vald tid, som också går när telefonen vilar (Doze).
        assertEquals(notification.fireDate.toEpochMilli(), alarm.triggerAtMs)
        assertEquals(ShadowAlarmManager.WINDOW_HEURISTIC, alarm.windowLengthMs)
        assertTrue(alarm.isAllowWhileIdle)
    }

    @Test
    fun alarmetVisarNotisenMedUtstalltKnapp() = runBlocking {
        val notification = planned(monday)
        notifications.schedule(listOf(notification))
        fire(notification)
        val shown = requireNotNull(shown(notification.identifier)) { "Notisen visas inte" }
        assertEquals("Ställ ut kärlen", shown.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertEquals(notification.body, shown.extras.getCharSequence(NotificationCompat.EXTRA_TEXT).toString())
        assertEquals(NotificationChannels.REMINDERS, shown.channelId)
        assertEquals(listOf(PlacedOutNotification.ACTION_TITLE), shown.actions.map { it.title.toString() })
    }

    @Test
    fun utstalltIKnappenSparasUtanAttAppenOppnas() = runBlocking {
        val notification = planned(monday)
        val morning = planned(monday, hours = 3, timing = ReminderTiming.SameMorning)
        notifications.schedule(listOf(notification, morning))
        fire(notification)
        val shown = requireNotNull(shown(notification.identifier)) { "Notisen visas inte" }

        shown.actions.single().actionIntent.send()
        idleUntil { appStore.placedOut().isNotEmpty() && shown(notification.identifier) == null }

        assertEquals(listOf(PlacedOut(testKey, monday)), appStore.placedOut())
        // Båda notiserna för tömningen är borta, den som visas och morgonens som väntar.
        assertNull(shown(notification.identifier))
        idleUntil { alarms.scheduledAlarms.isEmpty() }
        assertTrue(notifications.pending().isEmpty())
        // Appen öppnades inte.
        assertNull(shadowOf(application).nextStartedActivity)
    }

    @Test
    fun pendingGerDetSomArSchemalagtOchInteHarGattAv() = runBlocking {
        val first = planned(monday, hours = 1)
        val second = planned(thursday, hours = 2)
        notifications.schedule(listOf(first, second))
        assertEquals(setOf(first.identifier, second.identifier), notifications.pending().map { it.identifier }.toSet())

        fire(first)
        val pending = notifications.pending().single()
        assertEquals(second.identifier, pending.identifier)
        assertEquals(second.fireDate, pending.fireDate)
        assertEquals(second.body, pending.body)
    }

    @Test
    fun cancelTarBortAlarmOchNotis() = runBlocking {
        val first = planned(monday, hours = 1)
        val second = planned(thursday, hours = 2)
        notifications.schedule(listOf(first, second))
        fire(first)
        assertNotNull(shown(first.identifier))

        notifications.cancel(listOf(first.identifier, second.identifier))
        assertNull(shown(first.identifier))
        assertTrue(alarms.scheduledAlarms.isEmpty())
        assertTrue(notifications.pending().isEmpty())
    }

    @Test
    fun deliverNowVisasDirekt() = runBlocking {
        notifications.deliverNow("kalla.avesta.nya-rutter", "Avesta Vatten och Avfall", "Hämtrutterna läggs om")
        val shown = requireNotNull(shown("kalla.avesta.nya-rutter")) { "Notisen visas inte" }
        assertEquals(NotificationChannels.SOURCE_MESSAGES, shown.channelId)
        assertEquals("Avesta Vatten och Avfall", shown.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertEquals("Hämtrutterna läggs om", shown.extras.getCharSequence(NotificationCompat.EXTRA_TEXT).toString())
        // En notis som visats direkt räknas inte som väntande, så planeringen tar aldrig bort den.
        assertTrue(notifications.pending().isEmpty())
    }

    @Test
    fun ingenNotisNarNotiserArAvstangda() = runBlocking {
        val notification = planned(monday)
        notifications.schedule(listOf(notification))
        notificationManager.setNotificationsEnabled(false)
        fire(notification)
        notifications.deliverNow("kalla.avesta.nya-rutter", "Avesta Vatten och Avfall", "Hämtrutterna läggs om")
        assertEquals(0, notificationManager.size())
        assertFalse(notifications.pending().any { it.identifier == notification.identifier })
    }

    /** En notis i filen som aldrig fick gå: telefonen var avstängd vid [fireDate]. */
    private fun missed(fireDate: Instant, pickup: se.hardyson.sophamtning.core.dates.DayDate): String {
        val entry = ScheduledNotification.from(planned(pickup).copy(fireDate = fireDate))
        ScheduledReminders(appStore).update { it.copy(notifications = it.notifications + entry) }
        return entry.identifier
    }

    @Test
    fun missadUnderAvstangningVisasNarDenArHogstTvaTimmarSen() {
        val now = Instant.now()
        val late = missed(now.minus(Duration.ofMinutes(90)), StockholmClock.today().plusDays(1))
        AndroidNotifications.rescheduleAll(application, appStore, now)
        // Påminnelsen kommer när telefonen startar, och står inte kvar som väntande.
        assertEquals("Ställ ut kärlen", requireNotNull(shown(late)) { "Notisen visas inte" }.extras.getString(NotificationCompat.EXTRA_TITLE))
        assertTrue(ScheduledReminders(appStore).read().notifications.isEmpty())
    }

    @Test
    fun missadUnderAvstangningTasBortNarDenArForSenEllerTomningenPasserat() {
        val now = Instant.now()
        val tooLate = missed(now.minus(Duration.ofMinutes(150)), StockholmClock.today().plusDays(1))
        val passed = missed(now.minus(Duration.ofMinutes(30)), StockholmClock.today().plusDays(-1))
        AndroidNotifications.rescheduleAll(application, appStore, now)
        assertNull(shown(tooLate))
        assertNull(shown(passed))
        assertTrue(ScheduledReminders(appStore).read().notifications.isEmpty())
    }

    @Test
    fun appstartenLaggerInAlarmenFranFilenIgen() {
        // Systemet har tagit bort alarmen, till exempel efter tvångsstopp eller när exakta alarm drogs in.
        val notification = planned(monday)
        ScheduledReminders(appStore).update { it.copy(notifications = listOf(ScheduledNotification.from(notification))) }
        val live = ScheduledLiveUpdate("live.x", testKey, monday, Instant.now().plusSeconds(7200).toEpochMilli(), notificationContent)
        ScheduledReminders(appStore).update { it.copy(liveUpdates = listOf(live)) }
        assertTrue(alarms.scheduledAlarms.isEmpty())

        application.onCreate()
        assertEquals(setOf(notification.fireDate.toEpochMilli(), live.start), alarms.scheduledAlarms.map { it.triggerAtMs }.toSet())
    }
}

private val notificationContent = se.hardyson.sophamtning.core.reminders.PickupActivityContent(
    "Hemma", "Måndag 9 november", "Mån 9 nov", emptyList(), false, null,
)
