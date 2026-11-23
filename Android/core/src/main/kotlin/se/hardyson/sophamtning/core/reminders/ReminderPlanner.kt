package se.hardyson.sophamtning.core.reminders

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.graphemePrefix
import se.hardyson.sophamtning.core.schedule.ScheduleLogic
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.trimmedNonEmpty

/** En adress med sitt sparade schema, som indata till planeraren. */
data class PlannerAddress(val address: SavedAddress, val schedule: CachedSchedule?)

data class PlannerInput(
    val addresses: List<PlannerAddress>,
    val settings: ReminderSettings,
    val placedOut: Set<PlacedOut>,
    val now: Instant,
    val liveActivitiesAllowed: Boolean,
    /** Adress och datum för Live Updates som faktiskt finns hos systemet (väntande alarm eller pågående notis). Saknar standardvärde med avsikt. */
    val existingActivities: Set<PlacedOut>,
    /**
     * Adress och datum där Live Updaten bevisligen syntes. Då behövs ingen reservnotis. Saknar standardvärde med avsikt:
     * glöms den skickas en onödig andra påminnelse.
     */
    val shownActivities: Set<PlacedOut>,
    /** Live Updatens egna starttider, så att reserven räknas från den start som faktiskt gäller. Saknas en post används påminnelsetiden. */
    val activityStarts: Map<PlacedOut, Instant> = emptyMap(),
)

data class PlannedNotification(
    /** `"<key.fileName>-<iso-datum>"` för kvällen före och `"<key.fileName>-<iso-datum>-morgon"` för samma morgon. */
    val identifier: String,
    val fireDate: Instant,
    val title: String,
    val body: String,
    val key: AddressKey,
    val pickupDate: DayDate,
) {
    companion object {
        /** Identifieraren för adressens notis ett visst datum och val. Reservnotisen har samma som den vanliga för valet, så att den ersätter den. */
        fun identifier(key: AddressKey, date: DayDate, timing: ReminderTiming): String = when (timing) {
            ReminderTiming.EveningBefore -> "${key.fileName}-${date.iso}"
            ReminderTiming.SameMorning -> "${key.fileName}-${date.iso}-morgon"
        }
    }
}

data class PlannedLiveActivity(
    val key: AddressKey,
    val pickupDate: DayDate,
    /** Kvällen före tömningen eller samma morgon, på Live Updatens tid. */
    val start: Instant,
    /** Sant när starttiden har passerat men påminnelsedagen fortfarande är i dag. */
    val startsImmediately: Boolean,
    val content: PickupActivityContent,
)

data class ReminderPlan(val notifications: List<PlannedNotification>, val liveActivity: PlannedLiveActivity?) {
    companion object {
        val empty = ReminderPlan(emptyList(), null)
    }
}

/**
 * Beräknar önskat läge för notiser och Live Update. Ren funktion: ingen sidoeffekt, och telefonens tidszon läses aldrig.
 * Hur planen blir alarm och notiser bestäms i appen.
 */
object ReminderPlanner {
    /** Taket håller antalet väntande alarm och notiser nere, som på iOS. */
    internal const val MAX_NOTIFICATIONS = 60
    internal const val MAX_ADDRESS_NAME_LENGTH = 60

    /** Reservnotisen kommer så här många minuter efter Live Updatens start, om den inte syntes eller bekräftades. */
    internal const val FALLBACK_DELAY_MINUTES = 45L

    /** Senaste klockslag för reservnotisen kvällen före, i minuter efter midnatt: 23:45. Kvällstiden stannar vid 23:00. */
    internal const val FALLBACK_LATEST_MINUTES = 23 * 60 + 45

    /**
     * Senaste klockslag för reservnotisen samma morgon: 12:00. Morgontiden stannar vid 09:00, så taket binder i praktiken
     * aldrig. Det finns för att reserven aldrig ska räknas till nästa dags tömning.
     */
    internal const val MORNING_FALLBACK_LATEST_MINUTES = 12 * 60

    /** Med samma morgon gäller dagens tömning för Live Update fram till 12:00, i minuter efter midnatt. */
    internal const val MORNING_ACTIVITY_CUTOFF_MINUTES = 12 * 60

    const val FALLBACK_TITLE = "Har du ställt ut kärlen?"
    const val ORDINARY_TITLE = "Ställ ut kärlen"

