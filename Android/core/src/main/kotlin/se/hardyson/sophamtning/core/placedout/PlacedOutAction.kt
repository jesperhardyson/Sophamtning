package se.hardyson.sophamtning.core.placedout

import java.time.Duration
import kotlin.coroutines.cancellation.CancellationException
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderTiming

/** Att soporna är utställda, som knappen **Utställt** utför det. Körs utan att appen öppnas. */
object PlacedOutAction {
    /** Hur länge bocken visas innan Live Updaten försvinner. */
    val checkmarkDuration: Duration = Duration.ofSeconds(3)

    /**
     * Sparar valet, avslutar Live Updaten och tar sedan bort tömningens väntande notiser, både kvällens och morgonens, via
     * [cancelReminder] med varje notis identifierare. Inget fel kastas utanför: ett skrivfel hindrar varken avslutningen eller
     * borttagningen, och ett fel vid borttagningen ger i värsta fall en extra påminnelse, eftersom nästa planering rättar det.
     * Svarar med om valet sparades.
     */
    suspend fun perform(
        store: LocalStore,
        entry: PlacedOut,
        today: DayDate,
        end: suspend () -> Unit,
        cancelReminder: suspend (String) -> Unit,
    ): Boolean {
        val saved = attempt { store.markPlacedOut(entry, today) }
        end()
        for (timing in ReminderTiming.entries) {
            attempt { cancelReminder(PlannedNotification.identifier(entry.key, entry.date, timing)) }
        }
        return saved
    }

    /** Som `try?` i Swift: sant när steget gick bra. Ett avbrott av korutinen släpps igenom. */
    private inline fun attempt(step: () -> Unit): Boolean = try {
        step()
        true
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        false
    }
}
