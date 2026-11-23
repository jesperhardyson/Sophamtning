package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performTextInput
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
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaFinder
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.navigation.Changelog
import se.hardyson.sophamtning.navigation.DataSources
import se.hardyson.sophamtning.navigation.FullSchedule
import se.hardyson.sophamtning.navigation.Home
import se.hardyson.sophamtning.navigation.KommunCheck
import se.hardyson.sophamtning.navigation.Settings
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/**
 * Tillgänglighet och största text i hela appen, som schemat Granskning på iOS. Varje skärm ritas med 200 % text, i ljust
 * och mörkt läge, och granskas:
 * - varje knapp och reglage har en text eller beskrivning som TalkBack läser,
 * - varje knapp och reglage går att träffa på minst 48 × 48 dp,
 * - skärmen har minst en rubrik,
 * - ingen text klipps (samma kontroll som `LargeTextTest`).
 *
 * Accessibility Test Framework (`enableAccessibilityChecks`) kör inga kontroller under Robolectric: alla resultat blir
 * `NOT_RUN`, eftersom ramverket inte ser Composes noder där. Kontrollerna här gör samma sak på semantikträdet.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PHONE, fontScale = 2f)
open class AccessibilityTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val app = TestApp(changelog = CHANGELOG)

    private fun key(street: String) = testHit(street).let { AddressKey(it.source, it.id) }

    /** Visar skärmen [screen] överst i backstacken, med adresserna [streets] sparade. */
    private fun show(screen: NavKey, vararg streets: String, waitFor: String) {
        for (street in streets) app.model.add(testHit(street))
        compose.setContent {
            CompositionLocalProvider(LocalAppDependencies provides app.dependencies) {
                SophamtningTheme { AppNavigation(app.model, rememberNavBackStack(screen)) }
            }
        }
        compose.waitForText(waitFor, substring = true)
    }

    private fun type(text: String, waitFor: String) {
        compose.onNode(hasSetTextAction()).performTextInput(text)
        compose.idleFor(500)
        compose.waitForText(waitFor, substring = true)
    }

    // Granskningen

    private val SemanticsNode.hidden: Boolean
        get() = config.contains(SemanticsProperties.HideFromAccessibility) || config.contains(SemanticsProperties.InvisibleToUser)

    private val SemanticsNode.label: String
        get() = listOfNotNull(
            config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" "),
            config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text },
            config.getOrNull(SemanticsProperties.EditableText)?.text,
        ).joinToString(" ").trim()

    private val SemanticsNode.interactive: Boolean
        get() = config.contains(SemanticsActions.OnClick) || config.contains(SemanticsProperties.ToggleableState) || config.contains(SemanticsActions.SetText)

    private fun audit() {
        compose.waitForIdle()
        val problems = mutableListOf<String>()
        val density = compose.density.density
        val minTarget = 48 * density - 1
        // Trädet som TalkBack läser.
        val merged = compose.onAllNodes(SemanticsMatcher("alla") { true }).fetchSemanticsNodes()
        for (node in merged.filter { it.interactive && !it.hidden }) {
            if (node.label.isEmpty()) problems += "Knapp utan text eller beskrivning: ${node.config}"
            // En nod som syns helt mäts med ytan där den tar emot tryck. En nod som delvis eller helt är utanför skärmen klipps,
            // och mäts då med sin egen storlek.
            val fullyShown = node.boundsInRoot.width >= node.size.width - 1 && node.boundsInRoot.height >= node.size.height - 1
            val touch = if (fullyShown) node.touchBoundsInRoot.size else androidx.compose.ui.geometry.Size(node.size.width.toFloat(), node.size.height.toFloat())
            if (touch.width < minTarget || touch.height < minTarget) {
                problems += "\"${node.label}\" går att träffa på ${touch.width / density} × ${touch.height / density} dp"
            }
        }
        if (merged.none { it.config.contains(SemanticsProperties.Heading) }) problems += "Ingen rubrik"
        // Varje text för sig, med sin egen layout.
        val texts = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
        for (index in texts.fetchSemanticsNodes().indices) {
            val node = texts[index]
            val layout = node.textLayout()
            if (!layout.fitsOrEllipsized()) problems += "Texten \"${layout.layoutInput.text}\" klipps"
        }
        assertTrue(problems.joinToString("\n"), problems.isEmpty())
    }

    // Skärmarna

    @Test
    fun startvyn() {
        show(Home, waitFor = "När töms dina kärl?")
        audit()
    }

    @Test
    fun sokningen() {
        show(AddAddress(), waitFor = "Lägg till adress")
        type("Storgatan", waitFor = "4 träffar")
        audit()
    }

    @Test
    fun kommunfragan() {
        show(KommunCheck, waitFor = "Kommun eller ort")
        type("Avesta", waitFor = "Ja, Avesta kommun finns")
        audit()
    }

    @Test
    fun omradesvalet() {
        val held = app.dependencies.heldAreas.put(listOf(avestaArea("Askön, Nyhyttan m.fl.")))
        show(AreaPicker("Avesta kommun", "Avesta", held), waitFor = "Askön, Nyhyttan m.fl.")
        audit()
    }

    @Test
    fun hittaOmrade() {
        show(AreaFinder("Avesta"), waitFor = "När tömdes ditt kärl senast?")
        audit()
    }

    @Test
    fun bekraftelsen() {
        val hit = avestaArea("Askön, Nyhyttan m.fl.")
        val held = app.dependencies.heldAreas.put(listOf(hit))
        show(AreaConfirm(held, hit.id), waitFor = "Stämmer området?")
        audit()
    }

    @Test
    fun hemskarmenMedEnAdress() {
        show(Home, "Testgatan 1", waitFor = "NÄSTA TÖMNING")
        audit()
    }

    @Test
    fun hemskarmenMedFleraAdresser() {
        show(Home, "Testgatan 1", "Testgatan 2", "Testgatan 3", waitFor = "Fler adresser")
        audit()
    }

    @Test
    fun adressvyn() {
        show(Address(key("Testgatan 1")), "Testgatan 1", waitFor = "Kommande")
        audit()
    }

    @Test
    fun helaSchemat() {
        show(FullSchedule(key("Testgatan 1")), "Testgatan 1", waitFor = "Hela schemat")
        compose.waitForText("dec", substring = true)
        audit()
    }

    @Test
    fun installningarna() {
        show(Settings, "Testgatan 1", waitFor = "Om appen")
        audit()
    }

    @Test
    fun datakallorna() {
        show(DataSources, waitFor = "Schemat hämtas från")
        audit()
    }

    @Test
    fun nyheter() {
        show(Changelog, waitFor = "1.0.0")
        audit()
    }

    companion object {
        private val CHANGELOG = """
            ## [1.1.0](https://github.com/x/y/compare/android-v1.0.0...android-v1.1.0) (2026-11-10)

            ### Nytt

            * Kärlet säger något när man trycker på det, med en av Sopors roliga texter ([#90](https://github.com/x/y/issues/90))

            ## 1.0.0 (2026-11-08)

            ### Rättat

            * Första versionen för Android ([#88](https://github.com/x/y/issues/88))
        """.trimIndent()
    }
}

/** Samma granskning i mörkt läge. */
@Config(qualifiers = "w411dp-h891dp-night-xxhdpi", fontScale = 2f)
class AccessibilityDarkTest : AccessibilityTest()