    /**
     * Reservnotisens tid för en Live Update som startar [start]: 45 minuter senare, högst 23:45 samma dag i svensk tid, och
     * för en morgonstart högst 12:00. Taket följer startens eget klockslag, inte det som är valt nu, eftersom en Live Update
     * från det andra valet kan stå kvar efter ett byte.
     */
    internal fun fallbackDate(start: Instant): Instant {
        val today = StockholmClock.today(start)
        val sameDay = ReminderTime.pickupDay(start) == today
        val cap = if (sameDay) MORNING_FALLBACK_LATEST_MINUTES else FALLBACK_LATEST_MINUTES
        val latest = StockholmClock.dateOn(today, cap)
        return minOf(start + Duration.ofMinutes(FALLBACK_DELAY_MINUTES), latest)
    }

    /** En tömningsdag, med händelser samma dag ihopslagna. */
    private data class Pickup(val date: DayDate, val fractions: List<String>, val estimated: Boolean, val warning: String?)

    fun plan(input: PlannerInput): ReminderPlan {
        val today = StockholmClock.today(input.now)
        val liveActivity = planLiveActivity(input, today)
        val activitiesActive = input.settings.liveActivityOn && input.liveActivitiesAllowed

        val notifications = mutableListOf<PlannedNotification>()
        for (entry in input.addresses) {
            if (!entry.address.notificationsOn) continue
            val response = entry.schedule?.response ?: continue
            for (pickup in pickups(response, today)) {
                val id = PlacedOut(entry.address.key, pickup.date)
                if (id in input.placedOut) continue
                for (timing in input.settings.enabledTimings) {
                    var fireDate = ReminderTime.date(pickup.date, timing, input.settings)
                    var title = ORDINARY_TITLE
                    // Reserven gäller bara notisen som kommer vid samma tid som Live Updaten. Den aviserar själv, men bara om
                    // den faktiskt finns hos systemet. Syntes den redan behövs ingen påminnelse till. Annars ersätts notisen av
                    // en reserv efter starten, med samma identifierare, så att den aldrig blir dubbel. Andra notiser påverkas inte.
                    if (activitiesActive && input.settings.notificationMatchesLiveActivity(timing) && id in input.existingActivities) {
                        if (id in input.shownActivities) continue
                        fireDate = fallbackDate(input.activityStarts[id] ?: fireDate)
                        title = FALLBACK_TITLE
                    }
                    if (fireDate <= input.now) continue
                    notifications += PlannedNotification(
                        identifier = PlannedNotification.identifier(entry.address.key, pickup.date, timing),
                        fireDate = fireDate,
                        title = title,
                        body = body(entry.address.displayName, pickup, response),
                        key = entry.address.key,
                        pickupDate = pickup.date,
                    )
                }
            }
        }
        notifications.sortWith(compareBy<PlannedNotification> { it.fireDate }.thenBy { it.identifier })
        return ReminderPlan(notifications.take(MAX_NOTIFICATIONS), liveActivity)
    }

    /**
     * Notiser som står kvar när deras tid ligger framför även om planen inte längre innehåller dem. Gäller tömningar där den
     * ordinarie notistiden har passerat, tömningen finns kvar i schemat och den varken är utställd eller bevisat visad: en
     * väntande notis där är reserven, och tas den bort står tömningen utan påminnelse. Planeraren skapar aldrig en ny.
     * Bara notisen vid Live Updatens tid kan vara en reserv, så bara den behålls, och bara när valet är påslaget. Slås Live
     * Update av står reserven kvar. Adresser med notiser avstängda ingår inte, så avstängda val tar fortfarande bort sina notiser.
     */
    fun retainable(input: PlannerInput): Map<String, PlacedOut> {
        if (!input.settings.notificationMatchesLiveActivity(input.settings.liveActivityTiming)) return emptyMap()
        val timing = input.settings.liveActivityTiming
        val today = StockholmClock.today(input.now)
        val result = mutableMapOf<String, PlacedOut>()
        for (entry in input.addresses) {
            if (!entry.address.notificationsOn) continue
            val response = entry.schedule?.response ?: continue
            for (pickup in pickups(response, today)) {
                val id = PlacedOut(entry.address.key, pickup.date)
                if (id in input.placedOut || id in input.shownActivities) continue
                val ordinary = ReminderTime.date(pickup.date, timing, input.settings)
                if (ordinary <= input.now) result[PlannedNotification.identifier(id.key, id.date, timing)] = id
            }
        }
        return result
    }

