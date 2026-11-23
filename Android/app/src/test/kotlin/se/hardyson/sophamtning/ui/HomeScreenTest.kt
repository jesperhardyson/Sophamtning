package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Duration
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.app.NoReminders
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class HomeScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** Tisdag 10 november 2026 kl. 19:42, kvällen före Testgatans tömning. */
    private val eveningBefore = StockholmClock.dateOn(day("2026-11-10"), 19 * 60 + 42)

    private fun start(app: TestApp, vararg hits: SearchHit, notificationsOn: Boolean = false) {
        for (hit in hits) app.model.add(hit)
        if (notificationsOn) {
            // Påminnelsen är på för adresserna, som efter ett val i adressvyn.
            runBlocking { for (hit in hits) app.model.setNotifications(true, AddressKey(hit.source, hit.id)) }
        }
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForIdle()
    }

    @Test
    fun huvudkortetVisarNastaTomningOchKarlen() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"))
        compose.waitForText("Ons 11 nov", substring = true)
        val card = compose.onNode(shows("Hemma", substring = true))
        card.assertIsDisplayed()
        assertTrue(compose.isShowing("om 5 dagar", substring = true))
        assertTrue(compose.isShowing("Plastförpackningar, Glas", substring = true))
        compose.onNodeWithText("Sophämtning").assertIsDisplayed()
    }

    @Test
    fun stallUtOchAngra() {
        val app = TestApp(clock = TestClock(eveningBefore))
        start(app, testHit("Testgatan 1"), notificationsOn = true)
        compose.waitForText("Ställ ut kärlen")
        compose.onNodeWithText("Ställ ut kärlen").performScrollTo().performClick()
        compose.waitForText("Utställt")
        compose.waitForText("av dig · kl. 19:42")
        compose.onAllNodes(shows("Ångra")).onFirst().performScrollTo().performClick()
        compose.waitForText("Ställ ut kärlen")
        assertTrue(app.model.state.value.ownPlacedOut.isEmpty())
    }

    @Test
    fun svepTarBortMedBekraftelse() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"), testHit("Testgatan 2"))
        compose.waitForText("Fler adresser")
        compose.onNode(shows("Testgatan 2,", substring = true)).performScrollTo().performTouchInput { swipeLeft() }
        compose.waitForText("Ta bort adressen?")
        compose.onNodeWithText("Ta bort").performClick()
        compose.waitForIdle()
        assertEquals(listOf("Testgatan 1"), app.model.state.value.addresses.map { it.street })
        assertFalse(compose.isShowing("Fler adresser"))
    }

    @Test
    fun kallmeddelandetVisasOchStangs() {
        val app = TestApp()
        start(app, avestaArea("Askön, Nyhyttan m.fl."))
        compose.waitForText("Hämtrutterna läggs om")
        compose.waitForText("Läs mer hos Avesta Vatten och Avfall")
        compose.onNodeWithContentDescription("Stäng meddelandet").performClick()
        compose.waitForIdle()
        assertFalse(compose.isShowing("Hämtrutterna läggs om"))
    }

    @Test
    fun felVidHamtningVisasInteSomSaknadAdress() {
        val app = TestApp()
        val hit = testHit("Testgatan 1")
        // Ett schema hämtat för två timmar sedan, så att appen hämtar igen, och källan svarar 502.
        val fetched = recordedNoon.minus(Duration.ofHours(2))
        app.store.setSchedule(CachedSchedule(ApiDecoding.addressResponse(uiTestData("uitest-adress")), fetched, fetched, null), AddressKey(hit.source, hit.id))
        app.api.addressError = ApiError.SourceUnavailable
        start(app, hit)
        compose.waitForText("Kunde inte uppdatera schemat. Visar det senast hämtade.", substring = true)
        assertTrue(compose.isShowing("om 5 dagar", substring = true))
        assertFalse(compose.isShowing("Adressen hittas inte längre", substring = true))
        assertTrue(app.api.addressCalls.isNotEmpty())
    }

    @Test
    fun dagbytetRaknasOm() {
        val clock = TestClock(StockholmClock.dateOn(day("2026-11-10"), 23 * 60 + 59).plusSeconds(30))
        val app = TestApp(clock = clock)
        start(app, testHit("Testgatan 1"))
        compose.waitForText("i morgon", substring = true)
        clock.set(StockholmClock.dateOn(day("2026-11-11"), 0).plusSeconds(30))
        compose.advance(61_000)
        compose.waitForText("i dag", substring = true)
        assertFalse(compose.isShowing("i morgon", substring = true))
    }

    // Tills plan 5 finns inga påminnelser, och det som inte kan fungera visas inte.

    @Test
    fun forslagetVisasNarPaminnelserFinns() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"))
        compose.waitForText("Vill du bli påmind?")
    }

    @Test
    fun forslagetVisasInteUtanPaminnelser() {
        val app = TestApp(reminders = NoReminders)
        start(app, testHit("Testgatan 1"))
        compose.waitForText("Ons 11 nov", substring = true)
        assertFalse(compose.isShowing("Vill du bli påmind?"))
        assertFalse(compose.isShowing("Påminn mig"))
    }

    @Test
    fun bekraftelsenFoljerSinAdressNarEnAnnanTasBort() {
        val app = TestApp()
        val hits = listOf("Testgatan 1", "Testgatan 2", "Testgatan 3", "Testgatan 4").map(::testHit)
        start(app, *hits.toTypedArray())
        compose.waitForText("Fler adresser")
        compose.onNode(shows("Testgatan 3,", substring = true)).performScrollTo().performTouchInput { swipeLeft() }
        compose.waitForText("Ta bort adressen?")
        // En annan adress försvinner medan bekräftelsen är öppen.
        app.model.remove(AddressKey(hits[1].source, hits[1].id))
        compose.waitForIdle()
        compose.onNode(androidx.compose.ui.test.hasText("Ta bort") and androidx.compose.ui.test.hasClickAction()).performClick()
        compose.waitForIdle()
        assertEquals(listOf("Testgatan 1", "Testgatan 4"), app.model.state.value.addresses.map { it.street })
    }

    // Snabbmenyn med ett långt tryck, som AddressQuickActions.swift.

    private fun longPress(text: String) {
        compose.onNode(shows(text, substring = true) and hasClickAction()).performScrollTo().performTouchInput { longClick() }
        compose.waitForIdle()
    }

    @Test
    fun langtTryckOppnarMenyn() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"), testHit("Testgatan 2"))
        compose.waitForText("Fler adresser")
        longPress("Testgatan 2,")
        for (text in listOf("Byt namn", "Gör till huvudadress", "Påminn mig", "Ta bort")) compose.waitForText(text)
        assertFalse(compose.isShowing("Live Update"))
        // TalkBack får samma val som åtgärder på raden.
        val row = compose.onNode(shows("Testgatan 2,", substring = true) and hasClickAction()).fetchSemanticsNode()
        val actions = row.config[SemanticsActions.CustomActions].map { it.label }
        assertEquals(listOf("Byt namn", "Gör till huvudadress", "Slå på påminnelse", "Ta bort"), actions)
    }

    @Test
    fun huvudkortetsMenyHarLiveUpdateMenInteHuvudadress() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"), testHit("Testgatan 2"))
        compose.waitForText("Fler adresser")
        longPress("Hemma")
        compose.waitForText("Live Update")
        // Menyn står på hemskärmen. Ett långt tryck öppnar inte adressvyn.
        compose.waitForText("Byt namn")
        assertTrue(compose.isShowing("Fler adresser"))
        assertFalse(compose.isShowing("Gör till huvudadress"))
    }

    @Test
    fun menynVisarInteParminnelserUtanPaminnelser() {
        val app = TestApp(reminders = NoReminders)
        start(app, testHit("Testgatan 1"))
        compose.waitForText("Ons 11 nov", substring = true)
        longPress("Hemma")
        compose.waitForText("Byt namn")
        assertFalse(compose.isShowing("Påminn mig"))
        assertFalse(compose.isShowing("Live Update"))
    }

    @Test
    fun gorTillHuvudadressFranMenyn() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"), testHit("Testgatan 2"))
        compose.waitForText("Fler adresser")
        longPress("Testgatan 2,")
        compose.onNodeWithText("Gör till huvudadress").performClick()
        compose.waitForIdle()
        assertEquals("Testgatan 2", app.model.state.value.primary?.street)
    }

    @Test
    fun taBortFranMenynFragarForst() {
        val app = TestApp()
        start(app, testHit("Testgatan 1"), testHit("Testgatan 2"))
        compose.waitForText("Fler adresser")
        longPress("Testgatan 2,")
        compose.onNode(hasText("Ta bort") and hasClickAction()).performClick()
        compose.waitForText("Ta bort adressen?")
        // Inget är borttaget förrän valet bekräftas.
        assertEquals(2, app.model.state.value.addresses.size)
        compose.onNode(hasText("Ta bort") and hasClickAction()).performClick()
        compose.waitForIdle()
        assertEquals(listOf("Testgatan 1"), app.model.state.value.addresses.map { it.street })
    }
}
