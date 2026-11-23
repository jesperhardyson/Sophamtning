package se.hardyson.sophamtning.core.reminders

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.dates.DayDate

/** Notiser att lägga till och identifierare att ta bort, så att bara skillnaden ändras. */
data class NotificationChanges(val add: List<PlannedNotification>, val removeIds: List<String>)

/** Jämför önskade notiser med de som redan är schemalagda, så att bara skillnaden ändras. */
object NotificationDiff {
    /** Ett enda ögonblick räknas som samma tid. Utlösarens klockslag har bara minuters noggrannhet. */
    internal val fireDateTolerance: Duration = Duration.ofSeconds(1)

    private const val MORNING_SUFFIX = "-morgon"

    /**
     * Identifierare som planeraren skapar: `<key.fileName>-<iso-datum>` för kvällen före och `<key.fileName>-<iso-datum>-morgon`
     * för samma morgon, alltså 64 hexadecimala tecken, ett streck och `åååå-mm-dd`, eventuellt följt av `-morgon`.
     * Schemaläggaren rör bara väntande notiser med sådana identifierare, aldrig andra.
     */
    fun isOwn(identifier: String): Boolean {
        val dash = identifier.indexOf('-')
        if (dash < 0) return false
        val hash = identifier.substring(0, dash)
        if (hash.length != 64 || !hash.all { it in '0'..'9' || it in 'a'..'f' }) return false
        val rest = identifier.substring(dash + 1)
        val datePart = if (rest.endsWith(MORNING_SUFFIX)) rest.dropLast(MORNING_SUFFIX.length) else rest
        return DayDate.parse(datePart) != null
    }

    /**
     * [pendingBodies] är valfri: med den ersätts även en notis vars text ändrats (till exempel ett nytt namn). Saknas en
     * identifierare där räknas texten som oförändrad. [retain] är identifierare som får stå kvar när de ligger framför [now].
     */
    fun diff(
        desired: List<PlannedNotification>,
        pendingIds: Set<String>,
        pendingFireDates: Map<String, Instant>,
        pendingBodies: Map<String, String> = emptyMap(),
        retain: Set<String> = emptySet(),
        now: Instant = Instant.MAX,
    ): NotificationChanges {
        val add = mutableListOf<PlannedNotification>()
        val remove = mutableSetOf<String>()
        val desiredIds = desired.map { it.identifier }.toSet()
        for (notification in desired) {
            if (notification.identifier !in pendingIds) {
                add += notification
                continue
            }
            val sameTime = pendingFireDates[notification.identifier]
                ?.let { Duration.between(it, notification.fireDate).abs() < fireDateTolerance } ?: false
            val sameBody = pendingBodies[notification.identifier]?.let { it == notification.body } ?: true
            if (!(sameTime && sameBody)) {
                // Samma identifierare med ny tid eller text: den gamla tas bort och den nya läggs till.
                add += notification
                remove += notification.identifier
            }
        }
        // En väntande notis som ligger framför och ska stå kvar (reserven) tas inte bort även om planen saknar den.
        val kept = pendingIds.filter { id -> id in retain && (pendingFireDates[id]?.let { it > now } ?: false) }.toSet()
        remove += pendingIds - desiredIds - kept
        return NotificationChanges(add, remove.sorted())
    }
}
