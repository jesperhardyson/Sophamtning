package se.hardyson.sophamtning.core.widget

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.schedule.FractionPickup
import se.hardyson.sophamtning.core.schedule.ScheduleEnding
import se.hardyson.sophamtning.core.schedule.ScheduleLogic
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.StoreRead

/**
 * Widgetens innehåll för huvudadressen, räknat från sparade adresser och schema och given tid. Allt räknas lokalt: dagar och
 * datum kommer aldrig från sparade `next`-fält, och lägena följer [HomeContent].
 */
sealed interface WidgetContent {
    /** Det finns inga sparade adresser. */
    data object NoAddress : WidgetContent

    /**
     * Filerna går inte att läsa just nu eller är skadade. Det är inte samma sak som att adressen saknas, så widgeten ber om
     * en senare uppdatering.
     */
    data object Unavailable : WidgetContent

    /** Schemat har inte hämtats än. */
    data class NoSchedule(val name: String) : WidgetContent

    /** Schemat saknas och det senaste försöket misslyckades av tekniska skäl. */
    data class Failed(val name: String) : WidgetContent

    /** Schemat saknas och källan svarade att adressen inte finns (404). */
    data class NotFound(val name: String) : WidgetContent

    /** Schemat finns men har inga hämtningar från och med i dag. */
    data class NoUpcoming(val name: String) : WidgetContent

    /**
     * Nästa hämtning. [relative] och [shortDate] gäller första datumet och har "ca" först när det är uppskattat. [fractions]
     * är första kommande datum per fraktion, sorterat på datum.
     */
    data class Pickup(val name: String, val relative: String, val shortDate: String, val fractions: List<FractionPickup>) : WidgetContent

    /** Raderna i den mellanstora widgeten, och hur många kärl samma dag som inte fick plats. */
    data class MediumRows(val rows: List<FractionPickup>, val hidden: Int)

    companion object {
        /** Efter ett läge utan läsbara filer försöker widgeten igen inom så här lång tid. */
        val unavailableRetryInterval: Duration = Duration.ofMinutes(15)

        fun make(addresses: List<SavedAddress>, schedule: CachedSchedule?, now: Instant): WidgetContent {
            val address = addresses.firstOrNull { it.isPrimary } ?: addresses.firstOrNull() ?: return NoAddress
            val name = address.displayName
            val today = StockholmClock.today(now)
            // Samma sanning som hemskärmen: läget kommer från HomeContent.
            val schedules = schedule?.let { mapOf(address.key to it) } ?: emptyMap()
            return when (val status = HomeContent.make(listOf(address), schedules, ReminderSettings(), now).primary?.status) {
                is HomeContent.Status.Upcoming -> {
                    val response = schedule?.response ?: return NoSchedule(name)
                    val pickup = status.pickup
                    val shortDate = SwedishFormat.shortDate(pickup.date)
                    Pickup(
                        name = name,
                        relative = SwedishFormat.estimated(SwedishFormat.relative(pickup.daysUntil), pickup.estimated),
                        shortDate = SwedishFormat.estimated(if (pickup.estimated) shortDate.lowercase() else shortDate, pickup.estimated),
                        fractions = ScheduleLogic.nextByFraction(response.events, today),
                    )
                }
                HomeContent.Status.NoUpcoming -> NoUpcoming(name)
                is HomeContent.Status.Failed -> if (status.error == ApiError.NotFound) NotFound(name) else Failed(name)
                HomeContent.Status.Loading, null -> NoSchedule(name)
            }
        }

        /**
         * "Schemat slutar 10 jan" när schemat tar slut inom 14 dagar, för huvudadressen. Bara när widgeten visar en kommande
         * hämtning, och aldrig för live-källor. Räknas från [now], så att raden försvinner av sig själv när dagarna går.
         */
        fun scheduleEnding(addresses: List<SavedAddress>, schedule: CachedSchedule?, now: Instant): ScheduleEnding? {
            if (make(addresses, schedule, now) !is Pickup) return null
            return ScheduleEnding.make(schedule?.response?.schedule, StockholmClock.today(now))
        }

        /**
         * Raderna i den mellanstora widgeten: bara kärlen som töms det datum som står på kalenderbladet, som i den lilla. Får de
         * inte plats blir sista raden "+N till", så `hidden` gäller alltid samma tömning och aldrig ett senare datum.
         */
        fun mediumRows(fractions: List<FractionPickup>, maxRows: Int): MediumRows {
            val first = fractions.firstOrNull() ?: return MediumRows(emptyList(), 0)
            val sameDay = fractions.filter { it.date == first.date }
            val rows = if (sameDay.size > maxRows) sameDay.take(maxRows - 1) else sameDay
            return MediumRows(rows, sameDay.size - rows.size)
        }

        /** Datumet för ett senare kärl i widgetens TalkBack-text: "mån 9 nov", eller "ca tors 12 nov" när det är uppskattat. */
        fun rowDate(pickup: FractionPickup): String = SwedishFormat.estimated(SwedishFormat.shortDate(pickup.date).lowercase(), pickup.estimated)

        /** Tidslinjens poster: [now] och sedan varje svensk midnatt, [days] stycken. Widgeten byter dag då och räknar om allt. */
        fun timelineDates(now: Instant, days: Int): List<Instant> {
            val today = StockholmClock.today(now)
            return listOf(now) + (0 until maxOf(days, 0)).map { StockholmClock.dateOn(today.plusDays(it + 1), 0) }
        }
    }
}

