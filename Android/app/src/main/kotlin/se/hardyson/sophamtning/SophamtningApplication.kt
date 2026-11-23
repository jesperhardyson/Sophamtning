package se.hardyson.sophamtning

import android.app.Application
import io.ktor.client.engine.okhttp.OkHttp
import java.io.File
import java.time.Instant
import kotlinx.coroutines.MainScope
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.app.NoReminders
import se.hardyson.sophamtning.core.api.SoporClient
import se.hardyson.sophamtning.core.kommun.PlaceIndex
import se.hardyson.sophamtning.core.storage.LocalStore

/** Skapar nätet, lagringen och appens tillstånd en gång för hela processen. */
class SophamtningApplication : Application() {
    lateinit var dependencies: AppDependencies
        private set

    override fun onCreate() {
        super.onCreate()
        val api = SoporClient(OkHttp.create(), BuildConfig.VERSION_NAME)
        val clock = { Instant.now() }
        val model = AppModel(
            api = api,
            store = LocalStore(File(filesDir, "Sophamtning")),
            // Påminnelserna byggs i plan 5. Tills dess schemaläggs inget.
            reminders = NoReminders,
            clock = clock,
            scope = MainScope(),
            appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        )
        dependencies = AppDependencies(model, api, clock, placeIndex = { runCatching { PlaceIndex.load() }.getOrNull() })
    }
}
