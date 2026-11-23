package se.hardyson.sophamtning

import androidx.annotation.VisibleForTesting
import android.app.Application
import android.content.Context
import io.ktor.client.engine.okhttp.OkHttp
import java.io.File
import java.time.Instant
import kotlinx.coroutines.MainScope
import se.hardyson.sophamtning.core.app.AppModel
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
        val permission = NotificationPermission(this)
        val model = AppModel(
            api = api,
            store = store,
            notifications = AndroidNotifications(this, store, permission),
            liveActivities = AndroidLiveUpdates(this, store),
            clock = clock,
            scope = MainScope(),
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
    }

    companion object {
        /** Katalogen för `LocalStore`, där också det schemalagda sparas. */
        fun storeDirectory(context: Context): File = File(context.filesDir, "Sophamtning")
    }
}
