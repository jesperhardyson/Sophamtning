package se.hardyson.sophamtning.core.app

import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.messages.ActiveSourceMessage
import se.hardyson.sophamtning.core.messages.SourceMessages

// Meddelanden från källan, som AppModel+SourceMessages.swift. Det som ändrar tillståndet (stänga, notera sedda och ge
// notiser) ligger i AppModel, eftersom det läser modellens privata fält.

/** Var `refreshAll` körs. Avgör om ett nytt meddelande från källan ger en notis. */
enum class RefreshContext {
    /** Appen är öppen. Ett nytt meddelande visas som kort och räknas som sett utan notis. */
    Foreground,

    /** Bakgrundshämtningen. Ett nytt meddelande ger en notis, om valet är på och systemet redan tillåter notiser. */
    Background,
}

/** Meddelandena som gäller [today] för någon sparad adress och inte är stängda, för hemskärmen. */
fun AppState.visibleSourceMessages(today: DayDate): List<ActiveSourceMessage> =
    activeSourceMessages(today).filter { !sourceMessageMemory.isDismissed(it.key) }

/** Meddelandena som gäller [today] för någon sparad adress, stängda eller inte. */
internal fun AppState.activeSourceMessages(today: DayDate): List<ActiveSourceMessage> {
    val input = addresses.mapNotNull { address ->
        schedules[address.key]?.response?.let { address.key.source to it.messages }
    }
    return SourceMessages.active(input, today)
}
