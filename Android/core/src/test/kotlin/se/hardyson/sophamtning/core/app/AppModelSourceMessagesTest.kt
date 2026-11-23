package se.hardyson.sophamtning.core.app

import java.io.File
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.TestScope
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.api.SourceMessage
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.CachedSources
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.fixtureResponse
import se.hardyson.sophamtning.core.storage.tempDir
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.DisabledNotifications
import se.hardyson.sophamtning.core.reminders.DisabledLiveActivities

/** Ett API vars meddelanden går att byta mellan hämtningarna. */
private class MessagesApi(private val base: AddressResponse, @Volatile var messages: List<SourceMessage>, @Volatile var sourceList: List<Source>? = null) : UnusedApi() {
    @Volatile var sourcesCallCount = 0

    override suspend fun address(url: String): AddressResponse = base.copy(messages = messages)

    override suspend fun sources(): SourcesResponse {
        sourcesCallCount++
        val list = sourceList ?: throw ApiError.Unexpected(500)
        return SourcesResponse(list, emptyMap())
    }
}

private val avesta = Source(id = "avesta", name = "Avesta Vatten och Avfall", url = "https://www.avestavatten.se", kommuner = emptyList(), testData = false)

private fun day(iso: String) = DayDate.parse(iso)!!

/** Fredag 20 november 2026 12:00 svensk tid. */
private val now: Instant = StockholmClock.dateOn(day("2026-11-20"), 12 * 60)

/** En timme och lite till senare, så att `RefreshPolicy` hämtar igen. */
private val later: Instant = now.plusSeconds(3700)

private val rutter = SourceMessage(id = "nya-rutter-2026", title = "Hämtrutterna läggs om", text = "Schemat kan bli fel.", url = null, validFrom = day("2026-11-17"), validTo = day("2027-03-31"))

private fun avestaHit(id: String) = hit(id, source = "avesta", locality = "Avesta", kommun = "Avesta")

private class Setup(val model: AppModel, val api: MessagesApi, val reminders: FakeNotifications, val clock: TestClock, val store: LocalStore, val dir: File)

private fun TestScope.setup(
    dir: File = tempDir(),
    status: NotificationAuthorization = NotificationAuthorization.Authorized,
    messages: List<SourceMessage> = listOf(rutter),
    hits: List<SearchHit> = listOf(avestaHit("1")),
): Setup {
    val api = MessagesApi(fixtureResponse(), messages)
    val reminders = FakeNotifications(status)
    val clock = TestClock(now)
    val store = LocalStore(dir)
    val model = AppModel(api, store, reminders, DisabledLiveActivities, { clock.now }, backgroundScope)
    for (h in hits) model.add(h)
    return Setup(model, api, reminders, clock, store, dir)
}

private fun AppModel.visibleIds() = state.value.visibleSourceMessages(StockholmClock.today(now)).map { it.message.id }

private fun model(api: MessagesApi, dir: File, at: Instant, scope: CoroutineScope) = AppModel(api, LocalStore(dir), DisabledNotifications, DisabledLiveActivities, { at }, scope)

// Från AppModelSourceMessagesTests på iOS.
class AppModelSourceMessagesTest {
    @Test
    fun nyttIForgrundenVisarKortetUtanNotis() = runTest {
        val s = setup()
        s.model.refreshAll(manual = false)
        assertEquals(listOf("nya-rutter-2026"), s.model.visibleIds())
        assertTrue(s.reminders.delivered.isEmpty())
        // Räknas som sett: en senare bakgrundskörning ger ingen notis.
        s.clock.set(later)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertTrue(s.reminders.delivered.isEmpty())
        assertEquals(0, s.reminders.requests)
    }

    @Test
    fun nyttIBakgrundenGerEnNotisEnGang() = runTest {
        val s = setup(messages = emptyList())
        s.model.refreshAll(manual = false)
        s.api.messages = listOf(rutter)
        s.clock.set(later)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertEquals(listOf("kalla.avesta.nya-rutter-2026"), s.reminders.delivered.map { it.id })
        assertEquals("Hämtrutterna läggs om", s.reminders.delivered.first().body)
        // Utan källistan är rubriken appens namn.
        assertEquals("Sophämtning", s.reminders.delivered.first().title)
        // Kortet visas också.
        assertEquals(1, s.model.visibleIds().size)
        s.clock.set(later.plusSeconds(3700))
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertEquals(1, s.reminders.delivered.size)
    }

    @Test
    fun notisensRubrikArKallansNamnFranSparadLista() = runTest {
        val s = setup()
        s.store.setSources(CachedSources(SourcesResponse(listOf(avesta), emptyMap()), fetchedAt = now))
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertEquals("Avesta Vatten och Avfall", s.reminders.delivered.first().title)
        assertEquals("Avesta Vatten och Avfall", s.model.sourceName("avesta"))
        assertNull(s.model.sourceName("sater"))
        assertEquals(0, s.api.sourcesCallCount)
    }

