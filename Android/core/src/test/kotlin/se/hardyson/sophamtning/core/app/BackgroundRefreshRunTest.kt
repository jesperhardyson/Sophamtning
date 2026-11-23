package se.hardyson.sophamtning.core.app

import java.time.Duration
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.reminders.DisabledLiveActivities
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.fixtureResponse
import se.hardyson.sophamtning.core.storage.tempDir

/** Ett API som dröjer, så att en körning hinner avbrytas innan svaret kommer. */
private class SlowApi(private val response: AddressResponse, private val delayMillis: Long) : UnusedApi() {
    val calls = AtomicInteger()
    override suspend fun address(url: String): AddressResponse {
        calls.incrementAndGet()
        delay(delayMillis)
        return response
    }
}

private val fixedNow: Instant = Instant.ofEpochSecond(1_800_000_000)

private class RunSetup(val model: AppModel, val api: SlowApi, val scheduler: FakeNotifications)

private fun TestScope.runSetup(delayMillis: Long): RunSetup {
    val api = SlowApi(fixtureResponse(), delayMillis)
    val scheduler = FakeNotifications(NotificationAuthorization.Denied)
    val model = AppModel(api, LocalStore(tempDir()), scheduler, DisabledLiveActivities, { fixedNow }, backgroundScope)
    model.add(hit("1"))
    return RunSetup(model, api, scheduler)
}

// Från BackgroundRefreshRunTests på iOS. WorkManager bokar nästa körning och avbryter arbetet, så det som på iOS gäller
// nästa körning och att uppgiften avslutas exakt en gång finns inte här.
class BackgroundRefreshRunTest {
    @Test
    fun arbetetArUniktOchKorsVarTredjeTimme() {
        assertEquals("se.hardyson.sophamtning.refresh", BackgroundRefreshRun.UNIQUE_NAME)
        assertEquals(Duration.ofHours(3), BackgroundRefreshRun.INTERVAL)
    }

    @Test
    fun korningenHamtarOmplanerarOchLaddarOmWidgeten() = runTest {
        val s = runSetup(10)
        val readsBefore = s.scheduler.authorizationReads
        val order = mutableListOf<String>()

        BackgroundRefreshRun(s.model, startingActivities = true, reloadWidgets = { order += "reload" }).run()
        order += "klar"
        s.model.settleReminders()

        assertEquals(1, s.api.calls.get())
        assertNotNull(s.model.state.value.schedules[AddressKey("orebro", "1")]?.response)
        // Påminnelserna har planerats.
        assertTrue(s.scheduler.authorizationReads > readsBefore)
        // Widgeten laddas om en gång, innan arbetet är klart.
        assertEquals(listOf("reload", "klar"), order)
    }

    @Test
    fun avbrottLaddarOmWidgetenEnGang() = runTest {
        val s = runSetup(200)
        var reloads = 0
        val job = launch { BackgroundRefreshRun(s.model, startingActivities = true, reloadWidgets = { reloads++ }).run() }
        runCurrent()
        // Systemet säger att tiden är slut.
        job.cancel()
        job.join()
        assertTrue(job.isCancelled)
        assertEquals(1, reloads)
        advanceTimeBy(400)
        runCurrent()
        assertEquals(1, reloads)
    }
}
