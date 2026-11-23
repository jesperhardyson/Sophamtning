package se.hardyson.sophamtning.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

/** Systemets mottagare för widgeten. Alarmet vid midnatt finns bara så länge någon widget ligger på hemskärmen. */
class NextPickupWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextPickupWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetUpdates.armMidnight(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Den sista widgeten är borta. Alarmet tas bort, om inte rutan i snabbinställningarna behöver det.
        WidgetUpdates.armMidnight(context)
    }
}
