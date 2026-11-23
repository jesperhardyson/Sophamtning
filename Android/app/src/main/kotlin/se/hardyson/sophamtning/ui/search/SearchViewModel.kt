package se.hardyson.sophamtning.ui.search

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.schedule.LatestOnly
import se.hardyson.sophamtning.core.search.AddressSearch
import se.hardyson.sophamtning.core.search.SearchOutcome
import se.hardyson.sophamtning.core.search.SearchState
import se.hardyson.sophamtning.core.storage.AddressKey

/**
 * "Lägg till adress", som SearchView.swift på iOS. Söktexten sparas i [SavedStateHandle], så att den finns kvar när
 * telefonen vrids eller appen dödas, och en ny sökning görs bara när texten ändras.
 */
class SearchViewModel(
    private val dependencies: AppDependencies,
    private val handle: SavedStateHandle,
    /** Begränsar sökningen till en källa, efter kommunfrågan. */
    private val presetSource: String?,
) : ViewModel() {
    data class Ui(
        val outcome: SearchOutcome = SearchOutcome(SearchState.Idle, areas = null),
        /** Sant medan ett nytt svar hämtas. Gamla träffar tonas ned och går inte att trycka på. */
        val updating: Boolean = false,
        val sources: List<Source>? = null,
        val saveFailed: Boolean = false,
    )

    val query: StateFlow<String> = handle.getStateFlow(QUERY, "")
    private val attempt = MutableStateFlow(0)
    private val _ui = MutableStateFlow(Ui())
    val ui: StateFlow<Ui> = _ui.asStateFlow()
    private val latest = LatestOnly()
    private val latestAreas = LatestOnly()

    init {
        viewModelScope.launch {
            combine(query, attempt) { text, _ -> text }.collectLatest { search(it) }
        }
    }

    fun setQuery(text: String) {
        handle[QUERY] = text
        _ui.update { it.copy(saveFailed = false) }
    }

    fun retry() = attempt.update { it + 1 }

    private suspend fun search(query: String) {
        val text = query.trim()
        // Minst tre tecken innan /sok anropas.
        if (text.codePointCount(0, text.length) < 3) {
            _ui.update { it.copy(outcome = SearchOutcome(SearchState.Idle, areas = null), updating = false) }
            return
        }
        _ui.update { it.copy(updating = true) }
        delay(DEBOUNCE_MILLIS)
        // Gamla träffar ligger kvar medan ett nytt svar hämtas. Bara en tom eller felande ruta byts mot "söker".
        when (_ui.value.outcome.state) {
            SearchState.Idle, is SearchState.Failed, is SearchState.SourcesFailed, is SearchState.NoHits ->
                _ui.update { it.copy(outcome = SearchOutcome(SearchState.Searching, areas = null)) }
            SearchState.Searching, is SearchState.Results -> {}
        }
        AddressSearch.run(text, presetSource, dependencies.api, latest, latestAreas) { result ->
            _ui.update { it.copy(outcome = result, updating = false) }
        }
        // Källnamnen behövs bara för texterna, så träffarna visas utan att vänta på /kallor.
        val names = dependencies.model.sourceList()
        _ui.update { it.copy(sources = names) }
    }

    /** Sparar en adress och svarar med nyckeln. Ett område sparas först i bekräftelsen, så då svarar den `null`. */
    fun save(hit: SearchHit): AddressKey? {
        val key = dependencies.model.save(hit)
        _ui.update { it.copy(saveFailed = key == null) }
        return key
    }

    companion object {
        private const val QUERY = "query"
        const val DEBOUNCE_MILLIS = 300L
    }
}
