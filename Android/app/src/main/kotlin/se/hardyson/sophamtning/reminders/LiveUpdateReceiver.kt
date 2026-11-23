package se.hardyson.sophamtning.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.reminders.PlacedOutNotification
import se.hardyson.sophamtning.core.storage.LocalStore

/**
 * Live Updatens alarm vid starten, knappen **Klart** och bortsvepningen. Allt körs utan att appen öppnas. Klart gör samma
 * sak som Utställt i notisen: bocken sparas, Live Updaten visar bocken en kort stund och tömningens notiser tas bort.
 */
class LiveUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = LocalStore(SophamtningApplication.storeDirectory(context))
        when (intent.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: return
                runCatching { AndroidLiveUpdates.startDue(context, store, id) }
            }
            ACTION_DONE -> {
                val info = intent.extras?.let { extras -> extras.keySet().associateWith { extras.getString(it) } } ?: return
                val entry = PlacedOutNotification.entry(info) ?: return
                ReminderAlarmReceiver.markPlacedOut(context, entry, goAsync())
            }
            ACTION_DISMISSED -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: return
                runCatching { AndroidLiveUpdates.markDismissed(store, id) }
            }
        }
    }

    companion object {
        const val ACTION_START = "se.hardyson.sophamtning.action.LIVE_UPDATE_START"
        const val ACTION_DONE = "se.hardyson.sophamtning.action.KLART"
        const val ACTION_DISMISSED = "se.hardyson.sophamtning.action.LIVE_UPDATE_BORTSVEPT"
        const val EXTRA_ID = "id"
    }
}
