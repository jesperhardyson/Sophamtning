package se.hardyson.sophamtning.ui.components

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

@RunWith(AndroidJUnit4::class)
class ComponentsTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val papper = FractionInfo(name = "Pappersförpackningar", short = "Papper", color = "#2E5E86", icon = "package")

    @Test
    fun fraktionenVisasMedNamnOchIkon() {
        compose.setContent { SophamtningTheme { FractionChip(id = "papper", info = papper) } }
        // Chipet läses som en enhet med hela namnet, och ikonen har namnet som beskrivning.
        compose.onNodeWithText("Pappersförpackningar", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithContentDescription("Pappersförpackningar").assertIsDisplayed()
    }

    @Test
    fun okandIkonGerAtervinning() {
        assertSame(FractionIcons.recycling, FractionIcons.forName("okänd"))
        assertSame(FractionIcons.recycling, FractionStyle("tradgard", FractionInfo("Trädgård", "Trädgård", "#000000", "leaf-okänd")).icon)
        assertEquals(FractionIcons.forName("wine"), FractionStyle("glas", papper).icon)
    }

    @Test
    fun kalenderbrickanVisarManadOchDag() {
        compose.setContent { SophamtningTheme { CalendarTile(DayDate(2026, 11, 9)) } }
        compose.onNodeWithText("NOV", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("9", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithContentDescription("måndag 9 november").assertIsDisplayed()
    }

    @Test
    fun meddelandekortetKanStangas() {
        var closed = 0
        compose.setContent {
            SophamtningTheme {
                MessageCard(title = "Hämtrutterna läggs om", text = "Schemat kan bli fel.", style = MessageStyle.Neutral, icon = AppSymbols.Campaign, closeLabel = "Stäng meddelandet", onClose = { closed++ })
            }
        }
        compose.onNodeWithContentDescription("Stäng meddelandet").performClick()
        assertEquals(1, closed)
    }
}
