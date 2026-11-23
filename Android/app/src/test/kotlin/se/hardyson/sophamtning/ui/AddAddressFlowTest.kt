package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApp

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class AddAddressFlowTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val app = TestApp()

    private fun start() {
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForIdle()
    }

    private fun type(text: String) {
        compose.onNode(hasSetTextAction()).performTextInput(text)
        compose.idleFor(500)
    }

    @Test
    fun startvynVisarSokningOchKommunfragan() {
        start()
        compose.onNodeWithText("När töms dina kärl?").assertIsDisplayed()
        compose.onNodeWithText("Gata och husnummer").assertIsDisplayed()
        compose.onNodeWithText("Adressen sparas bara i din telefon.").assertIsDisplayed()
        compose.onNodeWithText("Finns min kommuns hämtningsschema?").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun sokningVisarTraffarOchSparar() {
        start()
        compose.onNodeWithText("Gata och husnummer").performClick()
        compose.waitForIdle()
        type("Storgatan")
        compose.waitForText("4 träffar")
        compose.onAllNodes(shows("Testgatan 1", substring = true)).onFirst().performClick()
        compose.waitForText("Sophämtning")
        compose.waitForText("Hemma")
        assertEquals(listOf("Testgatan 1"), app.model.state.value.addresses.map { it.street })
        // Hemskärmen hämtar schemat för den nya adressen.
        compose.waitForText("NÄSTA TÖMNING")
    }

    @Test
    fun kommunfraganSvararMedanManSkriver() {
        start()
        compose.onNodeWithText("Finns min kommuns hämtningsschema?").performScrollTo().performClick()
        compose.waitForIdle()
        type("Avesta")
        compose.waitForText("Ja, Avesta kommun finns")
        compose.onNodeWithText("Välj område i Avesta kommun").assertIsDisplayed()
    }

    @Test
    fun omradeValjsOchBekraftas() {
        start()
        compose.onNodeWithText("Finns min kommuns hämtningsschema?").performScrollTo().performClick()
        compose.waitForIdle()
        type("Avesta")
        compose.waitForText("Välj område i Avesta kommun")
        compose.onNodeWithText("Välj område i Avesta kommun").performClick()
        compose.waitForText("Du väljer området själv")
        compose.onAllNodes(shows("Skogsbo tätort, Rosse m.fl.", substring = true)).onFirst().performScrollTo().performClick()
        compose.waitForText("Stämmer området?")
        compose.onNodeWithText("Spara området").performClick()
        compose.waitForText("Hemma")
        assertEquals(listOf("Skogsbo tätort, Rosse m.fl."), app.model.state.value.addresses.map { it.street })
        compose.waitForText("Skogsbo tätort, Rosse m.fl.", substring = true)
    }

    @Test
    fun ingenTraffVisarLankTillKommunfragan() {
        start()
        compose.onNodeWithText("Gata och husnummer").performClick()
        compose.waitForIdle()
        type("Okändavägen 3")
        compose.waitForText("Adressen hittades inte")
        compose.onNodeWithText("Finns min kommuns hämtningsschema?").performScrollTo().performClick()
        compose.waitForText("Skriv din kommun eller ort. Svaret kommer medan du skriver.")
    }
}
