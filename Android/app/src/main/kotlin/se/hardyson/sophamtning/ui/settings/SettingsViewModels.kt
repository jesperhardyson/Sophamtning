package se.hardyson.sophamtning.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.storage.AddressKey

/**
 * Källistan för Inställningar och Datakällor, från `AppModel.sourceList()`. `null` är "okänt", aldrig "inga källor".
 * Testdata visas aldrig.
 */
class SourcesViewModel(private val dependencies: AppDependencies) : ViewModel() {
    data class Ui(val sources: List<Source>?, val loading: Boolean) {
        /** Källorna som visas, utan testdata. */
        val shown: List<Source>? get() = sources?.filter { !it.testData }
    }

    private val _ui = MutableStateFlow(Ui(null, loading = true))
    val ui: StateFlow<Ui> = _ui.asStateFlow()

    init {
        load()
    }

    /** Hämtar listan, också för Försök igen. */
    fun load() {
        _ui.value = _ui.value.copy(loading = true)
        viewModelScope.launch {
            val sources = dependencies.model.sourceList()
            _ui.value = Ui(sources, loading = false)
        }
    }
}

/** Valen i Inställningar som ändrar appens tillstånd. Går sparandet fel visas felet, och valet är kvar som förut. */
class SettingsViewModel(dependencies: AppDependencies) : ViewModel() {
    private val model = dependencies.model
    val state = model.state

    fun clearStorageError() = model.clearStorageError()

    fun setSourceMessages(on: Boolean) {
        model.clearStorageError()
        model.setSourceMessages(on)
    }

    fun setLiveActivity(on: Boolean) {
        model.clearStorageError()
        model.setLiveActivity(on)
    }

    fun setPrimary(key: AddressKey) {
        model.clearStorageError()
        model.setPrimary(key)
    }
}
