package se.hardyson.sophamtning.core.schedule

import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.SavedAddress

sealed interface RefreshOutcome {
    /** Nytt svar hämtat och sparat. */
    data object Fetched : RefreshOutcome

    /** Ingen hämtning gjordes: för tidigt enligt `RefreshPolicy`, eller anropet avbröts. */
    data object Skipped : RefreshOutcome

    /** API-anropet misslyckades. Försöket är sparat, och det tidigare svaret är kvar. */
    data class Failed(val error: ApiError) : RefreshOutcome

    /** Svaret hämtades men gick inte att spara. */
    data object StorageFailed : RefreshOutcome
}

/** Samtidiga anrop för samma adress hanteras inte här, utan av den som anropar. */
class ScheduleRefresher(private val api: SoporApi, private val store: LocalStore) {
    suspend fun refresh(address: SavedAddress, now: Instant, manual: Boolean): RefreshOutcome {
        val existing = store.schedule(address.key)
        if (!RefreshPolicy.canFetch(existing, now, manual)) return RefreshOutcome.Skipped

        val failure: ApiError = try {
            val response = api.address(address.url)
            return try {
                store.setSchedule(CachedSchedule(response, fetchedAt = now, lastAttemptAt = now, lastError = null), address.key)
                RefreshOutcome.Fetched
            } catch (_: Exception) {
                RefreshOutcome.StorageFailed
            }
        } catch (_: CancellationException) {
            // Ett avbrutet anrop är inget misslyckat försök.
            return RefreshOutcome.Skipped
        } catch (e: ApiError) {
            e
        } catch (_: Exception) {
            // Klienten kastar bara ApiError och avbrott. Något annat är oväntat och har ingen statuskod.
            ApiError.Unexpected(0)
        }

        // Sparat svar och `fetchedAt` lämnas orörda. Bara försöket noteras.
        val schedule = (existing ?: CachedSchedule()).copy(lastAttemptAt = now, lastError = failure)
        return try {
            store.setSchedule(schedule, address.key)
            RefreshOutcome.Failed(failure)
        } catch (_: Exception) {
            RefreshOutcome.StorageFailed
        }
    }
}
