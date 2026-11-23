package se.hardyson.sophamtning.ui.home

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
import se.hardyson.sophamtning.core.app.AppState
import se.hardyson.sophamtning.core.app.visibleSourceMessages
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.messages.ActiveSourceMessage
import se.hardyson.sophamtning.core.storage.AddressKey

/**
 * Hemskärmen, som HomeView.swift. Allt räknas från appens tillstånd och tiden [now], som räknas om när skärmen visas
 * och varje minut medan den syns, så att "i dag" och "i morgon" stämmer efter midnatt.
 */
class HomeViewModel(private val dependencies: AppDependencies) : ViewModel() {
    data class Ui(
        val state: AppState,
        val content: HomeContent,
        val messages: List<ActiveSourceMessage>,
        val showsReminderOffer: Boolean,
        val now: Instant,
    )

    private val model = dependencies.model
    private val now = MutableStateFlow(dependencies.clock())

    val ui: StateFlow<Ui> = combine(model.state, now, ::make).stateIn(viewModelScope, SharingStarted.Eagerly, make(model.state.value, now.value))

    private fun make(state: AppState, now: Instant) = Ui(
        state = state,
        content = state.homeContent(now),
        messages = state.visibleSourceMessages(StockholmClock.today(now)),
        showsReminderOffer = state.showsReminderOffer(now),
        now = now,
    )

    /** Läser klockan igen. */
    fun tick() {
        now.value = dependencies.clock()
    }

    /** Ställer ut kärlen för nästa tömning, och svarar med om det gick. */
    fun placeOut(entry: HomeContent.Entry, onDone: (Boolean) -> Unit = {}) {
        val pickup = (entry.status as? HomeContent.Status.Upcoming)?.pickup ?: return
        viewModelScope.launch {
            model.clearStorageError()
            model.markPlacedOut(entry.key, pickup.date)
            onDone(model.state.value.lastStorageError == null)
        }
    }

    fun undoPlaceOut(entry: HomeContent.Entry) {
        val pickup = (entry.status as? HomeContent.Status.Upcoming)?.pickup ?: return
        viewModelScope.launch {
            model.clearStorageError()
            model.undoPlacedOut(entry.key, pickup.date)
        }
    }

    fun remove(key: AddressKey) {
        model.clearStorageError()
        model.remove(key)
    }

    fun dismissMessage(item: ActiveSourceMessage) = model.dismissSourceMessage(item)

    /** "Påminn mig" i förslaget. Frågan om tillstånd ställs av modellen, bara när valet slås på. */
    fun acceptReminderOffer(key: AddressKey) {
        model.clearStorageError()
        viewModelScope.launch { model.setNotifications(true, key) }
    }

    fun declineReminderOffer() = model.dismissReminderOffer()

    fun clearStorageError() = model.clearStorageError()

    fun retryStorage() = model.retryStorage()

    fun startOver() {
        model.clearStorageError()
        viewModelScope.launch { model.startOver() }
    }

    /** Dra för att uppdatera. */
    suspend fun refresh() {
        model.refreshAll(manual = true)
        tick()
    }
}
