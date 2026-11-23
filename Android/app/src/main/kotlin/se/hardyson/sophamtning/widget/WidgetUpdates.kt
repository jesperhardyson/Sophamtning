package se.hardyson.sophamtning.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetManager.Companion.SET_WIDGET_PREVIEWS_RESULT_SUCCESS
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import androidx.core.content.edit
import androidx.glance.appwidget.updateAll
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.reminders.ReceiverWork
import se.hardyson.sophamtning.tile.PlaceOutTileService

/**
 * När widgetarna och rutan i snabbinställningarna ritas om: när schemat, Utställt eller huvudadressen ändras, och vid midnatt i Stockholm, så att "i morgon"
 * blir "i dag" utan att appen öppnas.
 *
 * Midnatten är ett alarm och inte widgetens egen period (`updatePeriodMillis`), som går högst var 30:e minut och inte kan
 * läggas på en viss tid. Alarmet väcker inte telefonen: står den i viloläge vid midnatt ritas widgeten om när skärmen tänds,
 * vilket är först när någon kan se den. Systemet glömmer alarmet vid omstart, så det läggs in igen tillsammans med
 * påminnelserna, och även vid ändrad tid eller tidszon.
 */
object WidgetUpdates {
    private val _version = MutableStateFlow(0)

    /** Ökar varje gång widgetarna ska läsa om lagringen. Widgeten som visas läser om när värdet ändras. */
    val version: StateFlow<Int> = _version.asStateFlow()

    /** Ändringar som kommer så här tätt ger en enda omritning. */
    private val BURST: Duration = Duration.ofMillis(300)

    /** Hur långt efter midnatt alarmet får komma, när appen inte får använda exakta alarm. */
    private val window: Duration = Duration.ofMinutes(10)

    /** Ritar om widgetarna från det som är sparat nu, utan att vänta. */
    fun requestUpdate(context: Context, scope: CoroutineScope) {
        scope.launch { updateNow(context) }
    }

    /**
     * Ber widgetarna och rutan läsa om lagringen nu. Funktionen väntar tills Glance har tagit emot omritningen för varje
     * widget, men inte tills hemskärmen har visat den: den ritas av Glance i en egen session efteråt. För mottagare och
     * bakgrundsarbete, så att begäran är gjord innan processen kan frysas.
     */
    suspend fun updateNow(context: Context) {
        _version.update { it + 1 }
        // Rutan i snabbinställningarna läser samma lagring.
        PlaceOutTileService.requestUpdate(context.applicationContext)
        try {
            NextPickupWidget().updateAll(context.applicationContext)
        } catch (e: IllegalStateException) {
            Log.w(TAG, "Widgetarna kunde inte ritas om", e)
        }
    }

    /**
     * Lägger widgetens förhandsvisning i widgetgalleriet, från Android 15, en gång per version av appen. Systemet tillåter
     * bara några få sådana anrop i timmen.
     */
    fun publishPreview(context: Context, scope: CoroutineScope, version: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (preferences.getInt(PREVIEW_VERSION, -1) == version) return
        scope.launch {
            try {
                val published = GlanceAppWidgetManager(context).setWidgetPreviews(NextPickupWidgetReceiver::class)
                if (published == SET_WIDGET_PREVIEWS_RESULT_SUCCESS) preferences.edit { putInt(PREVIEW_VERSION, version) }
            } catch (e: Exception) {
                Log.w(TAG, "Förhandsvisningen kunde inte läggas in", e)
            }
        }
    }

    /**
     * Ritar om widgetarna när det de visar ändras i appens tillstånd: adresserna (och därmed huvudadressen), scheman och
     * Utställt. Också en gång direkt, så att en widget som missat något, till exempel en midnatt, stämmer när processen startar.
     */
    @OptIn(FlowPreview::class)
    fun observe(model: AppModel, context: Context, scope: CoroutineScope) {
        scope.launch {
            model.state
                .map { Triple(it.addresses, it.schedules, it.ownPlacedOut) }
                .distinctUntilChanged()
                // En hämtning av flera adresser ändrar tillståndet flera gånger i rad. Widgetarna ritas om en gång efteråt.
                .debounce(BURST.toMillis())
                .collectLatest { updateNow(context) }
        }
    }

    /** Om det finns någon widget på hemskärmen. */
    fun hasWidgets(context: Context): Boolean =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, NextPickupWidgetReceiver::class.java)).isNotEmpty()

    /**
     * Om något visar dagen och behöver alarmet vid midnatt: en widget, eller rutan i snabbinställningarna, som är aktiv och
     * bara ritas om när appen ber om det.
     */
    private fun needsMidnight(context: Context): Boolean = hasWidgets(context) || PlaceOutTileService.isAdded(context)

    /** Nästa midnatt i Stockholm efter [now]. */
    fun nextMidnight(now: Instant): Instant = StockholmClock.dateOn(StockholmClock.today(now).plusDays(1), 0)

    /** Lägger alarmet vid nästa midnatt i Stockholm, eller tar bort det när varken widget eller ruta finns. */
    fun armMidnight(context: Context, now: Instant = Instant.now()) {
        val manager = context.getSystemService(AlarmManager::class.java)
        if (!needsMidnight(context)) {
            manager.cancel(midnightIntent(context))
            return
        }
        val at = nextMidnight(now).toEpochMilli()
        val operation = midnightIntent(context)
        if (manager.canScheduleExactAlarms()) {
            manager.setExact(AlarmManager.RTC, at, operation)
        } else {
            manager.setWindow(AlarmManager.RTC, at, window.toMillis(), operation)
        }
    }

    internal fun midnightIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, MidnightReceiver::class.java).setAction(ACTION_MIDNIGHT),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private const val PREFERENCES = "widget"
    private const val PREVIEW_VERSION = "förhandsvisning"
    const val ACTION_MIDNIGHT = "se.hardyson.sophamtning.action.MIDNATT"
    private const val TAG = "Sophamtning"
}

/** Midnatt i Stockholm: widgetarna byter dag, och nästa midnatt läggs in. */
class MidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetUpdates.ACTION_MIDNIGHT) return
        WidgetUpdates.armMidnight(context)
        val pending = goAsync()
        ReceiverWork.launch(finish = pending::finish) { WidgetUpdates.updateNow(context) }
    }
}
