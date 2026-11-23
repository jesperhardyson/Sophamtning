package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApp

/**
 * Den stora rubriken står direkt under raden med bakåtpilen, som på iOS. Appfältets utfällda höjd följer rubrikens höjd,
 * så att ingen tom yta står ovanför en rubrik på en rad.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class TitleTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** Raden med bakåtpilen, och luften mellan den och rubriken. */
    private val rowHeight = 64
    private val gap = 12

    private fun largeTitleTop(title: String): Float {
        val titles = compose.onAllNodes(hasText(title) and isHeading(), useUnmergedTree = true).fetchSemanticsNodes()
        // Appfältet har två rubriker: den lilla i raden överst, och den stora under raden.
        return titles.maxOf { it.positionInRoot.y } / compose.density.density
    }

    @Test
    fun adressvynsRubrikStarDirektUnderPilen() {
        val app = TestApp()
        app.model.add(testHit("Testgatan 1"))
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        compose.onNode(shows("Hemma", substring = true) and hasClickAction()).performClick()
        compose.waitForText("Kommande")
        val top = largeTitleTop("Hemma")
        assertTrue("rubriken börjar $top dp", top >= rowHeight - 1 && top <= rowHeight + gap)
    }

    @Test
    fun hemskarmensRubrikStarDirektUnderFaltet() {
        val app = TestApp()
        app.model.add(testHit("Testgatan 1"))
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForText("NÄSTA TÖMNING", substring = true)
        // Kärlet bredvid rubriken är högre än texten, så rubriken står lite längre ned, men inte en hel rad.
        val top = largeTitleTop("Sophämtning")
        assertTrue("rubriken börjar $top dp", top >= rowHeight - 1 && top <= rowHeight + gap + 20)
    }
}
