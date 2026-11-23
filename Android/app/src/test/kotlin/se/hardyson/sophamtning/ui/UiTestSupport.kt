package se.hardyson.sophamtning.ui

import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeTestRule
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.robolectric.Shadows.shadowOf
import android.os.Looper
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.app.NotificationAuthorization
import se.hardyson.sophamtning.core.app.ReminderRequest
import se.hardyson.sophamtning.core.app.ReminderScheduling
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.kommun.PlaceIndex
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut

/** Svaren som UI-testerna på iOS använder, ur `iOS/Sophamtning/UITestData/` (se build.gradle.kts). */
fun uiTestData(name: String): String =
    requireNotNull(FakeSoporApi::class.java.getResource("/$name.json")) { "$name saknas" }.readText()

/**
 * Ett API som svarar som `UITestAPI` på iOS, utan nät. Bara "testgatan" och "storgatan" ger träffar, och områden finns
 * bara i Avesta. Datumen flyttas inte: testerna har en klocka på dagen då svaren skrevs, 6 november 2026.
 */
class FakeSoporApi : SoporApi {
    /** Ett fel som varje hämtning av ett schema ger, till exempel 502. */
    @Volatile var addressError: ApiError? = null
    val addressCalls = mutableListOf<String>()
    val searches = mutableListOf<String>()

    override suspend fun search(query: String, source: String?): SearchResponse {
        searches += query
        val lowered = query.lowercase()
        if ("testgatan" in lowered || "storgatan" in lowered) return ApiDecoding.searchResponse(uiTestData("uitest-sok"))
        return SearchResponse(addresses = emptyList(), failed = emptyList())
    }

    override suspend fun areas(place: String): SearchResponse {
        if (place.lowercase() == "avesta") return ApiDecoding.searchResponse(uiTestData("uitest-omraden"))
        return SearchResponse(addresses = emptyList(), failed = emptyList())
    }

    override suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse = areas(place)

    override suspend fun address(url: String): AddressResponse {
        addressCalls += url
        addressError?.let { throw it }
        if ("/adress/avesta/" in url) return ApiDecoding.addressResponse(uiTestData("uitest-adress-avesta"))
        if ("/testgatan-4_" in url) return ApiDecoding.addressResponse(uiTestData("uitest-adress-tom"))
        return ApiDecoding.addressResponse(uiTestData("uitest-adress"))
    }

    override suspend fun sources(): SourcesResponse {
        val all = ApiDecoding.sourcesResponse(uiTestData("uitest-kallor"))
        return all.copy(sources = all.sources.filter { !it.testData })
    }
}

/** Påminnelser som säger att systemet tillåter notiser, så att Ställ ut kärlen visas. Inget schemaläggs. */
class AllowedReminders(var status: NotificationAuthorization = NotificationAuthorization.Authorized) : ReminderScheduling {
    override suspend fun authorization() = status
    override suspend fun requestAuthorization() = status == NotificationAuthorization.Authorized
    override suspend fun apply(request: ReminderRequest) {}
    override suspend fun cancel(identifiers: List<String>) {}
    override suspend fun cancelAll() {}
    override suspend fun endLiveUpdate(entry: PlacedOut) {}
    override suspend fun deliverNow(identifier: String, title: String, body: String) {}
}

/** En klocka som testet kan flytta. */
class TestClock(start: Instant) {
    private val value = AtomicReference(start)
    val now: Instant get() = value.get()
    fun set(new: Instant) = value.set(new)
}

fun day(iso: String) = DayDate.parse(iso)!!

/** Fredag 6 november 2026 kl. 12:00 i Stockholm, dagen då svaren i UITestData skrevs. */
val recordedNoon: Instant = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)

/** Allt en UI-test behöver: lagringen i en tillfällig katalog, det falska API:t och klockan. */
class TestApp(
    val api: FakeSoporApi = FakeSoporApi(),
    val clock: TestClock = TestClock(recordedNoon),
    val reminders: ReminderScheduling = AllowedReminders(),
    val dir: File = Files.createTempDirectory("sophamtning-ui-").toFile().also { it.deleteOnExit() },
) {
    val store = LocalStore(dir)
    val model by lazy { AppModel(api, store, reminders, { clock.now }, CoroutineScope(SupervisorJob() + Dispatchers.Main), appVersion = "test") }
    val dependencies by lazy { AppDependencies(model, api, { clock.now }, placeIndex = { PlaceIndex.load() }) }
}

/** Låter väntetider i ViewModels, som sökningens fördröjning, gå klart. */
fun ComposeTestRule.idleFor(millis: Long) {
    shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(millis))
    waitForIdle()
}

/** En nod som visar texten, eller som TalkBack läser med texten, som korten som läses som en enhet. */
fun shows(text: String, substring: Boolean = false) = hasText(text, substring = substring) or hasContentDescription(text, substring = true)

/** Om någon nod visar texten just nu. */
fun ComposeTestRule.isShowing(text: String, substring: Boolean = false) =
    onAllNodes(shows(text, substring), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

/** Väntar tills en nod med texten finns, högst några sekunder. */
fun ComposeTestRule.waitForText(text: String, substring: Boolean = false) {
    for (i in 0 until 50) {
        if (isShowing(text, substring)) return
        idleFor(100)
    }
    throw AssertionError("Texten \"$text\" visas inte")
}
