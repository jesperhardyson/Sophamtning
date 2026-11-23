package se.hardyson.sophamtning.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.ui.components.CalendarSheets
import se.hardyson.sophamtning.ui.components.CalendarTile
import se.hardyson.sophamtning.ui.components.CalendarTileTags
import se.hardyson.sophamtning.ui.components.FlipHaptics

/** Kalenderbladets bläddring i brickan, som CalendarTile.swift. Tidslinjen själv testas i `core`. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class CalendarFlipTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val from = day("2026-11-07")
    private val to = day("2026-11-11")
    private var shown by mutableStateOf(from)
    private val haptics = mutableListOf<HapticFeedbackType>()

    private fun start(reduceMotion: Boolean) {
        compose.mainClock.autoAdvance = false
        val recorder = object : HapticFeedback {
            override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
                haptics += hapticFeedbackType
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides recorder) { CalendarTile(shown, reduceMotion = reduceMotion) }
        }
        step(100)
    }

    private fun step(millis: Long) {
        compose.mainClock.advanceTimeBy(millis)
        compose.waitForIdle()
    }

    private fun tile() = compose.onNodeWithTag(CalendarTileTags.TILE).fetchSemanticsNode()

    /** Bladen som syns, det översta först. */
    private fun sheets(): List<DayDate> = tile().config[CalendarSheets]

    /** Allt TalkBack kan läsa i brickan. */
    private fun spoken(): List<String> {
        val node = tile()
        return node.config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() } +
            node.config.getOrElse(SemanticsProperties.Text) { emptyList() }.map { it.text } +
            compose.onNodeWithTag(CalendarTileTags.TILE, useUnmergedTree = true).fetchSemanticsNode().children.flatMap { child ->
                child.config.getOrElse(SemanticsProperties.Text) { emptyList() }.map { it.text }
            }
    }

    @Test
    fun bladetVandsNarNastaTomningByterDatum() {
        start(reduceMotion = false)
        // Första gången brickan visas bläddras inget.
        assertEquals(listOf(from), sheets())
        assertTrue(haptics.isEmpty())
        shown = to
        val seen = mutableSetOf<DayDate>()
        var most = 0
        repeat(80) {
            step(10)
            seen += sheets()
            most = maxOf(most, sheets().size)
        }
        // Ett blad per dag, de viks upp och överlappar, och tömningsdagen ligger kvar.
        assertEquals(setOf(from, day("2026-11-08"), day("2026-11-09"), day("2026-11-10"), to), seen)
        assertTrue("bladen överlappar: $most", most >= 3)
        assertEquals(listOf(to), sheets())
        // En lätt vibration per blad och en tydligare när sista bladet landar.
        assertEquals(List(4) { FlipHaptics.PAGE } + FlipHaptics.LANDING, haptics)
    }

    @Test
    fun brickanLasesBaraMedTomningsdagen() {
        start(reduceMotion = false)
        assertEquals(listOf(SwedishFormat.longDate(from, capitalized = false)), spoken())
        shown = to
        // Från första bildrutan med det nya datumet läses bara det, aldrig bladen som bläddras förbi.
        step(16)
        val expected = listOf(SwedishFormat.longDate(to, capitalized = false))
        repeat(80) {
            step(10)
            assertEquals(expected, spoken())
        }
    }

    @Test
    fun utanAnimationerToningEndast() {
        start(reduceMotion = true)
        shown = day("2026-12-24")
        val seen = mutableListOf<DayDate>()
        repeat(60) {
            step(10)
            val now = sheets()
            assertEquals("ett blad i taget", 1, now.size)
            if (seen.lastOrNull() != now.single()) seen += now.single()
        }
        assertEquals(listOf(from, day("2026-12-24")), seen)
        assertTrue(haptics.isEmpty())
    }
}
