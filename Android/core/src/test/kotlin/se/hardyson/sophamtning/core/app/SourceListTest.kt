package se.hardyson.sophamtning.core.app

import java.io.File
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.Kommun
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.storage.CachedSources
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.tempDir
import se.hardyson.sophamtning.core.reminders.DisabledNotifications
import se.hardyson.sophamtning.core.reminders.DisabledLiveActivities

private class SourcesApi(@Volatile var result: Result<SourcesResponse>) : UnusedApi() {
    @Volatile var callCount = 0
    override suspend fun sources(): SourcesResponse {
        callCount++
        return result.getOrThrow()
    }
}

private fun list(id: String) = SourcesResponse(
    listOf(Source(id = id, name = id, url = "https://example.com", kommuner = listOf(Kommun("1880", "Örebro kommun")), testData = false)),
    emptyMap(),
)

private val t0: Instant = Instant.ofEpochSecond(1_800_000_000)

// Från SourceListTests på iOS: testerna av AppModel.sourceList, visningsnamnen och ett misslyckat sparande.
// gammalSparadListaUtanAppversionAvkodas finns i storage/SourceListTest.
class SourceListTest {
    @Test
    fun sparadListaUnderEttDygnHamtarInteIgen() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(3600)))
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertEquals("sparad", model.sourceList()?.first()?.id)
        assertEquals(0, api.callCount)
    }

    @Test
    fun listaFranAnnanAppversionHamtasDirekt() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(60), appVersion = "1.0.0 (201)"))
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope, appVersion = "1.0.1 (301)")
        assertEquals("ny", model.sourceList()?.first()?.id)
        assertEquals("1.0.1 (301)", store.sources()?.appVersion)
        model.sourceList()
        assertEquals(1, api.callCount)
    }

    @Test
    fun listaUtanAppversionHamtasDirekt() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(60)))
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope, appVersion = "1.0.1 (301)")
        assertEquals("ny", model.sourceList()?.first()?.id)
    }

    @Test
    fun sammaAppversionAnvanderSparadLista() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(60), appVersion = "1.0.1 (301)"))
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope, appVersion = "1.0.1 (301)")
        assertEquals("sparad", model.sourceList()?.first()?.id)
        assertEquals(0, api.callCount)
    }

    @Test
    fun listaFranAnnanAppversionAnvandsNarHamtningenMisslyckas() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(60), appVersion = "1.0.0 (201)"))
        val api = SourcesApi(Result.failure(ApiError.Network))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope, appVersion = "1.0.1 (301)")
        assertEquals("sparad", model.sourceList()?.first()?.id)
    }

    @Test
    fun gammalListaHamtasOchSparas() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(90_000)))
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertEquals("ny", model.sourceList()?.first()?.id)
        assertEquals("ny", store.sources()?.response?.sources?.first()?.id)
        assertEquals(t0, store.sources()?.fetchedAt)
        model.sourceList()
        assertEquals(1, api.callCount)
    }

    @Test
    fun saknadListaHamtas() = runTest {
        val api = SourcesApi(Result.success(list("ny")))
        val model = AppModel(api, LocalStore(tempDir()), DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertEquals("ny", model.sourceList()?.first()?.id)
    }

    @Test
    fun sparadListaAnvandsNarHamtningMisslyckas() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(90_000)))
        val api = SourcesApi(Result.failure(ApiError.Network))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertEquals("sparad", model.sourceList()?.first()?.id)
    }

    @Test
    fun inteSparatOchMisslyckadGerNilAldrigTomLista() = runTest {
        val api = SourcesApi(Result.failure(ApiError.SourceUnavailable))
        val model = AppModel(api, LocalStore(tempDir()), DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertNull(model.sourceList())
        // Ett nytt försök hämtar igen, så att Försök igen fungerar.
        api.result = Result.success(list("ny"))
        assertEquals("ny", model.sourceList()?.first()?.id)
    }

    @Test
    fun avbrottUnderHamtningSatterIngenSparr() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(90_000)))
        val api = SourcesApi(Result.failure(CancellationException("avbruten")))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertEquals("sparad", model.sourceList()?.first()?.id)
        api.result = Result.success(list("ny"))
        assertEquals("ny", model.sourceList()?.first()?.id)
        assertEquals(2, api.callCount)
    }

    @Test
    fun misslyckadHamtningUpprepasInteVidVarjeTangent() = runTest {
        val store = LocalStore(tempDir())
        store.setSources(CachedSources(list("sparad"), fetchedAt = t0.minusSeconds(90_000)))
        val clock = TestClock(t0)
        val api = SourcesApi(Result.failure(ApiError.Network))
        val model = AppModel(api, store, DisabledNotifications, DisabledLiveActivities, { clock.now }, backgroundScope)
        model.sourceList()
        model.sourceList()
        assertEquals(1, api.callCount)
        clock.advance(3700)
        model.sourceList()
        assertEquals(2, api.callCount)
    }

    // Från AddDisplayNameTests.

    private fun areaHit(id: String, street: String, selection: String) = SearchHit(
        id = id, street = street, locality = "", kommun = "Avesta kommun", source = "avesta", detail = null, selection = selection,
        notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/avesta/$id",
    )

    @Test
    fun visningsnamn() = runTest {
        val model = AppModel(SourcesApi(Result.failure(ApiError.Network)), LocalStore(tempDir()), DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        assertTrue(model.add(areaHit("1", "Kvarnvägen 3", "address")))
        assertTrue(model.add(areaHit("2", "Skogsbo tätort, Rosse m.fl.", "area")))
        assertTrue(model.add(areaHit("3", "Storgatan 5", "address")))
        assertEquals(listOf("Hemma", "Skogsbo tätort, Rosse m.fl.", "Storgatan 5"), model.state.value.addresses.map { it.displayName })
    }

    // Från AddFailureTests.

    @Test
    fun misslyckatSparandeGerFalseOchLamnarListanOforandrad() = runTest {
        val blocked = File(tempDir(), "blockerad").apply { writeBytes(ByteArray(0)) }
        val model = AppModel(SourcesApi(Result.failure(ApiError.Network)), LocalStore(blocked), DisabledNotifications, DisabledLiveActivities, { t0 }, backgroundScope)
        val hit = SearchHit(
            id = "1", street = "Storgatan 1", locality = "Örebro", kommun = "Örebro kommun", source = "orebro", detail = null,
            selection = "address", notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/orebro/1",
        )
        assertFalse(model.add(hit))
        assertTrue(model.state.value.addresses.isEmpty())
    }
}
