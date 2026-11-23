package se.hardyson.sophamtning.reminders

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.widget.WidgetUpdates

/**
 * Lägger in påminnelserna igen när systemet har glömt eller flyttat alarmen: efter omstart, ändrad tid eller tidszon, en
 * appuppdatering och när exakta alarm slås på eller av. Widgetarnas alarm vid midnatt läggs också in igen. Allt läses från det som är sparat, utan nät. Sedan planeras
 * påminnelserna om från det sparade schemat, så att de gäller kl. 18:00 svensk tid oavsett telefonens tidszon.
 */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        val pending = goAsync()
        val store = LocalStore(SophamtningApplication.storeDirectory(context))
        runCatching { AndroidNotifications.rescheduleAll(context, store) }
        runCatching { AndroidLiveUpdates.rescheduleAll(context, store) }
        val model = (context.applicationContext as SophamtningApplication).dependencies.model
        // Widgetarnas midnatt är också ett alarm, och en ändrad tid kan ha flyttat dagen.
        runCatching { WidgetUpdates.armMidnight(context) }
        ReceiverWork.launch(finish = pending::finish) {
            model.applyReminders()
            model.settleReminders()
            WidgetUpdates.updateNow(context)
        }
    }

    companion object {
        private val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
        )
    }
}
