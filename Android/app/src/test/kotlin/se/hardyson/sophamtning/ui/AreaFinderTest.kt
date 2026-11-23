package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.navigation.AreaFinder
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/** Hitta område: knappen längst ned och läget efter att processen dödats. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class AreaFinderTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val app = TestApp()

    /** Nya ViewModels vid varje komposition, som när processen har dödats och bara det sparade läget finns kvar. */
    @Composable
    private fun FreshViewModels(content: @Composable () -> Unit) {
        val owner = remember {
            object : ViewModelStoreOwner {
                override val viewModelStore = ViewModelStore()
            }
        }
        CompositionLocalProvider(LocalViewModelStoreOwner provides owner, content = content)
    }

    @Composable
    private fun Finder() {
        CompositionLocalProvider(LocalAppDependencies provides app.dependencies) {
            SophamtningTheme { FreshViewModels { AppNavigation(app.model, rememberNavBackStack(AreaFinder("Avesta"))) } }
        }
    }

    private val findButton = hasText("Hitta område") and hasClickAction()

    @Test
    fun knappenHarBaraEnMarginalMotGestfaltet() {
        compose.setContent { Finder() }
        compose.waitForIdle()
        val density = compose.density.density
        val inset = (48 * density).toInt()
        compose.runOnUiThread {
            val insets = WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, inset)).build()
            ViewCompat.dispatchApplyWindowInsets(compose.activity.window.decorView, insets)
        }
        compose.waitForIdle()
        val button = compose.onNode(findButton).fetchSemanticsNode()
        val root = compose.onRoot().fetchSemanticsNode()
        val below = (root.size.height - (button.positionInRoot.y + button.size.height)) / density
        // Gestfältet och knappens egen marginal på 8 dp, inte gestfältet två gånger.
        assertTrue("$below dp under knappen", abs(below - (48 + 8)) <= 2)
    }

    @Test
    fun efterAttProcessenDodatsSynsKnappenIgen() {
        val tester = StateRestorationTester(compose)
        tester.setContent { Finder() }
        compose.waitForIdle()
        compose.onNode(findButton).performClick()
        compose.waitForIdle()
        tester.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        // Resultatet finns inte kvar, så vyn börjar om med kalendern och knappen.
        assertTrue(compose.onAllNodes(findButton).fetchSemanticsNodes().isNotEmpty())
    }
}
