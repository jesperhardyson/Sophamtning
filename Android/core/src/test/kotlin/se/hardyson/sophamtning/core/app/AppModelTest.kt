package se.hardyson.sophamtning.core.app

import java.io.File
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.fixtureResponse
import se.hardyson.sophamtning.core.storage.tempDir

/** Ett API som räknar anropen per adress och dröjer lite, så att samtidiga anrop hinner överlappa. */
private class CountingApi(private val response: AddressResponse) : UnusedApi() {
    private val counts = ConcurrentHashMap<String, AtomicInteger>()
    fun calls(url: String) = counts[url]?.get() ?: 0
    val totalCalls: Int get() = counts.values.sumOf { it.get() }

    override suspend fun address(url: String): AddressResponse {
        counts.computeIfAbsent(url) { AtomicInteger() }.incrementAndGet()
        delay(50)
        return response
    }
}

private val fixedNow: Instant = Instant.ofEpochSecond(1_800_000_000)

private fun makeModel(api: CountingApi, store: LocalStore, scope: CoroutineScope) =
    AppModel(api, store, NoReminders, { fixedNow }, scope)

// Från AppModelTests på iOS.
@OptIn(ExperimentalCoroutinesApi::class)
class AppModelTest {
    @Test
    fun samtidigaUppdateringarHamtarVarjeAdressEnGang() = runTest {
        val api = CountingApi(fixtureResponse())
        val model = makeModel(api, LocalStore(tempDir()), backgroundScope)
        model.add(hit("1"))
        model.add(hit("2"))

        listOf(async { model.refreshAll(manual = false) }, async { model.refreshAll(manual = true) }).awaitAll()

        assertEquals(1, api.calls(hit("1").url))
        assertEquals(1, api.calls(hit("2").url))
        assertNotNull(model.state.value.schedules[AddressKey("orebro", "1")]?.response)
    }

    @Test
    fun uppdateringarKorAdressernaEnITaget() = runTest {
        val api = CountingApi(fixtureResponse())
        val model = makeModel(api, LocalStore(tempDir()), backgroundScope)
        model.add(hit("1"))
        model.add(hit("2"))
        model.refreshAll(manual = false)
        assertEquals(2, api.totalCalls)
        // Inom timmen hämtas inget igen.
        model.refreshAll(manual = true)
        assertEquals(2, api.totalCalls)
    }

    @Test
    fun tillagdAdressSparasOchLaddasVidNastaStart() = runTest {
        val store = LocalStore(tempDir())
        val model = makeModel(CountingApi(fixtureResponse()), store, backgroundScope)
        model.add(hit("1"))
        model.add(hit("1"))
        val addresses = model.state.value.addresses
        assertEquals(1, addresses.size)
        assertTrue(addresses[0].isPrimary)
        assertEquals(addresses, store.addresses())
        val restarted = makeModel(CountingApi(fixtureResponse()), store, backgroundScope)
        assertEquals(addresses, restarted.state.value.addresses)
    }

    @Test
    fun borttagningTarBortAdressOchSparatSchema() = runTest {
        val store = LocalStore(tempDir())
        val model = makeModel(CountingApi(fixtureResponse()), store, backgroundScope)
        model.add(hit("1"))
        model.add(hit("2"))
        model.refreshAll(manual = false)
        val key = AddressKey("orebro", "1")
        assertNotNull(store.schedule(key))

        model.remove(key)
        val addresses = model.state.value.addresses
        assertEquals(listOf("2"), addresses.map { it.key.id })
        assertTrue(addresses[0].isPrimary)
        assertNull(model.state.value.schedules[key])
        assertNull(store.schedule(key))
        assertEquals(listOf("2"), store.addresses().map { it.key.id })
    }

    @Test
    fun misslyckadSparningBehallerTidigareLageOchVisarFel() = runTest {
        // Lagringen går inte att skriva när katalogen i stället är en fil.
        val blocked = File(tempDir(), "blockerad").apply { writeBytes(ByteArray(0)) }
        val model = makeModel(CountingApi(fixtureResponse()), LocalStore(blocked), backgroundScope)
        assertNull(model.state.value.lastStorageError)
        model.add(hit("1"))
        assertTrue(model.state.value.addresses.isEmpty())
        assertNotNull(model.state.value.lastStorageError)
        model.clearStorageError()
        assertNull(model.state.value.lastStorageError)
    }

