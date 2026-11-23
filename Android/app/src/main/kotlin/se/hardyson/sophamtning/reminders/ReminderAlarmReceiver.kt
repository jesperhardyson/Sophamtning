package se.hardyson.sophamtning.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.reminders.PlacedOutNotification
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut

/**
 * Alarmen för påminnelserna och knappen **Utställt** i notisen. Båda körs utan att appen öppnas. Knappen gör samma sak som
 * `markPlacedOut` i appen: bocken sparas, Live Updaten avslutas och tömningens båda notiser tas bort.
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SHOW -> {
                val identifier = intent.getStringExtra(EXTRA_IDENTIFIER) ?: return
                AndroidNotifications.showDue(context, LocalStore(SophamtningApplication.storeDirectory(context)), identifier)
            }
            ACTION_PLACED_OUT -> {
                val info = intent.extras?.let { extras -> extras.keySet().associateWith { extras.getString(it) } } ?: return
                val entry = PlacedOutNotification.entry(info) ?: return
                markPlacedOut(context, entry, goAsync())
            }
        }
    }

    companion object {
        const val ACTION_SHOW = "se.hardyson.sophamtning.action.PAMINNELSE"
        const val ACTION_PLACED_OUT = "se.hardyson.sophamtning.action.UTSTALLT"
        const val EXTRA_IDENTIFIER = "identifierare"

        /** Mottagaren har ungefär tio sekunder på sig. Arbetet avbryts före det, och nästa planering rättar det som återstår. */
        private const val TIME_LIMIT_MILLIS = 8_000L

        /**
         * Ställer ut kärlen i appens modell, utan att appen öppnas, och avslutar sedan [pending]. Modellen hör till
         * huvudtråden, som på iOS.
         */
        internal fun markPlacedOut(context: Context, entry: PlacedOut, pending: PendingResult) {
            val model = (context.applicationContext as SophamtningApplication).dependencies.model
            CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                try {
                    withTimeoutOrNull(TIME_LIMIT_MILLIS) {
                        model.markPlacedOut(entry.key, entry.date)
                        model.settleReminders()
                    }
                } finally {
                    pending.finish()
                }
            }
        }
    }
}
