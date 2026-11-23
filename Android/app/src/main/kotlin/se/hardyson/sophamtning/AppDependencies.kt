package se.hardyson.sophamtning

import androidx.compose.runtime.staticCompositionLocalOf
import java.time.Instant
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.kommun.PlaceIndex

/**
 * Det skärmarna behöver: appens tillstånd, API:t och klockan. Skapas en gång i [SophamtningApplication], och testerna
 * ger skärmarna sina egna med ett falskt API, en fast klocka och en tillfällig katalog. Inget DI-ramverk.
 */
class AppDependencies(
    val model: AppModel,
    val api: SoporApi,
    val clock: () -> Instant,
    /** Ortlistan för kommunfrågan, eller `null` när den inte går att läsa. */
    val placeIndex: () -> PlaceIndex?,
)

val LocalAppDependencies = staticCompositionLocalOf<AppDependencies> { error("AppDependencies saknas") }
