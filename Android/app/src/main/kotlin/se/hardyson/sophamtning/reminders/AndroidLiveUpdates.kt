package se.hardyson.sophamtning.reminders

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.annotation.VisibleForTesting
import androidx.core.net.toUri
import java.time.Duration
import java.time.Instant
import java.util.UUID
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.placedout.PlacedOutAction
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.LiveActivityPhase
import se.hardyson.sophamtning.core.reminders.LiveActivityScheduling
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.PlacedOutNotification
import se.hardyson.sophamtning.core.reminders.PlannedLiveActivity
import se.hardyson.sophamtning.core.reminders.StartMode
import se.hardyson.sophamtning.core.reminders.SystemActivity
import se.hardyson.sophamtning.core.reminders.alertBody
import se.hardyson.sophamtning.core.reminders.compactDate
import se.hardyson.sophamtning.core.reminders.detailLine
import se.hardyson.sophamtning.core.reminders.startMode
import se.hardyson.sophamtning.core.reminders.title
import se.hardyson.sophamtning.core.storage.LocalStore

/**
 * Live Update, som `LiveActivityScheduler` på iOS: ett alarm vid starttiden visar en pågående notis med kärlen och knappen
 * **Klart**. I Android 16 QPR2 (API 36.1) och senare begärs den som framhävd, med datumet som chip i statusfältet. Tillåts
 * det inte, eller på äldre Android, blir det samma notis utan framhävning.
 *
 * Det som är schemalagt sparas i [ScheduledReminders]. `current()` ger det som väntar på sitt alarm som `Pending`, det som
 * visas som `Active`, det som svepts bort som `Dismissed` och det som systemet tagit bort som `Ended`.
 */
