package se.hardyson.sophamtning.core.schedule

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.storage.CachedSchedule

/** Reglerna för när ett schema får hämtas. */
object RefreshPolicy {
    /** Högst en hämtning i timmen per adress. */
    internal val interval: Duration = Duration.ofHours(1)

    /** Efter ett misslyckat försök får användaren försöka igen efter en minut. */
    internal val manualRetryInterval: Duration = Duration.ofMinutes(1)

    /** Efter ett misslyckat försök räknas tiden från försöket, annars från senaste lyckade hämtning. */
    fun canFetch(schedule: CachedSchedule?, now: Instant, manual: Boolean): Boolean {
        schedule ?: return true
        val attempt = schedule.lastAttemptAt
        val (reference, required) = if (schedule.lastError != null && attempt != null) {
            attempt to if (manual) manualRetryInterval else interval
        } else {
            schedule.fetchedAt to interval
        }
        reference ?: return true
        val elapsed = Duration.between(reference, now)
        // En referenstid i framtiden är ogiltig (klockan har ställts bakåt) och får inte låsa hämtningen.
        return elapsed.isNegative || elapsed >= required
    }
}
