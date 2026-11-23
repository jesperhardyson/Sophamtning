package se.hardyson.sophamtning.core.schedule

import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException

/**
 * Låter bara det senast startade arbetet lämna ett svar. Ett äldre arbete som blir klart efter att ett nyare startat får
 * `null`, så att ett gammalt svar aldrig ersätter ett nyare.
 */
class LatestOnly {
    private val latest = AtomicInteger(0)

    /** Ger `null` om ett nyare anrop har startat medan det här pågick. Fel från ett omsprunget anrop kastas inte. */
    suspend fun <T> run(work: suspend () -> T): T? {
        val mine = latest.incrementAndGet()
        return try {
            val value = work()
            if (mine == latest.get()) value else null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (mine != latest.get()) null else throw e
        }
    }
}
