package se.hardyson.sophamtning.core.schedule

import java.io.File
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.fixtureResponse
import se.hardyson.sophamtning.core.storage.savedAddress
import se.hardyson.sophamtning.core.storage.tempDir

/** Ett API som svarar med en förbestämd utgång och räknar anropen. */
private class StubApi(private val result: () -> AddressResponse) : SoporApi {
    var calls = 0
    override suspend fun address(url: String): AddressResponse { calls++; return result() }
    override suspend fun search(query: String, source: String?): SearchResponse = error("används inte")
    override suspend fun areas(place: String): SearchResponse = error("används inte")
    override suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse = error("används inte")
    override suspend fun sources(): SourcesResponse = error("används inte")
}

private val now = Instant.ofEpochSecond(1_800_000_000)
private val address = savedAddress()
private fun blockedStore() = LocalStore(File(tempDir(), "blockerad").apply { writeText("") })

class ScheduleRefresherTest {
    @Test
    fun lyckatSvarSparasOchRapporterasSomFetched() = runTest {
        val store = LocalStore(tempDir())
        val fresh = fixtureResponse()
        assertEquals(RefreshOutcome.Fetched, ScheduleRefresher(StubApi { fresh }, store).refresh(address, now, false))
        assertEquals(CachedSchedule(fresh, now, now, null), store.schedule(address.key))
    }

    @Test
    fun lyckatSvarNollstallerFel() = runTest {
        val store = LocalStore(tempDir())
        val old = now.minusSeconds(7200)
        store.setSchedule(CachedSchedule(null, old, old, ApiError.Network), address.key)
        val fresh = fixtureResponse()
        assertEquals(RefreshOutcome.Fetched, ScheduleRefresher(StubApi { fresh }, store).refresh(address, now, false))
        val saved = store.schedule(address.key)!!
        assertNull(saved.lastError)
        assertEquals(fresh, saved.response)
        assertEquals(now, saved.fetchedAt)
    }

    @Test
    fun misslyckandeBehallerSparatSvar() = runTest {
        val store = LocalStore(tempDir())
        val kept = fixtureResponse()
        val fetched = now.minusSeconds(7200)
        store.setSchedule(CachedSchedule(kept, fetched, fetched, null), address.key)
        val outcome = ScheduleRefresher(StubApi { throw ApiError.SourceUnavailable }, store).refresh(address, now, false)
        assertEquals(RefreshOutcome.Failed(ApiError.SourceUnavailable), outcome)
        assertEquals(CachedSchedule(kept, fetched, now, ApiError.SourceUnavailable), store.schedule(address.key))
    }

    @Test
    fun notFoundBehallerSvaretOchMarkerarFel() = runTest {
        val store = LocalStore(tempDir())
        val kept = fixtureResponse()
        val fetched = now.minusSeconds(7200)
        store.setSchedule(CachedSchedule(kept, fetched, fetched), address.key)
        assertEquals(RefreshOutcome.Failed(ApiError.NotFound), ScheduleRefresher(StubApi { throw ApiError.NotFound }, store).refresh(address, now, true))
        val saved = store.schedule(address.key)!!
        assertEquals(kept, saved.response)
        assertEquals(ApiError.NotFound, saved.lastError)
    }

    @Test
    fun misslyckandeUtanTidigareSchemaSpararForsoket() = runTest {
        val store = LocalStore(tempDir())
        assertEquals(RefreshOutcome.Failed(ApiError.Network), ScheduleRefresher(StubApi { throw ApiError.Network }, store).refresh(address, now, false))
        assertEquals(CachedSchedule(null, null, now, ApiError.Network), store.schedule(address.key))
    }

    @Test
    fun skippedAnroparInteApiet() = runTest {
        val store = LocalStore(tempDir())
        val recent = now.minusSeconds(60)
        val before = CachedSchedule(fixtureResponse(), recent, recent)
        store.setSchedule(before, address.key)
        val api = StubApi { fixtureResponse() }
        assertEquals(RefreshOutcome.Skipped, ScheduleRefresher(api, store).refresh(address, now, true))
        assertEquals(0, api.calls)
        assertEquals(before, store.schedule(address.key))
    }

    @Test
    fun avbrutetAnropGerSkippedUtanAttSpara() = runTest {
        val store = LocalStore(tempDir())
        val before = CachedSchedule(fixtureResponse(), now.minusSeconds(7200), now.minusSeconds(7200))
        store.setSchedule(before, address.key)
        assertEquals(RefreshOutcome.Skipped, ScheduleRefresher(StubApi { throw CancellationException() }, store).refresh(address, now, false))
        assertEquals(before, store.schedule(address.key))
    }

    @Test
    fun skrivfelGerStorageFailed() = runTest {
        assertEquals(RefreshOutcome.StorageFailed, ScheduleRefresher(StubApi { fixtureResponse() }, blockedStore()).refresh(address, now, false))
    }

    @Test
    fun apiFelDarStorageFailedNarForsoketInteGarAttSpara() = runTest {
        assertEquals(RefreshOutcome.StorageFailed, ScheduleRefresher(StubApi { throw ApiError.Network }, blockedStore()).refresh(address, now, false))
    }
}
