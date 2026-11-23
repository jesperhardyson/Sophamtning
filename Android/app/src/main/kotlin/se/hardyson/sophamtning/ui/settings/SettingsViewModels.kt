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
import se.hardyson.sophamtning.core.storage.ReminderTiming

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
    private val clock = dependencies.clock

    fun now() = clock()

    private val model = dependencies.model
    val state = model.state

    fun clearStorageError() = model.clearStorageError()

    fun setSourceMessages(on: Boolean) {
        model.clearStorageError()
        model.setSourceMessages(on)
    }

    /** Live Update är en notis på Android, så frågan om notiser ställs när den slås på och tillståndet inte är avgjort. */
    fun setLiveActivity(on: Boolean) {
        model.clearStorageError()
        viewModelScope.launch { model.setLiveUpdate(on) }
    }

    /** Påminn mig för en adress. Frågan om tillstånd ställs av modellen, bara när valet slås på. */
    fun setNotifications(key: AddressKey, on: Boolean) {
        model.clearStorageError()
        viewModelScope.launch { model.setNotifications(on, key) }
    }

    fun setReminder(timing: ReminderTiming, on: Boolean) {
        model.clearStorageError()
        model.setReminder(timing, on)
    }

    fun setReminderMinutes(minutes: Int, timing: ReminderTiming) {
        model.clearStorageError()
        model.setReminderMinutes(minutes, timing)
    }

    fun setLiveActivityTiming(timing: ReminderTiming) {
        model.clearStorageError()
        model.setLiveActivityTiming(timing)
    }

    fun setLiveActivityMinutes(minutes: Int) {
        model.clearStorageError()
        model.setLiveActivityMinutes(minutes)
    }

    fun setPrimary(key: AddressKey) {
        model.clearStorageError()
        model.setPrimary(key)
    }
}
