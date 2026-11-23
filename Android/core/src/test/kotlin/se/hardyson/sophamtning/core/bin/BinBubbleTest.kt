package se.hardyson.sophamtning.core.bin

import kotlin.math.abs
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** Pratbubblan från kärlet bredvid rubriken och i tomt läge, som BinBubbleTests på iOS. */
class BinBubbleTest {
    @Test
    fun bubblanStarCirkaTvaSekunder() {
        assertEquals(2.0, BinBubbleTimeline.DURATION)
        assertTrue(BinBubbleTimeline.isShowing(0.0))
        assertTrue(BinBubbleTimeline.isShowing(1.99))
        assertFalse(BinBubbleTimeline.isShowing(2.0))
        assertFalse(BinBubbleTimeline.isShowing(-0.1))
    }

    @Test
    fun bubblanTonasInOchBort() {
        assertEquals(0.0, BinBubbleTimeline.opacity(0.0))
        assertEquals(1.0, BinBubbleTimeline.opacity(BinBubbleTimeline.FADE_IN))
        assertEquals(1.0, BinBubbleTimeline.opacity(1.0))
        val fading = BinBubbleTimeline.opacity(1.8)
        assertTrue(fading > 0 && fading < 1)
        assertEquals(0.0, BinBubbleTimeline.opacity(2.0))
        assertEquals(0.0, BinBubbleTimeline.opacity(5.0))
        // Stiger hela vägen in och sjunker hela vägen ut.
        val fadeIn = (0..10).map { BinBubbleTimeline.opacity(it * 0.02) }
        assertTrue(fadeIn.zipWithNext().all { (a, b) -> a <= b })
        val fadeOut = (0..25).map { BinBubbleTimeline.opacity(2 - BinBubbleTimeline.FADE_OUT + it * 0.02) }
        assertTrue(fadeOut.zipWithNext().all { (a, b) -> a >= b })
    }

    @Test
    fun bubblanSvavarUppat() {
        assertEquals(0.0, BinBubbleTimeline.rise(0.0, reduceMotion = false))
        val steps = (0..20).map { BinBubbleTimeline.rise(it * 0.1, reduceMotion = false) }
        assertTrue(steps.zipWithNext().all { (a, b) -> a <= b })
        assertEquals(BinBubbleTimeline.RISE_DISTANCE, BinBubbleTimeline.rise(2.0, reduceMotion = false))
        // Växer från lite mindre till full storlek medan den tonas in.
        assertTrue(BinBubbleTimeline.scale(0.0, reduceMotion = false) < 1)
        assertEquals(1.0, BinBubbleTimeline.scale(BinBubbleTimeline.FADE_IN, reduceMotion = false))
    }

    @Test
    fun reduceraRorelseTonarBaraPaPlats() {
        for (elapsed in listOf(0.0, 0.1, 1.0, 1.9)) {
            assertEquals(0.0, BinBubbleTimeline.rise(elapsed, reduceMotion = true))
            assertEquals(1.0, BinBubbleTimeline.scale(elapsed, reduceMotion = true))
        }
        // Toningen är densamma.
        assertEquals(1.0, BinBubbleTimeline.opacity(1.0))
    }

    @Test
    fun ettTryckStartarEttVarvBaraNarKarletStarStilla() {
        // Inget varv har spelats, eller det senaste är slut.
        assertTrue(BinBubbleTimeline.startsRound(roundElapsed = null, reduceMotion = false))
        assertTrue(BinBubbleTimeline.startsRound(roundElapsed = BinLoaderTimeline.ROUND_DURATION, reduceMotion = false))
        // Under ett varv får det spela klart, så att kärlet inte hoppar. Bubblan byts ändå.
        assertFalse(BinBubbleTimeline.startsRound(roundElapsed = 0.5, reduceMotion = false))
        // Med Reducera rörelse spelas inget varv alls.
        assertFalse(BinBubbleTimeline.startsRound(roundElapsed = null, reduceMotion = true))
    }

    @Test
    fun spetsenStarOvanforLocketEllerOvanforHelaKarlet() {
        // Kärlet är 360 × 560 i SVG:n, och locket börjar vid y 150 från överkanten. 4 punkter luft till spetsen.
        assertTrue(abs(BinBubbleTimeline.tipY(135.0, BinBubbleTimeline.Placement.OverLid) - (135.0 * 150 / 360 - 4)) < 0.001)
        // Bredvid rubriken står spetsen ovanför hela kärlets ram, så att bubblan inte täcker kärlet eller texten.
        assertEquals(-4.0, BinBubbleTimeline.tipY(30.0, BinBubbleTimeline.Placement.AboveBin))
        assertEquals(-4.0, BinBubbleTimeline.tipY(56.0, BinBubbleTimeline.Placement.AboveBin))
        // Under kärlet: kärlets höjd (560 av 360 i bredd) och luften.
        assertTrue(abs(BinBubbleTimeline.tipY(36.0, BinBubbleTimeline.Placement.BelowBin) - (36.0 * 560 / 360 + 4)) < 0.001)
        assertTrue(BinBubbleTimeline.Placement.BelowBin.isBelow)
        assertFalse(BinBubbleTimeline.Placement.AboveBin.isBelow)
    }

    @Test
    fun nastaTryckGerEnAnnanText() {
        val queue = BinLoaderTexts.Queue()
        var previous = queue.next(Random.Default)
        repeat(100) {
            val next = queue.next(Random.Default)
            assertNotEquals(previous, next)
            previous = next
        }
    }
}
