package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.navigation.Home
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/** Backstacken sparas när appen dödas. Den ska vara liten och klara att områdena inte finns kvar i minnet. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class NavigationStateTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun sparadNyckelInnehallerInteOmradena() {
        val app = TestApp()
        val response = ApiDecoding.searchResponse(uiTestData("uitest-omraden"))
        val id = app.dependencies.heldAreas.put(response.addresses, response.sources)
        val picker = Json.encodeToString(AreaPicker.serializer(), AreaPicker("Avesta kommun", "Avesta", id))
        val confirm = Json.encodeToString(AreaConfirm.serializer(), AreaConfirm(id, response.addresses[1].id))
        for (json in listOf(picker, confirm)) {
            assertFalse(json, "Skogsbo" in json)
            assertTrue(json, json.length < 200)
        }
    }

    @Test
    fun omradenSomInteFinnsKvarGerTillbakaTillHemskarmen() {
        val app = TestApp()
        // Som efter att appen dödats: nycklarna finns kvar, men områdena i minnet är borta.
        val backStack = NavBackStack<NavKey>(Home, AreaPicker("Avesta kommun", "Avesta", "borta"), AreaConfirm("borta", "trakt-2"))
        compose.setContent {
            CompositionLocalProvider(LocalAppDependencies provides app.dependencies) {
                SophamtningTheme { AppNavigation(app.model, backStack) }
            }
        }
        compose.waitForText("När töms dina kärl?")
        assertEquals(listOf<NavKey>(Home), backStack.toList())
    }
}
