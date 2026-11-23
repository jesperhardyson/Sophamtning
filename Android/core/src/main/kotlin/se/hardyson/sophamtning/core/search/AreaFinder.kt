package se.hardyson.sophamtning.core.search

import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.schedule.LatestOnly

/**
 * Modellen bakom arket "När tömdes ditt kärl senast?". Kalendern ändrar bara ett utkast. Först [find] frågar API:t,
 * och ett gammalt svar ersätter aldrig ett nyare.
 *
 * Anropen görs i [scope], som ska köra på en tråd (huvudtråden i appen), som `@MainActor` på iOS. Metoderna anropas
 * från samma tråd.
 */
class AreaFinder(
    private val api: SoporApi,
    private val place: String,
    private val scope: CoroutineScope,
    private val now: () -> Instant = Instant::now,
) {
    /** Allt som arket visar, som ett oföränderligt värde. */
    data class Snapshot(
        val state: AreaFinderState,
        /** Datumet som senast frågades efter. `null` tills användaren tryckt Hitta område, så ingen fråga ställs och inget område gissas. */
        val date: DayDate?,
        /** Utkastet i kalendern. Börjar på i dag, men ändrar inget och frågar inget. */
        val draft: DayDate,
        /** Falskt efter `400`: samma datum ger samma svar, så det finns inget att försöka igen. */
        val retryable: Boolean,
        /** Sant när en källa inte svarade men träffar ändå visas. Fler områden kan finnas. */
        val partial: Boolean,
    )

    private val _snapshot = MutableStateFlow(
        Snapshot(state = AreaFinderState.Idle, date = null, draft = StockholmClock.today(now()), retryable = true, partial = false),
    )
    val snapshot: StateFlow<Snapshot> = _snapshot.asStateFlow()

    val state: AreaFinderState get() = _snapshot.value.state
    val date: DayDate? get() = _snapshot.value.date
    val draft: DayDate get() = _snapshot.value.draft
    val retryable: Boolean get() = _snapshot.value.retryable
    val partial: Boolean get() = _snapshot.value.partial

    private val latest = LatestOnly()
    private var task: Job? = null

    /** Senast valbara dag: i dag i Stockholm. Framtida tömningar finns inte. */
    val latestSelectable: DayDate get() = StockholmClock.today(now())

    /** Ändrar utkastet. Resultatet för förra datumet tas bort, och inget frågas förrän [find]. */
    fun setDraft(day: DayDate) {
        val limited = minOf(day, latestSelectable)
        if (limited == draft) return
        _snapshot.update { it.copy(draft = limited) }
        if (date == null || date == limited) return
        task?.cancel()
        task = null
        _snapshot.update { it.copy(date = null, state = AreaFinderState.Idle, retryable = true, partial = false) }
    }

    /** Hitta område: frågar efter utkastets dag. Dagen begränsas till i dag, räknat nu. */
    fun find() {
        val day = minOf(draft, latestSelectable)
        _snapshot.update { it.copy(draft = day, date = day) }
        load()
    }

    /** Sätter utkastet och frågar direkt. */
    fun find(day: DayDate) {
        setDraft(day)
        find()
    }

    /** Frågar igen med samma datum. Utan valt datum görs ingenting. */
    fun retry() = load()

    fun cancel() {
        task?.cancel()
        task = null
    }

    private data class Outcome(val state: AreaFinderState, val retryable: Boolean = true, val partial: Boolean = false)

    private fun load() {
        val day = date ?: return
        task?.cancel()
        _snapshot.update { it.copy(state = AreaFinderState.Searching, retryable = true, partial = false) }
        task = scope.launch {
            val outcome: Outcome? = try {
                latest.run {
                    val response = api.areas(place, day)
                    Outcome(
                        state = AreaFinderState.from(response),
                        partial = response.addresses.isNotEmpty() && response.failed.isNotEmpty(),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Alla tekniska fel är "kunde inte kontrollera", aldrig "ingen hämtning".
                Outcome(state = AreaFinderState.Failed, retryable = e != ApiError.BadRequest)
            }
            // `null`: ett nyare anrop har startat. Avbruten: datumet ändrades igen.
            if (outcome == null || !isActive) return@launch
            _snapshot.update { it.copy(state = outcome.state, retryable = outcome.retryable, partial = outcome.partial) }
        }
    }
}
