package se.hardyson.sophamtning.core.reminders

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

/** Det som ska göras med en Live Update, som `LiveActivityAction` på iOS. */
sealed interface LiveActivityAction {
    data class Start(val activity: PlannedLiveActivity) : LiveActivityAction

    data class Update(val id: String, val content: PickupActivityContent) : LiveActivityAction

    data class Remove(val id: String) : LiveActivityAction

    /** Visar innehållet, med bocken för Utställt, en kort stund och avslutar sedan Live Updaten. */
    data class End(val id: String, val content: PickupActivityContent) : LiveActivityAction
}

/** Hur en planerad Live Update läggs in just nu: direkt, eller med ett alarm vid starttiden. */
sealed interface StartMode {
    data object Immediately : StartMode

    data class Scheduled(val at: Instant) : StartMode
}

/**
 * Hur Live Updaten ska läggas in just nu. Har starttiden hunnit passera sedan planeringen visas den direkt, så att ett
 * alarm aldrig sätts i det förflutna.
 */
fun PlannedLiveActivity.startMode(now: Instant): StartMode =
    if (startsImmediately || start <= now) StartMode.Immediately else StartMode.Scheduled(start)

/** Samma Live Update med bocken för Utställt. */
internal fun PlannedLiveActivity.markedPlacedOut(detail: String?) = copy(content = content.markedPlacedOut(detail))

/** Jämför önskad Live Update med de som finns, så att bara skillnaden ändras. Som `LiveActivityDiff` på iOS. */
object LiveActivityDiff {
    /** Räknas som samma start. */
    private val startTolerance: Duration = Duration.ofSeconds(1)

    /**
     * Hur länge efter sin starttid en Live Update får stå som väntande innan den räknas som utebliven. Ett alarm utan
     * exakt tid kan komma upp till tio minuter senare, men det väntande läget gäller tills alarmet gått, och ett sådant
     * alarm ger notisen på sin egen tid. Samma försiktiga gräns som på iOS.
     */
    val overdueMargin: Duration = Duration.ofMinutes(5)

    /** Väntande trots att starttiden passerat med marginal. Den går inte att lita på, och räknas inte som en påminnelse. */
    fun isOverdue(activity: ExistingActivity, now: Instant): Boolean = activity.isPending && now > activity.start.plus(overdueMargin)

    /**
     * Listan utför inte sig själv i ordning: `AppModel` startar den nya före borttagningarna, så att ett fel lämnar den gamla kvar.
     *
     * [primary] är huvudadressen. `null` betyder att den önskade Live Updatens adress gäller. Behövs för att en pågående
     * ska leva kvar när ingen nästa tömning är planerad. [canStart] är falskt när inget får startas: då behålls en väntande
     * för samma tömning, eftersom den annars försvinner utan ersättning. [todayContent] är dagens innehåll för
     * huvudadressen, så att en pågående får ny varning eller nytt namn. [householdMarked], [householdMarkDetails] och
     * [householdSilenced] gäller hushållets bockar, som på iOS. Android har inget hushåll än, så de är tomma.
     */
    fun actions(
        desired: PlannedLiveActivity?,
        existing: List<ExistingActivity>,
        today: DayDate,
        enabled: Boolean,
        primary: AddressKey? = null,
        canStart: Boolean = true,
        now: Instant = Instant.MIN,
        todayContent: PickupActivityContent? = null,
        householdMarked: Set<PlacedOut> = emptySet(),
        householdMarkDetails: Map<PlacedOut, String> = emptyMap(),
        householdSilenced: Set<PlacedOut> = emptySet(),
    ): List<LiveActivityAction> {
        if (!enabled) return existing.map { LiveActivityAction.Remove(it.id) }
        val main = primary ?: desired?.key
        val wanted = desired?.let { planned ->
            val entry = PlacedOut(planned.key, planned.pickupDate)
            if (entry in householdMarked) planned.markedPlacedOut(householdMarkDetails[entry]) else planned
        }
        // En visad Live Update som tas bort för att någon i hushållet har ställt ut visar bocken först. En väntande har aldrig visats.
        fun removal(id: String): LiveActivityAction {
            val activity = existing.firstOrNull { it.id == id }
            val entry = activity?.let { PlacedOut(it.key, it.pickupDate) }
            if (activity == null || activity.isPending || entry !in householdMarked) return LiveActivityAction.Remove(id)
            return LiveActivityAction.End(id, activity.content.markedPlacedOut(householdMarkDetails[entry]))
        }

        val removals = mutableListOf<String>()
        var kept: ExistingActivity? = null
        var keptToday: ExistingActivity? = null
        // Pågående går före väntande, så att den som redan visas är den som blir kvar av en dubblett.
        val ordered = existing.filter { !it.isPending } + existing.filter { it.isPending }
        for (activity in ordered) {
            if (wanted != null && activity.key == wanted.key && activity.pickupDate == wanted.pickupDate) {
                if (kept == null) kept = activity else removals += activity.id
            } else if (!activity.isPending && activity.pickupDate == today && activity.key == main && keptToday == null &&
                PlacedOut(activity.key, activity.pickupDate) !in householdSilenced
            ) {
                // Startad för i dag på huvudadressen. Den lever tills Klart eller tidsgränsen.
                keptToday = activity
            } else {
                removals += activity.id
            }
        }

        val result = mutableListOf<LiveActivityAction>()
        if (keptToday != null && todayContent != null && keptToday.content != todayContent) {
            result += LiveActivityAction.Update(keptToday.id, todayContent)
        }
        if (wanted == null) return removals.map(::removal) + result
        if (kept == null) return removals.map(::removal) + result + if (canStart) listOf(LiveActivityAction.Start(wanted)) else emptyList()
        if (kept.isPending) {
            val sameStart = Duration.between(kept.start, wanted.start).abs() < startTolerance
            if (canStart && (kept.content != wanted.content || !sameStart || isOverdue(kept, now))) {
                // En väntande ersätts, så att alarmet och innehållet följer den nya planen.
                return (removals + kept.id).map(::removal) + result + LiveActivityAction.Start(wanted)
            }
        } else if (kept.content != wanted.content) {
            result += LiveActivityAction.Update(kept.id, wanted.content)
        }
        return removals.map(::removal) + result
    }
}
