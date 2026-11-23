package se.hardyson.sophamtning.core.schedule

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.storage.CachedSchedule

private val base = Instant.ofEpochSecond(1_800_000_000)
private fun at(seconds: Long) = base.plusSeconds(seconds)

class RefreshPolicyTest {
    @Test
    fun enGangITimmenEfterLyckadHamtning() {
        for ((elapsed, manual, allowed) in listOf(Triple(0L, false, false), Triple(3599L, false, false), Triple(3600L, false, true), Triple(0L, true, false), Triple(3599L, true, false), Triple(3600L, true, true))) {
            val schedule = CachedSchedule(fetchedAt = at(0), lastAttemptAt = at(0))
            assertEquals(allowed, RefreshPolicy.canFetch(schedule, at(elapsed), manual), "$elapsed $manual")
        }
    }

    @Test
    fun utanTidigareForsokArHamtningTillaten() {
        assertTrue(RefreshPolicy.canFetch(null, base, false))
        assertTrue(RefreshPolicy.canFetch(null, base, true))
        assertTrue(RefreshPolicy.canFetch(CachedSchedule(), base, false))
    }

    @Test
    fun efterMisslyckatForsokGarManuelltEfterEnMinut() {
        val schedule = CachedSchedule(fetchedAt = at(-7200), lastAttemptAt = at(0), lastError = ApiError.SourceUnavailable)
        assertFalse(RefreshPolicy.canFetch(schedule, at(59), true))
        assertTrue(RefreshPolicy.canFetch(schedule, at(60), true))
    }

    @Test
    fun efterMisslyckatForsokGarAutomatisktEfterEnTimme() {
        val schedule = CachedSchedule(fetchedAt = at(-7200), lastAttemptAt = at(0), lastError = ApiError.Network)
        assertFalse(RefreshPolicy.canFetch(schedule, at(60), false))
        assertFalse(RefreshPolicy.canFetch(schedule, at(3599), false))
        assertTrue(RefreshPolicy.canFetch(schedule, at(3600), false))
    }

    @Test
    fun misslyckatForsokUtanSvarGarAndaFortGenomManuellt() {
        val schedule = CachedSchedule(lastAttemptAt = at(0), lastError = ApiError.NotFound)
        assertFalse(RefreshPolicy.canFetch(schedule, at(30), true))
        assertTrue(RefreshPolicy.canFetch(schedule, at(60), true))
    }

    @Test
    fun referensIFramtidenTillaterHamtning() {
        for (manual in listOf(false, true)) {
            assertTrue(RefreshPolicy.canFetch(CachedSchedule(fetchedAt = at(600), lastAttemptAt = at(600)), base, manual))
            assertTrue(RefreshPolicy.canFetch(CachedSchedule(fetchedAt = at(-7200), lastAttemptAt = at(600), lastError = ApiError.Network), base, manual))
        }
    }
}