    @Test
    fun misslyckadSparningAvForstaSvaretGerFelStalletForHamtar() = runTest {
        val dir = tempDir()
        val model = makeModel(CountingApi(fixtureResponse()), LocalStore(dir), backgroundScope)
        model.add(hit("1"))
        // En fil där schemakatalogen ska ligga gör att scheman inte går att spara.
        File(dir, "schedules").writeBytes(ByteArray(0))
        model.refreshAll(manual = false)
        val state = model.state.value
        assertNotNull(state.lastStorageError)
        val schedule = assertNotNull(state.schedules[AddressKey("orebro", "1")])
        assertNull(schedule.response)
        assertNotNull(schedule.lastError)
        val content = HomeContent.make(state.addresses, state.schedules, state.settings, fixedNow)
        assertNotEquals<HomeContent.Status?>(HomeContent.Status.Loading, content.primary?.status)
    }

    @Test
    fun borttagningUnderPagaendeUppdateringLamnarIngetSchemaKvar() = runTest {
        val store = LocalStore(tempDir())
        val model = makeModel(CountingApi(fixtureResponse()), store, backgroundScope)
        model.add(hit("1"))
        model.add(hit("2"))
        val removed = AddressKey("orebro", "1")
        val refresh = launch { model.refreshAll(manual = false) }
        advanceTimeBy(20)
        model.remove(removed)
        refresh.join()
        assertNull(store.schedule(removed))
        assertNull(model.state.value.schedules[removed])
        assertEquals(listOf("2"), model.state.value.addresses.map { it.key.id })
    }

    @Test
    fun misslyckadBorttagningBehallerAdressen() = runTest {
        val dir = tempDir()
        val model = makeModel(CountingApi(fixtureResponse()), LocalStore(dir), backgroundScope)
        model.add(hit("1"))
        // Gör adressfilen oskrivbar genom att ersätta den med en katalog.
        val file = File(dir, "addresses.json")
        file.delete()
        File(file, "x").mkdirs()

        model.remove(AddressKey("orebro", "1"))
        assertEquals(listOf("1"), model.state.value.addresses.map { it.key.id })
        assertNotNull(model.state.value.lastStorageError)
    }

    // Android: Ställ ut och Ångra, med tiden för raden Utställt.

    @Test
    fun stallUtSparasMedTidOchAngraTarBortBada() = runTest {
        val store = LocalStore(tempDir())
        val reminders = RecordingReminders()
        val now = StockholmClock.dateOn(se.hardyson.sophamtning.core.dates.DayDate.parse("2026-11-08")!!, 19 * 60 + 42)
        val model = AppModel(CountingApi(fixtureResponse()), store, reminders, { now }, backgroundScope)
        model.add(hit("1"))
        val entry = PlacedOut(AddressKey("orebro", "1"), se.hardyson.sophamtning.core.dates.DayDate.parse("2026-11-09")!!)

        model.markPlacedOut(entry.key, entry.date)
        assertEquals(setOf(entry), model.state.value.ownPlacedOut)
        assertEquals(mapOf(entry to now), model.state.value.placedOutTimes)
        assertEquals(listOf(entry), reminders.ended)
        assertEquals(2, reminders.cancelled.size)
        // En ny modell från samma lagring läser tiden.
        val again = AppModel(CountingApi(fixtureResponse()), store, NoReminders, { now }, backgroundScope)
        assertEquals(mapOf(entry to now), again.state.value.placedOutTimes)

        model.undoPlacedOut(entry.key, entry.date)
        assertTrue(model.state.value.ownPlacedOut.isEmpty())
        assertTrue(model.state.value.placedOutTimes.isEmpty())
        assertTrue(store.placedOutTimes().isEmpty())
    }
}