    @Test
    fun kallistanHamtasNarNamnetSaknas() = runTest {
        val s = setup()
        s.api.sourceList = listOf(avesta)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertEquals(1, s.api.sourcesCallCount)
        assertEquals("Avesta Vatten och Avfall", s.reminders.delivered.first().title)
        assertEquals("Avesta Vatten och Avfall", s.model.sourceName("avesta"))
        assertEquals("Avesta Vatten och Avfall", s.model.state.value.sourceNames["avesta"])
    }

    @Test
    fun kallistanHamtasInteUtanMeddelanden() = runTest {
        val s = setup(messages = emptyList())
        s.model.refreshAll(manual = false)
        assertEquals(0, s.api.sourcesCallCount)
    }

    @Test
    fun misslyckadKallistaForsokerHogstEnGangITimmen() = runTest {
        val s = setup()
        s.model.refreshAll(manual = false)
        assertEquals(1, s.api.sourcesCallCount)
        s.model.refreshAll(manual = true)
        assertEquals(1, s.api.sourcesCallCount)
        s.clock.set(later)
        s.model.refreshAll(manual = false)
        assertEquals(2, s.api.sourcesCallCount)
    }

    @Test
    fun tvaAdresserHosSammaKallaGerEnNotis() = runTest {
        val s = setup(hits = listOf(avestaHit("1"), avestaHit("2")))
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertEquals(1, s.reminders.delivered.size)
        assertEquals(1, s.model.visibleIds().size)
    }

    @Test
    fun reglagetAvGerIngenNotisMenRaknasSomSett() = runTest {
        val s = setup()
        assertTrue(s.model.setSourceMessages(false))
        assertEquals(false, s.model.state.value.settings.sourceMessagesOn)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertTrue(s.reminders.delivered.isEmpty())
        assertEquals(1, s.model.visibleIds().size)
        // Slås reglaget på igen kommer ingen notis i efterhand.
        assertTrue(s.model.setSourceMessages(true))
        s.clock.set(later)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertTrue(s.reminders.delivered.isEmpty())
    }

    @Test
    fun nekadeNotiserGerIngenNotisOchIngenFraga() = runTest {
        for (status in listOf(NotificationAuthorization.Denied, NotificationAuthorization.NotDetermined)) {
            val s = setup(status = status)
            s.model.refreshAll(manual = false, context = RefreshContext.Background)
            assertTrue(s.reminders.delivered.isEmpty(), "$status")
            assertEquals(0, s.reminders.requests, "$status")
        }
    }

    @Test
    fun oslasligtMinneGerIngenNotisOchSkrivsInteOver() = runTest {
        val dir = tempDir()
        val file = File(dir, "source-messages.json").apply { writeText("{trasig") }
        val s = setup(dir = dir)
        s.model.refreshAll(manual = false, context = RefreshContext.Background)
        assertTrue(s.reminders.delivered.isEmpty())
        assertContentEquals("{trasig".encodeToByteArray(), file.readBytes())
        // Korten visas ändå.
        assertEquals(1, s.model.visibleIds().size)
    }

    @Test
    fun stangtKortVisasInteMenAndraStarKvar() = runTest {
        val other = SourceMessage(id = "helgdagar", title = "Helgdagar", text = "Ändrade dagar.", url = null, validFrom = day("2026-11-01"), validTo = day("2026-12-31"))
        val s = setup(messages = listOf(rutter, other))
        s.model.refreshAll(manual = false)
        assertEquals(listOf("helgdagar", "nya-rutter-2026"), s.model.visibleIds())
        val first = s.model.state.value.visibleSourceMessages(StockholmClock.today(now)).first()
        s.model.dismissSourceMessage(first)
        assertEquals(listOf("nya-rutter-2026"), s.model.visibleIds())
        // Minnet sparas: en ny modell från samma lagring visar inte det stängda.
        val again = model(s.api, s.dir, now, backgroundScope)
        assertEquals(listOf("nya-rutter-2026"), again.visibleIds())
    }

    @Test
    fun utgangetMeddelandeISparatSvarVisasInte() = runTest {
        val s = setup()
        s.model.refreshAll(manual = false)
        val afterEnd = StockholmClock.dateOn(day("2027-04-01"), 12 * 60)
        val again = model(s.api, s.dir, afterEnd, backgroundScope)
        assertTrue(again.state.value.visibleSourceMessages(StockholmClock.today(afterEnd)).isEmpty())
    }
}
