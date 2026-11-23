package se.hardyson.sophamtning.background

import android.Manifest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.app.BackgroundRefreshRun
import se.hardyson.sophamtning.core.messages.SourceMessages
import se.hardyson.sophamtning.core.messages.SourceMessageKey
import se.hardyson.sophamtning.reminders.AndroidLiveUpdates
import se.hardyson.sophamtning.reminders.AndroidNotifications
import se.hardyson.sophamtning.reminders.NotificationPermission
import se.hardyson.sophamtning.reminders.alarms
import se.hardyson.sophamtning.reminders.application
import se.hardyson.sophamtning.reminders.appStore
import se.hardyson.sophamtning.reminders.notificationId
import se.hardyson.sophamtning.reminders.notificationManager
import se.hardyson.sophamtning.reminders.onMain
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.avestaArea
import se.hardyson.sophamtning.ui.testHit

@RunWith(AndroidJUnit4::class)
class RefreshWorkerTest {
    private lateinit var app: TestApp

    @Before
    fun setUp() {
        shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val store = appStore
        app = TestApp(
            reminders = AndroidNotifications(application, store, NotificationPermission(application)),
            liveActivities = AndroidLiveUpdates(application, store),
            dir = SophamtningApplication.storeDirectory(application),
        )
        application.dependencies = app.dependencies
    }

    private fun runWorker(): ListenableWorker.Result {
        val worker = TestListenableWorkerBuilder<RefreshWorker>(application).build()
        return onMain { worker.doWork() }
    }

    @Test
    fun arbetetHamtarOchPlanerarOm() {
        val key = testHit("Testgatan 1").let { se.hardyson.sophamtning.core.storage.AddressKey(it.source, it.id) }
        onMain {
            app.model.add(testHit("Testgatan 1"))
            app.model.setNotifications(true, key)
            app.model.settleReminders()
        }
        assertTrue(alarms.scheduledAlarms.isEmpty())

        assertEquals(ListenableWorker.Result.success(), runWorker())
        assertEquals(1, app.api.addressCalls.size)
        assertNotNull(app.model.state.value.schedules[key]?.response)
        // Påminnelserna är planerade från det nya schemat.
        assertTrue(alarms.scheduledAlarms.isNotEmpty())

        // En ny körning inom timmen hämtar inte igen.
        runWorker()
        assertEquals(1, app.api.addressCalls.size)
    }

    @Test
    fun arbetetSkickarNotisForNyttKallmeddelande() {
        val area = avestaArea("Askön, Nyhyttan m.fl.")
        onMain { app.model.add(area) }
        runWorker()
        // Bakgrunden räknas som `Background`: ett nytt meddelande från källan ger en notis.
        val identifier = SourceMessages.notificationId(SourceMessageKey("avesta", "nya-rutter-2026"))
        assertNotNull(notificationManager.getNotification(identifier, notificationId(identifier)))
        assertEquals("Hämtrutterna läggs om", notificationManager.getNotification(identifier, notificationId(identifier)).extras.getCharSequence("android.text").toString())
    }

    private fun scheduledWork(): androidx.work.WorkInfo {
        WorkManagerTestInitHelper.initializeTestWorkManager(application, Configuration.Builder().setExecutor(SynchronousExecutor()).build())
        RefreshWorker.schedule(application)
        RefreshWorker.schedule(application)
        return WorkManager.getInstance(application).getWorkInfosForUniqueWork(BackgroundRefreshRun.UNIQUE_NAME).get().single()
    }

    @Test
    fun arbetetKraverNat() {
        assertEquals(NetworkType.CONNECTED, scheduledWork().constraints.requiredNetworkType)
    }

    @Test
    fun arbetetKorsVarTredjeTimme() {
        val info = scheduledWork()
        assertEquals(Duration.ofHours(3).toMillis(), info.periodicityInfo?.repeatIntervalMillis)
    }
}
