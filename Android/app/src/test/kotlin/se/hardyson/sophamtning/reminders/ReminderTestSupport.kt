package se.hardyson.sophamtning.reminders

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import java.time.Instant
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowNotificationManager
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.ReminderTiming

val application: SophamtningApplication get() = ApplicationProvider.getApplicationContext<Application>() as SophamtningApplication

/** Appens lagring, där också `scheduled-reminders.json` ligger. */
val appStore: LocalStore get() = LocalStore(SophamtningApplication.storeDirectory(application))

val alarms: ShadowAlarmManager get() = shadowOf(application.getSystemService(AlarmManager::class.java))

val notificationManager: ShadowNotificationManager get() = shadowOf(application.getSystemService(NotificationManager::class.java))

val testKey = AddressKey("orebro", "1")

/** En notis för tömningen [date], om [hours] timmar. */
fun planned(date: DayDate, hours: Long = 2, timing: ReminderTiming = ReminderTiming.EveningBefore) = PlannedNotification(
    identifier = PlannedNotification.identifier(testKey, date, timing),
    fireDate = Instant.now().plusSeconds(hours * 3600).let { Instant.ofEpochSecond(it.epochSecond) },
    title = "Ställ ut kärlen",
    body = "Hemma: Restavfall töms måndag 9 november.",
    key = testKey,
    pickupDate = date,
)

/** Låter huvudtråden och arbete på andra trådar bli klart, högst några sekunder. */
fun idleUntil(condition: () -> Boolean) {
    val deadline = System.nanoTime() + 5_000_000_000L
    while (!condition()) {
        shadowOf(Looper.getMainLooper()).idle()
        if (condition()) return
        if (System.nanoTime() > deadline) throw AssertionError("Villkoret uppfylldes inte")
        Thread.sleep(10)
    }
}
