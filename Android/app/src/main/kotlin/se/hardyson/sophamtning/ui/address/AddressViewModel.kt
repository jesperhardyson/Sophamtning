package se.hardyson.sophamtning.ui.address

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.app.AppState
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.PermissionResult
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.ui.search.sourceName

/** Adressvyn och Hela schemat för en adress, som AddressView.swift och FullScheduleView. */
class AddressViewModel(private val dependencies: AppDependencies, val key: AddressKey) : ViewModel() {
    data class Ui(
        val state: AppState,
        /** `null` när adressen inte finns längre, eller adresserna inte går att läsa. */
        val detail: AddressDetail?,
        /** Källistan för kortet om källan, eller `null` tills den har hämtats. */
        val sources: List<Source>?,
        val notificationsDenied: Boolean,
        val remindersOn: Boolean,
    )

    private val model = dependencies.model
    private val now = MutableStateFlow(dependencies.clock())
    private val sources = MutableStateFlow<List<Source>?>(null)

    val ui: StateFlow<Ui> = combine(model.state, now, sources, ::make)
        .stateIn(viewModelScope, SharingStarted.Eagerly, make(model.state.value, now.value, null))

    init {
        viewModelScope.launch { sources.value = model.sourceList() }
    }

    private fun make(state: AppState, now: Instant, sources: List<Source>?): Ui {
        val address = state.address(key)
        val detail = address?.let {
            AddressDetail.make(
                address = it,
                schedule = state.schedules[key],
                settings = state.settings,
                sourceName = sources?.let { list -> sourceName(key.source, list) },
                now = now,
                remindersOn = state.remindersOn(it),
                ownPlacedOut = state.ownPlacedOut,
                placedOutTimes = state.placedOutTimes,
            ).let(state::withoutUnavailableReminders)
        }
        return Ui(
            state = state,
            detail = detail,
            sources = sources,
            notificationsDenied = state.notificationAuthorization == NotificationAuthorization.Denied,
            remindersOn = address?.let(state::remindersOn) ?: false,
        )
    }

    fun tick() {
        now.value = dependencies.clock()
    }

    suspend fun refresh() {
        model.refreshAll(manual = true)
        tick()
    }

    fun retry() {
        viewModelScope.launch { refresh() }
    }

    fun setPrimary() {
        model.clearStorageError()
        model.setPrimary(key)
    }

    /** Tar bort adressen, och svarar med om den är borta. Gick det inte att spara är den kvar, och felet visas. */
    fun remove(): Boolean {
        model.clearStorageError()
        model.remove(key)
        return model.state.value.address(key) == null
    }

    fun clearStorageError() = model.clearStorageError()

    /** Reglaget Påminn mig. [onDenied] körs när systemet nekar notiser. */
    fun setNotifications(on: Boolean, onDenied: () -> Unit) {
        model.clearStorageError()
        viewModelScope.launch {
            if (model.setNotifications(on, key) == PermissionResult.Denied) onDenied()
        }
    }

    fun setLiveActivity(on: Boolean) {
        model.clearStorageError()
        model.setLiveActivity(on)
    }

    fun placeOut() {
        val date = ui.value.detail?.next?.date ?: return
        viewModelScope.launch {
            model.clearStorageError()
            model.markPlacedOut(key, date)
        }
    }

    fun undoPlaceOut() {
        val date = ui.value.detail?.next?.date ?: return
        viewModelScope.launch {
            model.clearStorageError()
            model.undoPlacedOut(key, date)
        }
    }
}
