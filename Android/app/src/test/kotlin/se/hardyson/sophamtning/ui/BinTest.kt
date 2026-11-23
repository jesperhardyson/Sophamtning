package se.hardyson.sophamtning.ui

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.bin.BinBubbleStack
import se.hardyson.sophamtning.core.bin.BinLoaderTexts
import se.hardyson.sophamtning.ui.bin.BinArtwork
import se.hardyson.sophamtning.ui.bin.BinRoundPlaying
import se.hardyson.sophamtning.ui.bin.BinTags

/** Kärlet i tomt läge med pratbubblorna, som BinRoundView på iOS. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class BinTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun startEmpty(app: TestApp = TestApp()) {
        // Klockan går bara när testet flyttar den, så att bubblorna inte hinner tonas bort medan testet väntar.
        compose.mainClock.autoAdvance = false
        compose.setContent { SophamtningApp(app.dependencies) }
        compose.mainClock.advanceTimeBy(100)
        compose.waitForIdle()
    }

    private fun tapBin() {
        compose.onNodeWithTag(BinTags.BIN, useUnmergedTree = true).performTouchInput { click() }
        compose.mainClock.advanceTimeBy(50)
        compose.waitForIdle()
    }

    private fun bubbleCount() = compose.onAllNodes(hasTestTag(BinTags.BUBBLE), useUnmergedTree = true).fetchSemanticsNodes().size

    private fun playing() = compose.onNodeWithTag(BinTags.BIN, useUnmergedTree = true).fetchSemanticsNode().config[BinRoundPlaying]

    @Test
    fun trycketVisarEnBubbla() {
        startEmpty()
        assertEquals(0, bubbleCount())
        // Det första varvet spelas när kärlet visas, och står sedan still.
        compose.mainClock.advanceTimeBy(2_000)
        compose.waitForIdle()
        assertFalse(playing())
        tapBin()
        assertEquals(1, bubbleCount())
        assertTrue(playing())
        // Bubblan syns i cirka 2 sekunder.
        compose.mainClock.advanceTimeBy(2_200)
        compose.waitForIdle()
        assertEquals(0, bubbleCount())
    }

    @Test
    fun fyraSnabbaTryckVisarHogstTreBubblor() {
        startEmpty()
        repeat(4) { tapBin() }
        assertEquals(BinBubbleStack.MAX_COUNT, bubbleCount())
    }

    @Test
    fun kartaOchBubblaArDoldaForTalkBackMenTextenLases() {
        startEmpty()
        tapBin()
        val hidden = SemanticsMatcher.keyIsDefined(SemanticsProperties.HideFromAccessibility)
        compose.onNode(hasTestTag(BinTags.BIN) and hidden, useUnmergedTree = true).fetchSemanticsNode()
        compose.onNode(hasTestTag(BinTags.BUBBLE) and hidden, useUnmergedTree = true).fetchSemanticsNode()
        // Texten tillkännages med låg prioritet.
        val polite = SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite)
        val announced = compose.onNode(polite, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()
        assertTrue(announced in BinLoaderTexts.ALL)
        // I trädet som TalkBack läser står texten bara i tillkännagivandet.
        assertTrue(compose.onAllNodes(hasText(announced)).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun utanAnimationerSpelasIngetVarv() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f)
        try {
            startEmpty()
            assertFalse(playing())
            tapBin()
            // Bubblan kommer ändå, och tonas bara in och ut på plats.
            assertEquals(1, bubbleCount())
            assertFalse(playing())
        } finally {
            Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        }
    }

    @Test
    fun allaKarletsBanorGarAttTolka() {
        assertEquals(7, BinArtwork.lidParts.size)
        for (part in BinArtwork.lidParts + BinArtwork.bodyParts) assertFalse(part.isEmpty)
    }

    @Test
    fun bubblanSynsInteOverNastaSkarm() {
        startEmpty()
        tapBin()
        assertEquals(1, bubbleCount())
        compose.onNodeWithContentDescription("Inställningar").performClick()
        // Mitt i övergången till nästa skärm.
        compose.mainClock.advanceTimeBy(100)
        compose.waitForIdle()
        assertEquals(0, bubbleCount())
    }

    @Test
    fun forstaVarvetSpelasBaraEnGang() {
        val app = TestApp()
        app.model.add(testHit("Testgatan 1"))
        startEmpty(app)
        // Kärlet bredvid rubriken spelar sitt första varv när hemskärmen visas.
        assertTrue(playing())
        compose.mainClock.advanceTimeBy(2_000)
        compose.waitForIdle()
        assertFalse(playing())
        compose.onNode(shows("Hemma", substring = true) and hasClickAction()).performClick()
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Tillbaka").performClick()
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
        // Tillbaka på hemskärmen står kärlet still, som på iOS.
        assertFalse(playing())
    }
}
