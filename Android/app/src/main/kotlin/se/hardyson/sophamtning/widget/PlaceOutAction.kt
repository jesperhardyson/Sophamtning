package se.hardyson.sophamtning.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.action.ActionCallback
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

/**
 * Knappen **Ställ ut kärlen** i widgeten. Gör samma sak som Klart i Live Updaten och Utställt i notisen, via
 * `AppModel.markPlacedOut`: bocken sparas med tiden, tömningens notiser tas bort och Live Updaten avslutas. Körs utan att
 * appen öppnas. Widgeten och rutan ritas sedan om av [WidgetUpdates], eftersom Utställt ändras i appens tillstånd.
 */
class PlaceOutAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val entry = entry(parameters) ?: return
        placeOut(context, entry)
    }

    companion object {
        private val source = ActionParameters.Key<String>("källa")
        private val id = ActionParameters.Key<String>("id")
        private val date = ActionParameters.Key<String>("datum")

        fun parameters(entry: PlacedOut): ActionParameters =
            actionParametersOf(source to entry.key.source, id to entry.key.id, date to entry.date.iso)

        fun entry(parameters: ActionParameters): PlacedOut? {
            val day = parameters[date]?.let(DayDate::parse) ?: return null
            return PlacedOut(AddressKey(parameters[source] ?: return null, parameters[id] ?: return null), day)
        }

        /** Ställer ut kärlen för tömningen, på huvudtråden där appens modell hör hemma. Används också av rutan. */
        suspend fun placeOut(context: Context, entry: PlacedOut) {
            withContext(Dispatchers.Main) {
                val model = (context.applicationContext as SophamtningApplication).dependencies.model
                model.markPlacedOut(entry.key, entry.date)
                model.settleReminders()
            }
            // Widgeten visar Utställda innan processen kan frysas.
            WidgetUpdates.updateNow(context)
        }
    }
}
