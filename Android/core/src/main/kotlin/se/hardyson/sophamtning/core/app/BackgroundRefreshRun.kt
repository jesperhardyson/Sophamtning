package se.hardyson.sophamtning.core.app

import java.time.Duration

/**
 * En körning av bakgrundshämtningen, som `BackgroundRefreshRun` på iOS. Logiken ligger här så att den går att testa på JVM,
 * och appens arbete i WorkManager kör den.
 *
 * Körningen hämtar scheman enligt `RefreshPolicy` (`refreshAll(manual = false)`), så att regeln om en hämtning per timme
 * gäller, räknar nya meddelanden från källan som `Background`, planerar om påminnelserna och laddar om widgeten. Avbryts
 * den, för att systemet säger att tiden är slut, laddas widgeten ändå om och avbrottet släpps vidare.
 *
 * WorkManager bokar nästa körning själv, så den delen av iOS-versionen finns inte här.
 */
class BackgroundRefreshRun(
    private val model: AppModel,
    /** Om en Live Update får startas. På iOS aldrig i bakgrunden. På Android går det, eftersom den är ett alarm och en notis. */
    private val startingActivities: Boolean,
    /** Laddar om widgeten, som läser från lagringen. */
    private val reloadWidgets: () -> Unit = {},
) {
    suspend fun run() {
        try {
            model.refreshAll(manual = false, startingActivities = startingActivities, context = RefreshContext.Background)
            model.applyReminders(startingActivities)
            model.settleReminders()
        } finally {
            reloadWidgets()
        }
    }

    companion object {
        /** Namnet på det unika periodiska arbetet. */
        const val UNIQUE_NAME = "se.hardyson.sophamtning.refresh"

        /** Hur ofta arbetet körs. Systemet bestämmer själv exakt när. */
        val INTERVAL: Duration = Duration.ofHours(3)
    }
}
