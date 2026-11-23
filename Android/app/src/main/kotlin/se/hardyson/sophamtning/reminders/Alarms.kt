package se.hardyson.sophamtning.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import java.time.Instant

/**
 * Alarmen för påminnelserna och Live Update. Får appen använda exakta alarm kommer de på minuten. Annars används ett inexakt
 * alarm från vald tid, som också går när telefonen vilar (Doze). Det kommer oftast inom några minuter, men kan bli senare
 * när telefonen har legat stilla länge. Appen begär aldrig exakta alarm själv: bara raden Exakta tider i inställningarna
 * öppnar systemets inställning.
 */
object Alarms {
    fun canScheduleExact(context: Context): Boolean = context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    /** Sätter alarmet. Alarmen är i UTC-tid, så en ändrad tidszon flyttar dem inte. */
    fun set(context: Context, at: Instant, operation: PendingIntent) {
        val manager = context.getSystemService(AlarmManager::class.java)
        if (manager.canScheduleExactAlarms()) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), operation)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), operation)
        }
    }

    fun cancel(context: Context, operation: PendingIntent) {
        context.getSystemService(AlarmManager::class.java).cancel(operation)
        operation.cancel()
    }
}
