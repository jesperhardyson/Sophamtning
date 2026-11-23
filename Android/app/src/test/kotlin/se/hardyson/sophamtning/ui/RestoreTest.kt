package se.hardyson.sophamtning.ui

import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.MainActivity
import se.hardyson.sophamtning.SophamtningApplication

/** Telefonen vrids: aktiviteten skapas om, och backstacken och söktexten finns kvar utan en ny hämtning. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class RestoreTest {
    private val app = TestApp()

    @get:Rule(order = 0)
    val dependencies = object : ExternalResource() {
        override fun before() {
            app.model.add(testHit("Testgatan 1"))
            ApplicationProvider.getApplicationContext<SophamtningApplication>().dependencies = app.dependencies
        }
    }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun adressvynFinnsKvarUtanNyHamtning() {
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        compose.onNode(shows("Hemma", substring = true) and hasClickAction()).performClick()
        compose.waitForText("Kommande")
        val calls = app.api.addressCalls.size
        compose.activityRule.scenario.recreate()
        compose.waitForText("Kommande")
        compose.waitForText("Per kärl")
        assertEquals(calls, app.api.addressCalls.size)
    }

    @Test
    fun sokningenFinnsKvar() {
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        compose.onNode(androidx.compose.ui.test.hasContentDescription("Lägg till")).performClick()
        compose.onNode(hasSetTextAction()).performTextInput("Storgatan")
        compose.idleFor(500)
        compose.waitForText("4 träffar")
        val searches = app.api.searches.size
        compose.activityRule.scenario.recreate()
        compose.waitForText("Storgatan")
        compose.waitForText("4 träffar")
        assertTrue(compose.isShowing("Lägg till adress"))
        assertEquals(searches, app.api.searches.size)
        compose.onNodeWithText("Storgatan").assertExists()
    }
}
