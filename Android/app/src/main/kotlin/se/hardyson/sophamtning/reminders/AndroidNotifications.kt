package se.hardyson.sophamtning.reminders

import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.net.toUri
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationScheduling
import se.hardyson.sophamtning.core.reminders.PendingNotification
import se.hardyson.sophamtning.core.reminders.PlacedOutNotification
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.LocalStore

/**
 * Påminnelserna som alarm och notiser, som `NotificationScheduler` på iOS. Varje notis får ett alarm vid sin tid, och det
 * som är schemalagt sparas i [ScheduledReminders]. När alarmet går visar [ReminderAlarmReceiver] notisen med knappen
 * **Utställt**, om appen får visa notiser då.
 */
class AndroidNotifications(
    private val context: Context,
    store: LocalStore,
    private val permission: NotificationPermission,
) : NotificationScheduling {
    private val scheduled = ScheduledReminders(store)

    override suspend fun authorization(): NotificationAuthorization = permission.authorization()

    override suspend fun requestAuthorization(): Boolean = permission.request()

    override suspend fun pending(): List<PendingNotification> =
        scheduled.read().notifications.map { PendingNotification(it.identifier, it.fireDate, it.body) }

    override suspend fun schedule(notifications: List<PlannedNotification>): List<String> {
        val set = mutableListOf<PlannedNotification>()
        val failed = mutableListOf<String>()
        for (notification in notifications) {
            try {
                Alarms.set(context, notification.fireDate, alarmIntent(context, notification.identifier))
                set += notification
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                failed += notification.identifier
            }
        }
        val ids = set.map { it.identifier }.toSet()
        try {
            scheduled.update { file -> file.copy(notifications = file.notifications.filter { it.identifier !in ids } + set.map(ScheduledNotification::from)) }
        } catch (_: Exception) {
            // Utan sparad post visas notisen inte när alarmet går, så alarmet tas bort och notisen räknas som misslyckad.
            for (notification in set) Alarms.cancel(context, alarmIntent(context, notification.identifier))
            return failed + ids
        }
        return failed
    }

    override suspend fun cancel(identifiers: List<String>) {
        val manager = NotificationManagerCompat.from(context)
        for (id in identifiers) {
            Alarms.cancel(context, alarmIntent(context, id))
            manager.cancel(id, notificationId(id))
        }
        try {
            scheduled.update { file -> file.copy(notifications = file.notifications.filter { it.identifier !in identifiers }) }
        } catch (_: Exception) {
            // Alarmen är borta, så en kvarglömd post visar ingen notis. Nästa planering rättar filen.
        }
    }

    override suspend fun deliverNow(identifier: String, title: String, body: String) {
        val notification = NotificationCompat.Builder(context, NotificationChannels.SOURCE_MESSAGES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openApp(context))
            .setAutoCancel(true)
            .build()
        post(context, identifier, notification)
    }

    companion object {
        /** Alarmet för notisen. Adressen i `data` gör varje notis till ett eget alarm, oavsett heltals-id. */
        internal fun alarmIntent(context: Context, identifier: String): PendingIntent {
            val intent = Intent(context, ReminderAlarmReceiver::class.java)
                .setAction(ReminderAlarmReceiver.ACTION_SHOW)
                .setData("sophamtning://paminnelse/${android.net.Uri.encode(identifier)}".toUri())
                .putExtra(ReminderAlarmReceiver.EXTRA_IDENTIFIER, identifier)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** Öppnar appen när notisen trycks. */
        internal fun openApp(context: Context): PendingIntent? {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
            return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /**
         * Alarmet har gått: posten tas bort och notisen visas, om appen får visa notiser. Finns ingen post är notisen
         * borttagen under tiden, och då visas inget.
         */
        internal fun showDue(context: Context, store: LocalStore, identifier: String) {
            var due: ScheduledNotification? = null
            try {
                ScheduledReminders(store).update { file ->
                    due = file.notifications.firstOrNull { it.identifier == identifier }
                    file.copy(notifications = file.notifications.filter { it.identifier != identifier })
                }
            } catch (_: Exception) {
                due = ScheduledReminders(store).read().notifications.firstOrNull { it.identifier == identifier }
            }
            val entry = due ?: return
            post(context, identifier, reminder(context, entry))
        }

        /** Påminnelsen med knappen **Utställt**, som markerar tömningen utan att appen öppnas. */
        private fun reminder(context: Context, entry: ScheduledNotification): Notification {
            val info = PlacedOutNotification.userInfo(entry.key, entry.pickupDate)
            val placedOut = Intent(context, ReminderAlarmReceiver::class.java)
                .setAction(ReminderAlarmReceiver.ACTION_PLACED_OUT)
                .setData("sophamtning://utstallt/${android.net.Uri.encode(entry.identifier)}".toUri())
            info.forEach { (key, value) -> placedOut.putExtra(key, value) }
            val action = PendingIntent.getBroadcast(context, 0, placedOut, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            return NotificationCompat.Builder(context, NotificationChannels.REMINDERS)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(entry.title)
                .setContentText(entry.body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(entry.body))
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setWhen(entry.fireAt)
                .setShowWhen(true)
                .setContentIntent(openApp(context))
                .setAutoCancel(true)
                .addAction(0, PlacedOutNotification.ACTION_TITLE, action)
                .build()
        }

        /** Visar notisen med identifieraren som tagg, om appen får visa notiser. Annars visas inget. */
        @SuppressLint("MissingPermission") // Tillståndet kontrolleras i canNotify.
        internal fun post(context: Context, identifier: String, notification: Notification) {
            if (!NotificationPermission.canNotify(context)) return
            try {
                NotificationManagerCompat.from(context).notify(identifier, notificationId(identifier), notification)
            } catch (_: SecurityException) {
                // Tillståndet drogs tillbaka mellan kontrollen och notisen.
            }
        }

        /** Hur sen en missad påminnelse får vara och ändå visas. */
        val MISSED_LIMIT: Duration = Duration.ofHours(2)

        /**
         * Lägger in alarmen igen från filen: när appen startar, efter omstart, ändrad tid eller tidszon, en appuppdatering eller
         * ändrade exakta alarm. Utan nät. Systemet kan ha glömt alarmen utan att säga till, till exempel efter tvångsstopp.
         * En påminnelse vars tid passerade medan telefonen var avstängd visas direkt, om den är högst [MISSED_LIMIT] sen och
         * tömningen inte har passerat i Stockholm. Annars tas den bort.
         */
        fun rescheduleAll(context: Context, store: LocalStore, now: Instant = Instant.now()) {
            val scheduled = ScheduledReminders(store)
            val file = scheduled.read()
            val (future, past) = file.notifications.partition { it.fireDate > now }
            val today = StockholmClock.today(now)
            for (entry in past) {
                if (entry.fireDate >= now.minus(MISSED_LIMIT) && entry.pickupDate >= today) post(context, entry.identifier, reminder(context, entry))
            }
            for (entry in future) {
                try {
                    Alarms.set(context, entry.fireDate, alarmIntent(context, entry.identifier))
                } catch (_: Exception) {
                    // Nästa planering lägger in den igen.
                }
            }
            if (past.isNotEmpty()) {
                val gone = past.map { it.identifier }.toSet()
                try {
                    scheduled.update { it.copy(notifications = it.notifications.filter { n -> n.identifier !in gone }) }
                } catch (_: Exception) {
                }
            }
        }
    }
}
