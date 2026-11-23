package se.hardyson.sophamtning

import androidx.annotation.VisibleForTesting
import android.app.Application
import android.content.Context
import io.ktor.client.engine.okhttp.OkHttp
import java.io.File
import java.time.Instant
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.plus
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.background.RefreshWorker
import se.hardyson.sophamtning.core.api.SoporClient
import se.hardyson.sophamtning.core.kommun.PlaceIndex
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.reminders.AndroidLiveUpdates
import se.hardyson.sophamtning.reminders.AndroidNotifications
import se.hardyson.sophamtning.reminders.NotificationChannels
import se.hardyson.sophamtning.reminders.NotificationPermission

/** Skapar nätet, lagringen och appens tillstånd en gång för hela processen. */
class SophamtningApplication : Application() {
    /** Sätts i `onCreate`. Testerna som startar `MainActivity` sätter sina egna innan aktiviteten skapas. */
    @set:VisibleForTesting
    lateinit var dependencies: AppDependencies

    override fun onCreate() {
        super.onCreate()
        val api = SoporClient(OkHttp.create(), BuildConfig.VERSION_NAME)
        val clock = { Instant.now() }
        val store = LocalStore(storeDirectory(this))
        NotificationChannels.create(this)
        // Systemet kan ha glömt alarmen utan att säga till: efter tvångsstopp, eller när exakta alarm drogs in.
        runCatching { AndroidNotifications.rescheduleAll(this, store) }
        runCatching { AndroidLiveUpdates.rescheduleAll(this, store) }
        val permission = NotificationPermission(this)
        val model = AppModel(
            api = api,
            store = store,
            notifications = AndroidNotifications(this, store, permission),
            liveActivities = AndroidLiveUpdates(this, store),
            clock = clock,
            // Ett fel i en planering loggas och kraschar inte appen, som kan köras utan att synas, från ett alarm eller en
            // mottagare. Nästa planering försöker igen.
            scope = MainScope() + CoroutineExceptionHandler { _, error -> Log.w("Sophamtning", "Planeringen misslyckades", error) },
            appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        )
        dependencies = AppDependencies(
            model,
            api,
            clock,
            placeIndex = { runCatching { PlaceIndex.load() }.getOrNull() },
            // Nyheterna följer med appen, så sidan fungerar utan nät och stämmer med versionen som är installerad.
            changelog = { runCatching { assets.open("CHANGELOG.md").bufferedReader().use { it.readText() } }.getOrNull() },
            notificationPermission = permission,
        )
        scheduleBackgroundRefresh()
    }

    /**
     * Lägger in bakgrundshämtningen. WorkManager startas av appens startprovider innan `onCreate`, och utan den, som i
     * Robolectric-testerna, finns ingen bakgrundshämtning att lägga in.
     */
    private fun scheduleBackgroundRefresh() {
        try {
            RefreshWorker.schedule(this)
        } catch (_: IllegalStateException) {
        }
    }

    companion object {
        /** Katalogen för `LocalStore`, där också det schemalagda sparas. */
        fun storeDirectory(context: Context): File = File(context.filesDir, "Sophamtning")
    }
}
