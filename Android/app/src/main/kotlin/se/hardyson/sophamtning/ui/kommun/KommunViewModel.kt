package se.hardyson.sophamtning.ui.kommun

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.kommun.KommunAnswer
import se.hardyson.sophamtning.core.kommun.KommunChecker
import se.hardyson.sophamtning.core.kommun.shortKommunName
import se.hardyson.sophamtning.core.schedule.LatestOnly

/** "Finns min kommuns hämtningsschema?", som KommunCheckView.swift. Svaret kommer medan man skriver. */
class KommunViewModel(private val dependencies: AppDependencies, private val handle: SavedStateHandle) : ViewModel() {
    /** Svaret och, för en täckt kommun, områdena och källorna som `/omraden` gav. */
    data class Result(val answer: KommunAnswer, val areas: List<SearchHit> = emptyList(), val areaSources: List<AreaSource> = emptyList())

    data class Ui(
        /** Det senaste svaret. Det ligger kvar medan ett nytt hämtas, så att rutan inte blinkar. */
        val result: Result = Result(KommunAnswer.Empty),
        val updating: Boolean = false,
    )

    val query: StateFlow<String> = handle.getStateFlow(QUERY, "")
    private val attempt = MutableStateFlow(0)
    private val _ui = MutableStateFlow(Ui())
    val ui: StateFlow<Ui> = _ui.asStateFlow()
    private val latest = LatestOnly()

    init {
        viewModelScope.launch { combine(query, attempt) { text, _ -> text }.collectLatest { update(it) } }
    }

    fun setQuery(text: String) {
        handle[QUERY] = text
    }

    fun retry() = attempt.update { it + 1 }

    private suspend fun update(query: String) {
        val text = query.trim()
        if (text.codePointCount(0, text.length) < 2) {
            _ui.value = Ui()
            return
        }
        _ui.update { it.copy(updating = true) }
        // Väntar tills användaren slutat skriva. Ett nytt tangenttryck avbryter.
        delay(DEBOUNCE_MILLIS)
        val index = dependencies.placeIndex()
        if (index == null) {
            _ui.value = Ui(Result(KommunAnswer.Unavailable))
            return
        }
        val model = dependencies.model
        val api = dependencies.api
        val outcome = try {
            latest.run {
                val sources = model.sourceList()
                when (val answer = KommunChecker.check(text, index, sources)) {
                    is KommunAnswer.Covered -> {
                        // Misslyckas anropet erbjuds adresssökning i stället för områdesval.
                        val response = try {
                            api.areas(shortKommunName(answer.row.name))
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                            null
                        }
                        Result(answer, response?.addresses ?: emptyList(), response?.sources ?: emptyList())
                    }
                    else -> Result(answer)
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            Result(KommunAnswer.Unavailable)
        } ?: return
        _ui.value = Ui(outcome)
    }

    companion object {
        private const val QUERY = "query"
        const val DEBOUNCE_MILLIS = 200L
    }
}
