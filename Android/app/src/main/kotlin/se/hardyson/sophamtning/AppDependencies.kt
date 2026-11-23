package se.hardyson.sophamtning

import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.AreaSource
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID
import androidx.compose.runtime.staticCompositionLocalOf
import java.time.Instant
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.plus
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.bin.ShownOnce
import se.hardyson.sophamtning.core.kommun.PlaceIndex
import se.hardyson.sophamtning.reminders.NotificationPermission

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
    /** Områdena som visas i områdesvalet, i minnet. Backstacken sparar bara deras id. */
    val heldAreas: HeldAreas = HeldAreas(),
    /** Innehållet i `CHANGELOG.md` som följer med appen, eller `null` när filen inte finns, som före den första releasen. */
    val changelog: () -> String? = { null },
    /** Kärlen som redan har spelat sitt första varv i den här processen, så att det inte spelas igen vid retur. */
    val binFirstRounds: ShownOnce<String> = ShownOnce(),
    /** Kalenderbladen som redan har bläddrats vid start i den här processen, så att det inte görs igen vid retur. */
    val calendarOpenings: ShownOnce<String> = ShownOnce(),
    /** Frågan om notiser, som aktiviteten kopplar in. `null` i testerna, där ingen fråga ställs. */
    val notificationPermission: NotificationPermission? = null,
    /**
     * Arbete som ska bli klart även om det som startade det försvinner, som ett tryck i rutan i snabbinställningarna.
     * Lever lika länge som processen. Ett fel loggas och kraschar inte appen.
     */
    val appScope: CoroutineScope = MainScope() + CoroutineExceptionHandler { _, error -> Log.w("Sophamtning", "Arbetet misslyckades", error) },
)

/**
 * Områden från `/omraden` eller sökningen, i minnet så länge processen lever. Backstacken sparas när appen läggs i
 * bakgrunden, och en lista med många områden kan bli för stor för det. Nycklarna har därför bara ett id hit. Efter att
 * appen dödats är minnet tomt, och skärmarna går då tillbaka till den skärm som hämtar områdena igen.
 */
class HeldAreas {
    data class Held(val hits: List<SearchHit>, val sources: List<AreaSource>)

    private val held = ConcurrentHashMap<String, Held>()

    /** Sparar områdena och svarar med ett kort id för backstacken. */
    fun put(hits: List<SearchHit>, sources: List<AreaSource> = emptyList()): String {
        val id = UUID.randomUUID().toString()
        held[id] = Held(hits, sources)
        return id
    }

    fun get(id: String): Held? = held[id]
}

val LocalAppDependencies = staticCompositionLocalOf<AppDependencies> { error("AppDependencies saknas") }
