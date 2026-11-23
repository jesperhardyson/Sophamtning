package se.hardyson.sophamtning.core.search

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.schedule.LatestOnly

/** Vad `/omraden` gav för orterna i söktexten. */
sealed interface AreaLookup {
    /** [place] är orten som gav områdena. [sources] är källorna som svarade, med förklaringen till områdesvalet. */
    data class Found(val place: String, val areas: List<SearchHit>, val sources: List<AreaSource> = emptyList()) : AreaLookup

    /** Ingen ort gav områden, och inget anrop misslyckades. */
    data object NotFound : AreaLookup

    /** Inga områden, och minst ett anrop misslyckades. Det betyder inte att kommunen saknar områdesval. */
    data object Failed : AreaLookup

    companion object {
        /** Högst så många anrop till `/omraden` per söktext. */
        const val maxCalls = 3

        /** Frågar `/omraden` för söktextens orter i ordning, tills någon ger områden. Kastar bara vid avbrott. */
        suspend fun run(query: String, api: SoporApi): AreaLookup = run(SearchState.placeCandidates(query), api)

        internal suspend fun run(candidates: List<String>, api: SoporApi): AreaLookup {
            var failed = false
            for (place in candidates.take(maxCalls)) {
                currentCoroutineContext().ensureActive()
                try {
                    val response = api.areas(place)
                    if (response.addresses.isNotEmpty()) return Found(place, response.addresses, response.sources)
                    if (response.failed.isNotEmpty()) failed = true
                } catch (e: CancellationException) {
                    throw e
                } catch (_: ApiError.BadRequest) {
                    // 400: orten gick inte att tolka. Inget tekniskt fel, bara inga områden för den.
                    continue
                } catch (_: Exception) {
                    currentCoroutineContext().ensureActive()
                    failed = true
                }
            }
            currentCoroutineContext().ensureActive()
            return if (failed) Failed else NotFound
        }

        /**
         * Träffarna som visas under raden Välj område, med sin plats i svaret. Områdesrader för en kommun vars områden redan
         * nås med raden göms, så att samma områden inte står två gånger. Utan områden visas alla träffar.
         */
        fun visibleHits(hits: List<SearchHit>, lookup: AreaLookup?): List<IndexedValue<SearchHit>> {
            val all = hits.withIndex().toList()
            if (lookup !is Found) return all
            val kommuner = lookup.areas.map { it.kommun }.toSet()
            return all.filter { !(it.value.isArea && it.value.kommun in kommuner) }
        }
    }
}

/** Ett svar från adressökningen. [areas] är `null` medan `/omraden` fortfarande frågas. */
data class SearchOutcome(val state: SearchState, val areas: AreaLookup?)

object AddressSearch {
    /**
     * Frågar `/sok` och, samtidigt, `/omraden` för orterna i söktexten. Träffarna lämnas direkt och väntar inte på
     * områdena, som lämnas i ett andra svar. Vid noll träffar lämnas ett enda svar när områdena är klara. Inget lämnas
     * efter avbrott, eller när ett nyare anrop har startat. [deliver] anropas i den anropande coroutinens kontext.
     */
    suspend fun run(
        query: String,
        source: String?,
        api: SoporApi,
        searches: LatestOnly,
        areaLookups: LatestOnly,
        deliver: (SearchOutcome) -> Unit,
    ) = coroutineScope {
        // `null` när ett nyare anrop har startat eller frågan misslyckades, som `try?` på iOS.
        val lookup = async {
            try {
                areaLookups.run { AreaLookup.run(query, api) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
        }
        try {
            val state = try {
                val response = searches.run { api.search(query, source) } ?: return@coroutineScope
                SearchState.from(response, query)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (!isActive) return@coroutineScope
                SearchState.Failed(e)
            } catch (_: Exception) {
                return@coroutineScope
            }
            if (!isActive) return@coroutineScope
            when (state) {
                is SearchState.Results -> {
                    deliver(SearchOutcome(state, areas = null))
                    val areas = lookup.await() ?: return@coroutineScope
                    if (!isActive) return@coroutineScope
                    deliver(SearchOutcome(state, areas))
                }
                is SearchState.NoHits -> {
                    val areas = lookup.await() ?: return@coroutineScope
                    if (!isActive) return@coroutineScope
                    deliver(SearchOutcome(state, areas))
                }
                SearchState.Idle, SearchState.Searching, is SearchState.SourcesFailed, is SearchState.Failed ->
                    deliver(SearchOutcome(state, areas = null))
            }
        } finally {
            // Som `async let` på iOS: en fråga som inte behövs längre avbryts.
            lookup.cancel()
        }
    }
}
