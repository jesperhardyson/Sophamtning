package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.BuildConfig
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.reminders.DisabledNotifications

/** Inställningarna, datakällorna och Nyheter, som SettingsView.swift och ChangelogSheet.swift. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class SettingsScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val changelog = """
        # Changelog

        ## [1.1.0](https://github.com/x/y/compare/android-v1.0.0...android-v1.1.0) (2026-11-10)


        ### Nytt

        * Kärlet säger något när man trycker på det ([#90](https://github.com/x/y/issues/90)) ([b7e13ad](https://github.com/x/y/commit/b7e13ad))

        ## 1.0.0 (2026-11-08)


        ### Rättat

        * Första versionen för Android ([#88](https://github.com/x/y/issues/88)) ([4b1ca42](https://github.com/x/y/commit/4b1ca42))
    """.trimIndent()

    private fun openSettings(app: TestApp = TestApp()) {
        app.model.add(testHit("Testgatan 1"))
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.waitForText("Sophämtning")
        compose.onNodeWithContentDescription("Inställningar").performClick()
        compose.waitForText("Om appen")
    }

    private fun tap(text: String) {
        compose.onNode(hasText(text) and hasClickAction()).performScrollTo().performClick()
    }

    @Test
    fun installningarnaVisarHuvudadressInofficiellIntegritetOchVersion() {
        openSettings()
        for (text in listOf("Huvudadress", "Hemma", "Datakällor", "Integritet", "Version", BuildConfig.VERSION_NAME, "Inofficiell app")) {
            compose.waitForText(text)
        }
        assertTrue(compose.isShowing("Sophämtning är inte kopplad till någon kommun", substring = true))
    }

    @Test
    fun datakallornaVisarKallorUtanTestdata() {
        val app = TestApp()
        app.api.sourcesWithTestData = true
        openSettings(app)
        tap("Datakällor")
        compose.waitForText("Schemat hämtas från 43 källor.")
        compose.waitForText("Avesta Vatten och Avfall")
        assertFalse(compose.isShowing("Testkällan"))
        compose.onNode(shows("Wikidata (CC0)", substring = true)).performScrollTo()
        assertTrue(compose.isShowing("Ortlistan för kommunfrågan", substring = true))
    }

    @Test
    fun versionOppnarNyheter() {
        openSettings()
        tap("Version")
        compose.waitForText("Nyheter")
    }

    @Test
    fun nyheterUtanChangelogVisarTomText() {
        openSettings()
        tap("Version")
        compose.waitForText("Inga nyheter att visa")
        assertTrue(compose.isShowing("Nyheterna följer med nästa version av appen.", substring = true))
    }

    @Test
    fun nyheterMedChangelogVisarVersionerna() {
        openSettings(TestApp(changelog = changelog))
        tap("Version")
        compose.waitForText("1.1.0 · 10 november 2026")
        compose.waitForText("Kärlet säger något när man trycker på det")
        compose.waitForText("1.0.0 · 8 november 2026")
        assertTrue(compose.isShowing("Rättat"))
        assertFalse(compose.isShowing("Inga nyheter att visa"))
    }

    @Test
    fun paminnelserVisasInteNarDeInteFinns() {
        openSettings(TestApp(reminders = DisabledNotifications))
        compose.waitForText("Huvudadress")
        for (text in listOf("Notiser", "Meddelanden från källan", "Live Update")) assertFalse(text, compose.isShowing(text))
    }

    @Test
    fun paminnelserVisasNarDeFinns() {
        openSettings()
        compose.waitForText("Notiser")
        compose.waitForText("Meddelanden från källan")
    }
}
