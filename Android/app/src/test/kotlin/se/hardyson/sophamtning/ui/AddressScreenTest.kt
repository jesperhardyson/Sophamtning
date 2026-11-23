package se.hardyson.sophamtning.ui

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.app.NoReminders
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.storage.AddressKey

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class AddressScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private var app = TestApp()

    /** Sparar adressen, visar hemskärmen och öppnar adressvyn från huvudkortet. */
    private fun openAddress(hit: SearchHit = testHit("Testgatan 1")) {
        app.model.add(hit)
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        compose.onNode(shows("Hemma", substring = true) and hasClickAction()).performClick()
        compose.waitForText("Kommande")
    }

    @Test
    fun adressvynVisarNastaKommandeOchPerKarl() {
        openAddress()
        compose.onNode(shows("Nästa tömning. Om 5 dagar", substring = true)).assertIsDisplayed()
        compose.onNodeWithText("Kommande").assertIsDisplayed()
        compose.onNodeWithText("Per kärl").performScrollTo().assertIsDisplayed()
        // Restavfall töms nästa gång den 12 november.
        assertTrue(compose.isShowing("Restavfall, om 6 dagar", substring = true))
    }

    @Test
    fun helaSchemaOppnasOchVisarAllaDatum() {
        openAddress()
        compose.onNodeWithText("Hela schemat").performClick()
        compose.waitForText("Hela schemat")
        val address = app.model.state.value.addresses.single()
        val detail = AddressDetail.make(address, app.model.state.value.schedules[address.key], app.model.state.value.settings, null, recordedNoon)
        assertTrue(detail.rows.size > 50)
        // Det sista datumet, ett år fram, står också med.
        compose.onNode(shows(detail.rows.last().accessibilityLabel)).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun bytNamnOchTaBortFranMenyn() {
        openAddress()
        compose.onNodeWithContentDescription("Mer").performClick()
        compose.onNodeWithText("Byt namn").performClick()
        compose.waitForText("Namnet får vara högst 60 tecken.")
        compose.onNode(hasSetTextAction()).performTextReplacement("Stugan")
        compose.onNodeWithText("Spara").performClick()
        compose.waitForText("Stugan")
        assertEquals("Stugan", app.model.state.value.addresses.single().displayName)

        compose.onNodeWithContentDescription("Mer").performClick()
        compose.onNodeWithText("Ta bort").performClick()
        compose.waitForText("Ta bort adressen?")
        compose.onNode(hasText("Ta bort") and hasClickAction()).performClick()
        compose.waitForText("När töms dina kärl?")
        assertTrue(app.model.state.value.addresses.isEmpty())
    }

    @Test
    fun kalenderradenOppnarGoogleKalender() {
        openAddress()
        compose.onNode(shows("Lägg till i Google Kalender")).performScrollTo().performClick()
        val intent = shadowOf(ApplicationProvider.getApplicationContext<Application>()).nextStartedActivity
        val url = intent.dataString.orEmpty()
        assertTrue(url, url.startsWith("https://calendar.google.com/calendar/render"))
        assertTrue(url, "cid=" in url)
        assertTrue(url, "webcal" in url)
    }

    @Test
    fun kallkortetHarWebbplatsOchKommunensInformation() {
        openAddress()
        compose.waitForText("Uppsala Vatten")
        compose.onNodeWithText("Ansvarar för hämtningen").performScrollTo().assertIsDisplayed()
        compose.onNode(shows("Webbplats")).performScrollTo().assertIsDisplayed()
        compose.onNode(shows("Kommunens information")).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun adressMedAaoOchProcentOppnasOchTasBort() {
        val id = "storgatan-1_åäö-%25"
        val url = "https://sopor.hardyson.se/api/v1/adress/uppsala/storgatan-1_%C3%A5%C3%A4%C3%B6-%2525"
        val hit = testHit("Testgatan 1").copy(id = id, street = "Storgatan 1", url = url)
        openAddress(hit)
        val key = AddressKey("uppsala", id)
        // Samma id hela vägen, och schemat hämtas med den sparade adressen oförändrad.
        assertEquals(key, app.model.state.value.addresses.single().key)
        assertEquals(listOf(url), app.api.addressCalls.distinct())
        compose.onNodeWithContentDescription("Mer").performClick()
        compose.onNodeWithText("Ta bort").performClick()
        compose.onNode(hasText("Ta bort") and hasClickAction()).performClick()
        compose.waitForText("När töms dina kärl?")
        assertTrue(app.store.addresses().isEmpty())
        assertNull(app.store.schedule(key))
    }

    @Test
    fun paminnelsenVisasNarDenFinns() {
        openAddress()
        compose.onNodeWithText("Påminnelser").performScrollTo().assertIsDisplayed()
        compose.onNode(hasText("Påminn mig")).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun paminnelsenVisasInteUtanPaminnelser() {
        app = TestApp(reminders = NoReminders)
        openAddress()
        compose.onNodeWithText("Per kärl").performScrollTo()
        assertTrue(compose.isShowing("Ansvarar för hämtningen"))
        assertFalse(compose.isShowing("Påminnelser"))
        assertFalse(compose.isShowing("Påminn mig"))
    }

    @Test
    fun appenHamtarNarDenKommerTillbakaMedAdressvynOverst() {
        openAddress()
        val before = app.api.addressCalls.size
        // Mer än en timme senare får adressen hämtas igen.
        app.clock.set(recordedNoon.plus(java.time.Duration.ofHours(2)))
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        for (i in 0 until 30) {
            if (app.api.addressCalls.size > before) break
            compose.idleFor(100)
        }
        assertTrue("hämtningar ${app.api.addressCalls.size}", app.api.addressCalls.size > before)
    }

    @Test
    fun adressvynRaknasOmVidDagbytet() {
        val clock = TestClock(se.hardyson.sophamtning.core.dates.StockholmClock.dateOn(day("2026-11-10"), 23 * 60 + 59).plusSeconds(30))
        app = TestApp(clock = clock)
        openAddress()
        compose.waitForText("Nästa tömning. I morgon", substring = true)
        clock.set(se.hardyson.sophamtning.core.dates.StockholmClock.dateOn(day("2026-11-11"), 0).plusSeconds(30))
        compose.advance(61_000)
        compose.waitForText("Nästa tömning. I dag", substring = true)
    }
}