/**
 * Det widgeten läser från lagringen, en enda läsning per uppdatering. Skriver aldrig något. Utan hushåll är Utställt bara de
 * egna utställda i `placed-out.json`.
 */
class WidgetData private constructor(
    private val source: Source,
    /** De egna utställda. Går filen inte att läsa visas ingen bock. */
    private val ownPlacedOut: Set<PlacedOut> = emptySet(),
) {
    private sealed interface Source {
        data object Unavailable : Source
        data class Loaded(val addresses: List<SavedAddress>, val schedule: CachedSchedule?) : Source
    }

    /** Huvudadressen, som ett tryck på widgeten öppnar, eller `null` utan adresser eller när filerna inte går att läsa. */
    val primaryKey: AddressKey?
        get() = (source as? Source.Loaded)?.addresses?.let { list -> (list.firstOrNull { it.isPrimary } ?: list.firstOrNull())?.key }

    /** Fraktionernas namn och ikoner ur det sparade schemat. Okända id:n får reservvärden av `ScheduleLogic.displayInfo`. */
    val fractionInfo: Map<String, FractionInfo>
        get() = (source as? Source.Loaded)?.schedule?.response?.fractions ?: emptyMap()

    fun content(now: Instant): WidgetContent = when (source) {
        Source.Unavailable -> WidgetContent.Unavailable
        is Source.Loaded -> WidgetContent.make(source.addresses, source.schedule, now)
    }

    /** Raden om att schemat tar slut, eller `null`. */
    fun scheduleEnding(now: Instant): ScheduleEnding? = when (source) {
        Source.Unavailable -> null
        is Source.Loaded -> WidgetContent.scheduleEnding(source.addresses, source.schedule, now)
    }

    /** Sant när kärlen är utställda för huvudadressens nästa tömning. */
    fun placedOut(now: Instant): Boolean = nextPickup(now)?.let { it in ownPlacedOut } == true

    /**
     * Tömningen som knappen Ställ ut kärlen i den mellanstora widgeten markerar: huvudadressens nästa tömning när den är i
     * dag eller i morgon och inte redan är utställd. Annars `null`, och knappen visas inte.
     */
    fun placeOutEntry(now: Instant): PlacedOut? {
        val next = nextPickup(now) ?: return null
        if (placedOut(now) || StockholmClock.today(now).daysUntil(next.date) !in 0..1) return null
        return next
    }

    /** Huvudadressens nästa tömning, som tömning för en bock. */
    private fun nextPickup(now: Instant): PlacedOut? {
        val loaded = source as? Source.Loaded ?: return null
        val address = loaded.addresses.firstOrNull { it.isPrimary } ?: loaded.addresses.firstOrNull() ?: return null
        val events = loaded.schedule?.response?.events ?: return null
        val next = ScheduleLogic.nextPickup(events, StockholmClock.today(now))?.date ?: return null
        return PlacedOut(address.key, next)
    }

    /** Visningsinfo för en fraktion, med samma reservvärden som appen. */
    fun info(id: String): FractionInfo = ScheduleLogic.displayInfo(id, fractionInfo)

    /**
     * När widgeten ska läsa om själv: inom 15 minuter när filerna inte gick att läsa, annars `null` (då uppdateras den vid
     * midnatt och när appen sparar något).
     */
    fun reloadDate(now: Instant): Instant? = if (source == Source.Unavailable) now + WidgetContent.unavailableRetryInterval else null

    companion object {
        fun read(store: LocalStore): WidgetData {
            val addresses = when (val state = store.addressesState()) {
                StoreRead.Missing -> return WidgetData(Source.Loaded(emptyList(), null))
                is StoreRead.Value -> state.value
                // En fil som inte går att läsa eller tolka är inte "inga adresser".
                StoreRead.Unavailable, StoreRead.Unreadable -> return WidgetData(Source.Unavailable)
            }
            val address = addresses.firstOrNull { it.isPrimary } ?: addresses.firstOrNull()
                ?: return WidgetData(Source.Loaded(addresses, null))
            return when (val state = store.scheduleState(address.key)) {
                StoreRead.Missing -> WidgetData(Source.Loaded(addresses, null))
                is StoreRead.Value -> WidgetData(Source.Loaded(addresses, state.value), store.placedOut().toSet())
                StoreRead.Unavailable, StoreRead.Unreadable -> WidgetData(Source.Unavailable)
            }
        }
    }
}