    private fun planLiveActivity(input: PlannerInput, today: DayDate): PlannedLiveActivity? {
        if (!input.settings.liveActivityOn || !input.liveActivitiesAllowed) return null
        val primary = input.addresses.firstOrNull { it.address.isPrimary } ?: return null
        val response = primary.schedule?.response ?: return null
        val key = primary.address.key
        val timing = input.settings.liveActivityTiming
        // Kvällen före gäller första tömning efter i dag, så på tömningsdagen gäller nästa. Samma morgon gäller också dagens
        // tömning fram till 12:00.
        val morningOpen = input.now < StockholmClock.dateOn(today, MORNING_ACTIVITY_CUTOFF_MINUTES)
        val next = pickups(response, today).firstOrNull {
            val eligible = it.date > today || (timing == ReminderTiming.SameMorning && it.date == today && morningOpen)
            eligible && PlacedOut(key, it.date) !in input.placedOut
        } ?: return null

        val start = ReminderTime.liveActivityStart(next.date, input.settings)
        // Passerad start ger direktstart, men bara när påminnelsedagen är i dag.
        val remindedToday = ReminderTime.reminderDay(next.date, timing) == today
        return PlannedLiveActivity(
            key = key,
            pickupDate = next.date,
            start = start,
            startsImmediately = remindedToday && input.now >= start,
            content = content(next, primary.address, response),
        )
    }

    /** Innehållet för huvudadressens tömning ett visst datum, för en Live Update som redan pågår. `null` utan sådan tömning. */
    fun activityContent(date: DayDate, input: PlannerInput): PickupActivityContent? {
        val primary = input.addresses.firstOrNull { it.address.isPrimary } ?: return null
        val response = primary.schedule?.response ?: return null
        val pickup = pickups(response, date).firstOrNull { it.date == date } ?: return null
        return content(pickup, primary.address, response)
    }

    private fun content(pickup: Pickup, address: SavedAddress, response: AddressResponse) = PickupActivityContent(
        addressName = address.displayName.graphemePrefix(MAX_ADDRESS_NAME_LENGTH),
        dateText = SwedishFormat.longDate(pickup.date, capitalized = true),
        shortDateText = SwedishFormat.shortDate(pickup.date),
        fractions = pickup.fractions.map { id ->
            val info = ScheduleLogic.displayInfo(id, response.fractions)
            ActivityFraction(id = id, name = info.name, short = info.short, color = info.color, icon = info.icon)
        },
        estimated = pickup.estimated,
        warning = pickup.warning,
    )

    /** Kommande tömningar från och med [today], en per datum, utan tomma fraktionslistor. */
    private fun pickups(response: AddressResponse, today: DayDate): List<Pickup> {
        val byDate = mutableMapOf<DayDate, Pickup>()
        for (event in ScheduleLogic.upcoming(response.events, today)) {
            if (event.fractions.isEmpty()) continue
            val warning = event.warning?.trimmedNonEmpty()
            val existing = byDate[event.date]
            if (existing == null) {
                byDate[event.date] = Pickup(event.date, event.fractions.distinct(), event.estimated, warning)
                continue
            }
            // Två händelser samma dag slås ihop, så att ingen fraktion eller varning tappas.
            val warnings = listOfNotNull(existing.warning, warning)
            byDate[event.date] = Pickup(
                date = event.date,
                fractions = (existing.fractions + event.fractions).distinct(),
                estimated = existing.estimated || event.estimated,
                warning = if (warnings.isEmpty()) null else warnings.distinct().joinToString(" "),
            )
        }
        return byDate.values.sortedBy { it.date }
    }

    private fun body(addressName: String, pickup: Pickup, response: AddressResponse): String {
        val names = pickup.fractions.map { ScheduleLogic.displayInfo(it, response.fractions).name }
        val date = SwedishFormat.estimated(SwedishFormat.longDate(pickup.date, capitalized = false), pickup.estimated)
        var text = "$addressName: ${joined(names)} töms $date."
        pickup.warning?.let { text += " $it" }
        return text
    }

    /** "A", "A och B", "A, B och C". */
    private fun joined(names: List<String>): String {
        if (names.size < 2) return names.firstOrNull() ?: ""
        return names.dropLast(1).joinToString(", ") + " och " + names.last()
    }
}
