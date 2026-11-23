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
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.widget.WidgetData
import java.time.Instant

/**
 * Knappen **Ställ ut kärlen** i widgeten. Gör samma sak som Klart i Live Updaten och Utställt i notisen, via
 * `AppModel.markPlacedOut`: bocken sparas med tiden, tömningens notiser tas bort och Live Updaten avslutas. Körs utan att
 * appen öppnas. Widgeten och rutan ritas sedan om av [WidgetUpdates], eftersom Utställt ändras i appens tillstånd.
 */
class PlaceOutAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        perform(context, parameters)
    }

    companion object {
        private val source = ActionParameters.Key<String>("källa")
        private val id = ActionParameters.Key<String>("id")
        private val date = ActionParameters.Key<String>("datum")

        /**
         * Trycket på knappen. Widgeten kan ha ritats för en tömning som inte längre gäller, till exempel efter att schemat
         * ändrats, så tömningen räknas om från lagringen och klockan nu. Bara när den är samma ställs kärlen ut.
         */
        suspend fun perform(context: Context, parameters: ActionParameters) {
            val requested = entry(parameters) ?: return
            val current = withContext(Dispatchers.IO) {
                val store = LocalStore(SophamtningApplication.storeDirectory(context))
                WidgetData.read(store).placeOutEntry(clock(context)())
            }
            if (current == requested) placeOut(context, requested)
        }

        private suspend fun clock(context: Context): () -> Instant = withContext(Dispatchers.Main) {
            (context.applicationContext as SophamtningApplication).dependencies.clock
        }

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
