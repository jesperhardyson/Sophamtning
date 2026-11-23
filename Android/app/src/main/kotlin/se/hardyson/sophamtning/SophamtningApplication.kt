package se.hardyson.sophamtning

import androidx.annotation.VisibleForTesting
import android.app.Application
import io.ktor.client.engine.okhttp.OkHttp
import java.io.File
import java.time.Instant
import kotlinx.coroutines.MainScope
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.api.SoporClient
import se.hardyson.sophamtning.core.kommun.PlaceIndex
import se.hardyson.sophamtning.core.reminders.DisabledLiveActivities
import se.hardyson.sophamtning.core.reminders.DisabledNotifications
import se.hardyson.sophamtning.core.storage.LocalStore

/** Skapar nätet, lagringen och appens tillstånd en gång för hela processen. */
class SophamtningApplication : Application() {
    /** Sätts i `onCreate`. Testerna som startar `MainActivity` sätter sina egna innan aktiviteten skapas. */
    @set:VisibleForTesting
    lateinit var dependencies: AppDependencies

    override fun onCreate() {
        super.onCreate()
        val api = SoporClient(OkHttp.create(), BuildConfig.VERSION_NAME)
        val clock = { Instant.now() }
        val model = AppModel(
            api = api,
            store = LocalStore(File(filesDir, "Sophamtning")),
            // Android-lagret för påminnelserna kopplas in i nästa steg. Tills dess schemaläggs inget och de visas inte.
            notifications = DisabledNotifications,
            liveActivities = DisabledLiveActivities,
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
        )
    }
}