class AndroidLiveUpdates(
    private val context: Context,
    store: LocalStore,
    private val clock: () -> Instant = Instant::now,
) : LiveActivityScheduling {
    private val scheduled = ScheduledReminders(store)

    override suspend fun areEnabled(): Boolean {
        if (!NotificationPermission.canNotify(context)) return false
        val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(NotificationChannels.LIVE_UPDATE)
        return channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    override suspend fun current(): List<SystemActivity> {
        val today = StockholmClock.today(clock())
        val showing = showingTags(context)
        val file = scheduled.read()
        // Passerade tömningar som inte längre visas är bara städning.
        val (old, kept) = file.liveUpdates.partition { it.pickupDate < today && it.id !in showing }
        if (old.isNotEmpty()) {
            try {
                scheduled.update { f -> f.copy(liveUpdates = f.liveUpdates - old.toSet()) }
            } catch (_: Exception) {
            }
        }
        return kept.map { entry ->
            val phase = when {
                !entry.started -> LiveActivityPhase.Pending
                entry.dismissed -> LiveActivityPhase.Dismissed
                entry.id in showing -> LiveActivityPhase.Active
                else -> LiveActivityPhase.Ended
            }
            SystemActivity(
                ExistingActivity(entry.id, entry.key, entry.pickupDate, entry.content, isPending = !entry.started, start = Instant.ofEpochMilli(entry.start)),
                phase,
            )
        }
    }

    override suspend fun start(activity: PlannedLiveActivity) {
        val mode = activity.startMode(clock())
        val entry = ScheduledLiveUpdate(
            id = "live.${UUID.randomUUID()}",
            key = activity.key,
            pickupDate = activity.pickupDate,
            start = activity.start.toEpochMilli(),
            content = activity.content,
            started = mode == StartMode.Immediately,
        )
        scheduled.update { it.copy(liveUpdates = it.liveUpdates + entry) }
        when (mode) {
            StartMode.Immediately -> show(context, entry)
            is StartMode.Scheduled -> try {
                Alarms.set(context, mode.at, startIntent(context, entry.id))
            } catch (e: Exception) {
                scheduled.update { f -> f.copy(liveUpdates = f.liveUpdates.filter { it.id != entry.id }) }
                throw e
            }
        }
    }

    override suspend fun update(id: String, content: PickupActivityContent) {
        val updated = try {
            scheduled.update { f -> f.copy(liveUpdates = f.liveUpdates.map { if (it.id == id) it.copy(content = content) else it }) }
        } catch (_: Exception) {
            // Utan sparat innehåll visas det gamla. Nästa planering försöker igen.
            return
        }
        val entry = updated.liveUpdates.firstOrNull { it.id == id } ?: return
        if (entry.started && !entry.dismissed && id in showingTags(context)) show(context, entry)
    }

    override suspend fun remove(id: String) {
        Alarms.cancel(context, startIntent(context, id))
        NotificationManagerCompat.from(context).cancel(id, notificationId(id))
        try {
            scheduled.update { f -> f.copy(liveUpdates = f.liveUpdates.filter { it.id != id }) }
        } catch (_: Exception) {
            // Alarmet och notisen är borta. En kvarglömd post räknas som avslutad och städas bort efter tömningen.
        }
    }

    /** Visar bocken i [PlacedOutAction.checkmarkDuration], och sedan tar systemet bort notisen, även om appen inte körs. */
    override suspend fun end(id: String, content: PickupActivityContent) {
        val entry = scheduled.read().liveUpdates.firstOrNull { it.id == id }
        Alarms.cancel(context, startIntent(context, id))
        if (entry != null && entry.started && !entry.dismissed) {
            show(context, entry.copy(content = content), timeout = PlacedOutAction.checkmarkDuration)
        } else {
            NotificationManagerCompat.from(context).cancel(id, notificationId(id))
        }
        try {
            scheduled.update { f -> f.copy(liveUpdates = f.liveUpdates.filter { it.id != id }) }
        } catch (_: Exception) {
        }
    }

    companion object {
        /** Hur länge en Live Update visas som längst, om Klart aldrig trycks. */
        val TIMEOUT: Duration = Duration.ofHours(12)

        /** Om systemet tillåter framhävda notiser för appen. Testerna sätter den, eftersom Robolectric inte kan svara. */
        @VisibleForTesting
        var canPostPromoted: (Context) -> Boolean = { NotificationManagerCompat.from(it).canPostPromotedNotifications() }

        /** Framhävning finns från Android 16 QPR2 (API 36.1), och bara när systemet tillåter den för appen. */
        fun promotionAllowed(context: Context): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
                Build.VERSION.SDK_INT_FULL >= Build.VERSION_CODES_FULL.BAKLAVA_1 &&
                runCatching { canPostPromoted(context) }.getOrDefault(false)

        private fun showingTags(context: Context): Set<String> =
            context.getSystemService(NotificationManager::class.java).activeNotifications.mapNotNull { it.tag }.toSet()

        /** Alarmet vid starttiden. */
        internal fun startIntent(context: Context, id: String): PendingIntent =
            broadcast(context, LiveUpdateReceiver.ACTION_START, "start", id)

        private fun broadcast(context: Context, action: String, path: String, id: String): PendingIntent {
            val intent = Intent(context, LiveUpdateReceiver::class.java)
                .setAction(action)
                .setData("sophamtning://live-update/$path/$id".toUri())
                .putExtra(LiveUpdateReceiver.EXTRA_ID, id)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** Knappen **Klart**, som markerar tömningen som utställd utan att appen öppnas. */
        private fun doneIntent(context: Context, entry: ScheduledLiveUpdate): PendingIntent {
            val intent = Intent(context, LiveUpdateReceiver::class.java)
                .setAction(LiveUpdateReceiver.ACTION_DONE)
                .setData("sophamtning://live-update/klart/${entry.id}".toUri())
            PlacedOutNotification.userInfo(entry.key, entry.pickupDate).forEach { (key, value) -> intent.putExtra(key, value) }
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** Visar Live Updaten. Utan tillstånd för notiser visas inget, och den räknas som avslutad. */
        internal fun show(context: Context, entry: ScheduledLiveUpdate, timeout: Duration = TIMEOUT) {
            AndroidNotifications.post(context, entry.id, notification(context, entry, promotionAllowed(context), timeout))
        }

        private fun notification(context: Context, entry: ScheduledLiveUpdate, promoted: Boolean, timeout: Duration): Notification {
            val content = entry.content
            val text = if (content.placedOut) content.detailLine else content.alertBody
            val builder = NotificationCompat.Builder(context, NotificationChannels.LIVE_UPDATE)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(content.title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setColorized(false)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setShortCriticalText(content.compactDate)
                .setTimeoutAfter(timeout.toMillis())
                .setContentIntent(AndroidNotifications.openApp(context))
                .setDeleteIntent(broadcast(context, LiveUpdateReceiver.ACTION_DISMISSED, "bortsvept", entry.id))
            if (promoted) builder.setRequestPromotedOngoing(true)
            if (!content.placedOut) builder.addAction(0, PickupActivityContent.DONE_BUTTON, doneIntent(context, entry))
            return builder.build()
        }

        /** Alarmet har gått: Live Updaten visas, om den fortfarande finns. */
        internal fun startDue(context: Context, store: LocalStore, id: String) {
            val updated = ScheduledReminders(store).update { f -> f.copy(liveUpdates = f.liveUpdates.map { if (it.id == id) it.copy(started = true) else it }) }
            val entry = updated.liveUpdates.firstOrNull { it.id == id } ?: return
            show(context, entry)
        }

        /** Användaren har svept bort notisen. Samma tömning startas inte igen. */
        internal fun markDismissed(store: LocalStore, id: String) {
            ScheduledReminders(store).update { f -> f.copy(liveUpdates = f.liveUpdates.map { if (it.id == id) it.copy(dismissed = true) else it }) }
        }

        /**
         * Lägger in alarmen igen efter omstart, ändrad tid eller tidszon, en appuppdatering eller ändrade exakta alarm. En
         * Live Update som visades före omstarten visas igen, om den inte är bortsvept och tidsgränsen inte har gått ut.
         */
        fun rescheduleAll(context: Context, store: LocalStore, now: Instant = Instant.now()) {
            val showing = showingTags(context)
            for (entry in ScheduledReminders(store).read().liveUpdates) {
                val start = Instant.ofEpochMilli(entry.start)
                if (start.plus(TIMEOUT) <= now || entry.dismissed) continue
                try {
                    when {
                        // Ett alarm i det förflutna går direkt, och då visas den.
                        !entry.started -> Alarms.set(context, start, startIntent(context, entry.id))
                        // Tidsgränsen räknas från starten, så att en omstart inte förlänger den.
                        entry.id !in showing -> show(context, entry, timeout = Duration.between(now, start.plus(TIMEOUT)))
                    }
                } catch (_: Exception) {
                    // Nästa planering lägger in den igen.
                }
            }
        }
    }
}
