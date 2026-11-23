package se.hardyson.sophamtning

import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.AreaSource
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID
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
    /** Områdena som visas i områdesvalet, i minnet. Backstacken sparar bara deras id. */
    val heldAreas: HeldAreas = HeldAreas(),
    /** Innehållet i `CHANGELOG.md` som följer med appen, eller `null` när filen inte finns, som före den första releasen. */
    val changelog: () -> String? = { null },
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
