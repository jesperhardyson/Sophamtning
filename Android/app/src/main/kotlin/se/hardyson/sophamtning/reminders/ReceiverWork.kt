package se.hardyson.sophamtning.reminders

import android.util.Log
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Arbetet som mottagarna gör efter `goAsync()`, på huvudtråden där appens modell hör hemma. */
object ReceiverWork {
    /** Mottagaren har ungefär tio sekunder på sig. Arbetet avbryts före det, och nästa planering rättar det som återstår. */
    private const val TIME_LIMIT_MILLIS = 8_000L

    /**
     * Kör [work] och anropar sedan alltid [finish]. Ett fel loggas och kraschar aldrig appen: mottagaren körs utan att
     * appen syns, och nästa planering rättar det som inte blev gjort.
     */
    fun launch(finish: () -> Unit, work: suspend () -> Unit) {
        val logged = CoroutineExceptionHandler { _, error -> Log.w(TAG, "Arbetet i mottagaren misslyckades", error) }
        CoroutineScope(SupervisorJob() + Dispatchers.Main + logged).launch {
            try {
                withTimeoutOrNull(TIME_LIMIT_MILLIS) { work() }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Arbetet i mottagaren misslyckades", e)
            } finally {
                finish()
            }
        }
    }

    private const val TAG = "Sophamtning"
}
