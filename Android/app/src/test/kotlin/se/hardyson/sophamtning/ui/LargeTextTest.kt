package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.ui.components.CalendarTile
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/** Största textstorleken (200 %) med riktig textmätning: inget av det viktiga klipps. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PHONE, fontScale = 2.0f)
class LargeTextTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** 60 tecken, det längsta namnet som går att spara. */
    private val longName = "Sommarstugan vid sjön bakom den gamla ladan längs grusvägen!"

    private fun openAddressWithLongName(): TestApp {
        val app = TestApp()
        val hit = testHit("Testgatan 1")
        app.model.add(hit)
        app.model.rename(AddressKey(hit.source, hit.id), longName)
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        return app
    }

    @Test
    fun hemskarmenMedLangtNamnKlipperInteRubrikenEllerDagarna() {
        assertTrue(longName.length == 60)
        openAddressWithLongName()
        assertTrue(compose.isShowing(longName, substring = true))
        val headline = compose.onAllNodesWithText("Om 5 dagar", useUnmergedTree = true).onFirst()
        assertTrue(headline.textLayout().fitsOrEllipsized())
        val name = compose.onAllNodesWithText(longName, useUnmergedTree = true).onFirst()
        assertTrue(name.textLayout().fitsOrEllipsized())
    }

    @Test
    fun adressvynsStoraRubrikKlippsInte() {
        openAddressWithLongName()
        compose.onNode(shows(longName, substring = true) and hasClickAction()).performClick()
        compose.waitForText("Kommande")
        // Appfältet har två rubriker: den stora under raden med bakåtpilen, och den lilla bredvid pilen när fältet har krympt.
        val titles = compose.onAllNodes(hasText(longName) and isHeading(), useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals(2, titles.size)
        val large = titles.minBy { it.positionInRoot.x }
        val small = titles.maxBy { it.positionInRoot.x }
        val density = compose.density.density
        val rowHeight = 64 * density
        fun layoutOf(id: Int) = compose.onNode(SemanticsMatcher("rubriken") { it.id == id }, useUnmergedTree = true).textLayout()
        // Den lilla rubriken är en rad, som ryms i raden med pilen.
        val smallLayout = layoutOf(small.id)
        assertEquals(1, smallLayout.lineCount)
        assertTrue("lilla rubriken ${small.size.height} > $rowHeight", small.size.height <= rowHeight + 1)
        assertTrue(smallLayout.fitsOrEllipsized())
        // Den stora rubriken står under raden med pilen och ovanför adressraden.
        val lines = compose.onNode(shows("Testgatan 1, Uppsala", substring = true), useUnmergedTree = true).fetchSemanticsNode()
        val top = large.positionInRoot.y
        val bottom = top + large.size.height
        assertTrue("stora rubriken börjar $top", top >= rowHeight - 1)
        assertTrue("stora rubriken slutar $bottom, raden börjar ${lines.positionInRoot.y}", bottom <= lines.positionInRoot.y + 1)
        assertTrue(layoutOf(large.id).fitsOrEllipsized())
    }

    @Test
    fun kalenderbrickanKlipperInteVeckodagenEllerDagen() {
        compose.setContent { SophamtningTheme { CalendarTile(day("2026-11-12")) } }
        for (text in listOf("torsdag", "12", "NOV")) {
            val layout = compose.onAllNodesWithText(text, useUnmergedTree = true).onFirst().textLayout()
            assertTrue("$text klipps", layout.fitsOrEllipsized())
            assertTrue("$text kortas", !layout.isLineEllipsized(layout.lineCount - 1))
        }
    }
}
