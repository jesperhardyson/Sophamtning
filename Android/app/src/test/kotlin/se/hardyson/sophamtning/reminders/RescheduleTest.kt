package se.hardyson.sophamtning.reminders

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.ui.FakeSoporApi
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.TestClock
import se.hardyson.sophamtning.ui.uiTestData

@RunWith(AndroidJUnit4::class)
class RescheduleTest {
    /** Ett API som kastar vid varje hämtning, som utan nät. */
    private val api = FakeSoporApi().apply { addressError = ApiError.Network }
    private val today = StockholmClock.today()
    private val zone: TimeZone = TimeZone.getDefault()

    @Before
    fun setUp() {
        shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(zone)
    }

    /** En adress med påminnelser på och ett sparat schema med tömning i övermorgon och om fem dagar. Appen använder dem. */
    private fun installApp(liveUpdate: Boolean) {
        val dir = SophamtningApplication.storeDirectory(application)
        val key = AddressKey("orebro", "1")
        val store = appStore
        store.setAddresses(
            listOf(
                SavedAddress(
                    key = key, url = "https://sopor.hardyson.se/api/v1/adress/orebro/1", street = "Storgatan 1", locality = "Örebro",
                    kommun = "Örebro", selection = "address", displayName = "Hemma", isPrimary = true, notificationsOn = true, addedAt = Instant.now(),
                ),
            ),
        )
        val base = ApiDecoding.addressResponse(uiTestData("uitest-adress"))
        val events = listOf(today.plusDays(2), today.plusDays(5)).map { PickupEvent(it, listOf("rest"), false, null, null, emptyMap()) }
        store.setSchedule(CachedSchedule(base.copy(events = events, next = emptyList()), fetchedAt = Instant.now()), key)
        store.setSettings(ReminderSettings(liveActivityOn = liveUpdate))
        val app = TestApp(
            api = api,
            clock = TestClock(Instant.now()),
            reminders = AndroidNotifications(application, store, NotificationPermission(application)),
            liveActivities = AndroidLiveUpdates(application, store),
            dir = dir,
        )
        application.dependencies = app.dependencies
        onMain {
            app.model.applyReminders()
            app.model.settleReminders()
        }
    }

    private fun triggers() = alarms.scheduledAlarms.map { it.triggerAtMs }.toSet()

    /** Telefonen startas om, och systemet glömmer alla alarm. */
    private fun forgetAlarms() {
        val manager = application.getSystemService(AlarmManager::class.java)
        for (alarm in alarms.scheduledAlarms) manager.cancel(requireNotNull(alarm.operation))
        assertTrue(alarms.scheduledAlarms.isEmpty())
    }

    private fun broadcast(action: String) {
        application.sendBroadcast(Intent(action).setPackage(application.packageName))
    }

    @Test
    fun omstartLaggerInAlarmenIgenUtanNat() {
        installApp(liveUpdate = true)
        val before = triggers()
        // Kvällens notis för övermorgon, notisen om fem dagar och Live Updatens start.
        assertEquals(3, before.size)

        forgetAlarms()
        broadcast(Intent.ACTION_BOOT_COMPLETED)
        idleUntil { triggers() == before }
        assertTrue(api.addressCalls.isEmpty())
    }

    @Test
    fun tidszonsbyteRaknarOmTillStockholm() {
        installApp(liveUpdate = false)
        forgetAlarms()
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        broadcast(Intent.ACTION_TIMEZONE_CHANGED)
        // Påminnelserna gäller fortfarande kl. 18:00 svensk tid.
        val expected = setOf(StockholmClock.dateOn(today.plusDays(1), 18 * 60), StockholmClock.dateOn(today.plusDays(4), 18 * 60)).map { it.toEpochMilli() }.toSet()
        idleUntil { triggers() == expected }
        assertTrue(api.addressCalls.isEmpty())
    }
}
