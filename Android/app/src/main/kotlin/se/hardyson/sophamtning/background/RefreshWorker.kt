package se.hardyson.sophamtning.background

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.app.BackgroundRefreshRun

/**
 * Bakgrundshämtningen, som `BGAppRefreshTask` på iOS. Körs några gånger per dygn när nätet finns, och följer
 * [BackgroundRefreshRun]: varje adress hämtas högst en gång i timmen, ett nytt meddelande från källan ger en notis och
 * påminnelserna planeras om. På Android får en Live Update startas här, eftersom den är ett alarm och en notis.
 */
class RefreshWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val model = (applicationContext as SophamtningApplication).dependencies.model
        // Modellen hör till huvudtråden, som på iOS.
        withContext(Dispatchers.Main) { BackgroundRefreshRun(model, startingActivities = true).run() }
        return Result.success()
    }

    companion object {
        /**
         * Lägger in det periodiska arbetet en gång. Ett arbete som redan finns behålls, så att perioden inte börjar om varje
         * gång appen startas. Första körningen kommer efter en period, eftersom appen själv hämtar när den öppnas.
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RefreshWorker>(BackgroundRefreshRun.INTERVAL)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setInitialDelay(BackgroundRefreshRun.INTERVAL)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(BackgroundRefreshRun.UNIQUE_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
