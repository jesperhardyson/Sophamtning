package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.navigation.Home
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/**
 * Telefonen i liggande läge med 200 % text: hemskärmen och adressvyn granskas som i [AccessibilityTest], och den stora
 * rubriken ryms i appfältet också när navigeringsfältet eller kameran tar plats vid sidan.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi", fontScale = 2f)
class AccessibilityLandscapeTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val app = TestApp()
    private val hit = testHit("Testgatan 1")
    private val key = AddressKey(hit.source, hit.id)

    private fun show(screen: NavKey, waitFor: String) {
        app.model.add(hit)
        compose.setContent {
            CompositionLocalProvider(LocalAppDependencies provides app.dependencies) {
                SophamtningTheme { AppNavigation(app.model, rememberNavBackStack(screen)) }
            }
        }
        compose.waitForText(waitFor, substring = true)
    }

    @Test
    fun hemskarmen() {
        show(Home, waitFor = "NÄSTA TÖMNING")
        compose.auditAccessibility()
    }

    @Test
    fun adressvyn() {
        show(Address(key), waitFor = "Kommande")
        compose.auditAccessibility()
    }

    @Test
    fun langRubrikRymsMedFaltVidSidan() {
        app.model.add(hit)
        // Ryms på en rad över hela bredden, men inte mellan fälten vid sidan.
        app.model.rename(key, TITLE)
        show(Address(key), waitFor = "Kommande")
        // Navigeringsfältet till höger och kameran till vänster, som på en telefon i liggande läge.
        val density = compose.density.density
        compose.runOnUiThread {
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, (240 * density).toInt(), 0))
                .setInsets(WindowInsetsCompat.Type.displayCutout(), Insets.of((120 * density).toInt(), 0, 0, 0))
                .build()
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView, insets)
        }
        compose.waitForIdle()
        val titles = compose.onAllNodes(hasText(TITLE) and isHeading(), useUnmergedTree = true).fetchSemanticsNodes()
        val large = titles.maxBy { it.positionInRoot.y }
        val lines = compose.onNode(shows("Testgatan 1, Uppsala", substring = true), useUnmergedTree = true).fetchSemanticsNode()
        val top = large.positionInRoot.y / density
        val bottom = top + large.size.height / density
        val linesTop = lines.positionInRoot.y / density
        // Hela rubriken står under raden med pilen, med fältets luft på 8 dp under sig före adressraden. Räknas höjden
        // med hela bredden får rubriken en rad för lite, och fältet slutar direkt under texten eller klipper den.
        assertTrue("stora rubriken börjar $top dp", top >= 63)
        assertTrue("stora rubriken slutar $bottom dp, raden börjar $linesTop dp", bottom + 8 <= linesTop + 1)
        assertTrue(large.boundsInRoot.height >= large.size.height - 1)
    }

    private companion object {
        const val TITLE = "Sommarstugan vid sjön bakom ladan"
    }
}
