package se.hardyson.sophamtning.core.bin

import java.time.Instant
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Den del av MotionTests på iOS som är logik: inträdet, en gång per process och trycket. */
class MotionTest {
    // Hemskärmen kommer in

    @Test
    fun kortenKommerEttEfterEtt() {
        assertEquals(24.0, EntranceTimeline.CARD_DISTANCE)
        assertEquals(0.45, EntranceTimeline.CARD_DURATION)
        val delays = (0 until 5).map { EntranceTimeline.cardDelay(it, reduceMotion = false) }
        assertEquals(0.0, delays.first())
        for ((earlier, later) in delays.zipWithNext()) assertTrue(abs(later - earlier - 0.06) < 0.0001)
    }

    @Test
    fun reduceraRorelseToningUtanFordrojningOchUtanGlid() {
        for (index in 0 until 5) {
            assertEquals(0.0, EntranceTimeline.cardDelay(index, reduceMotion = true))
            assertEquals(0.0, EntranceTimeline.rowDelay(index, reduceMotion = true))
        }
        assertEquals(0.0, EntranceTimeline.offset(24.0, reduceMotion = true))
        assertEquals(24.0, EntranceTimeline.offset(24.0, reduceMotion = false))
    }

    @Test
    fun utfallningUtanAnimationMedReduceraRorelse() {
        assertFalse(Motion.expands(reduceMotion = true))
        assertTrue(Motion.expands(reduceMotion = false))
    }

    @Test
    fun vandningenBorjarNarKortetKommitIn() {
        // Huvudkortet är andra kortet i ordningen: 60 ms väntan och 0,45 s glidning.
        assertTrue(abs(EntranceTimeline.flipDelay(cardIndex = 1, reduceMotion = false) - 0.51) < 0.0001)
        assertTrue(abs(EntranceTimeline.flipDelay(cardIndex = 1, reduceMotion = true) - 0.2) < 0.0001)
    }

    // En gång per process

    @Test
    fun spelasBaraEnGangPerProcess() {
        assertTrue(StartEntrance.shouldPlay(skipsIntro = false, alreadyPlayed = false))
        assertFalse(StartEntrance.shouldPlay(skipsIntro = false, alreadyPlayed = true))
        assertFalse(StartEntrance.shouldPlay(skipsIntro = true, alreadyPlayed = false))
    }

    @Test
    fun enStartBorjarEnGangOchAldrigOm() {
        var entrance = StartEntrance(plays = true)
        assertTrue(entrance.hidesCards)
        assertNull(entrance.begin)
        assertTrue(entrance.allowsOpeningFlip)
        val first = Instant.ofEpochSecond(100)
        entrance = entrance.start(first)
        assertFalse(entrance.hidesCards)
        assertEquals(first, entrance.begin)
        entrance = entrance.start(first.plusSeconds(50))
        assertEquals(first, entrance.begin)
        entrance = entrance.finish()
        assertFalse(entrance.hidesCards)
        assertFalse(entrance.allowsOpeningFlip)
        // När den är klar kan den inte starta på nytt, till exempel vid retur från bakgrunden.
        entrance = entrance.start(first.plusSeconds(100))
        assertNull(entrance.begin)
        assertFalse(entrance.hidesCards)
        assertFalse(entrance.allowsOpeningFlip)
    }

    @Test
    fun utanStartVisasAlltDirektUtanVandning() {
        var entrance = StartEntrance(plays = false)
        assertFalse(entrance.hidesCards)
        assertFalse(entrance.allowsOpeningFlip)
        entrance = entrance.start(Instant.now())
        assertNull(entrance.begin)
    }

    @Test
    fun enListaSomRedanVisatsSpelasInteIgen() {
        val shown = ShownOnce<String>()
        assertTrue(shown.shouldPlay("a"))
        shown.markShown("a")
        assertFalse(shown.shouldPlay("a"))
        assertTrue(shown.shouldPlay("b"))
    }

    // Listor

    @Test
    fun radernaKommerEnEfterEnOchBaraDeForstaAtta() {
        assertEquals(8, EntranceTimeline.ROW_LIMIT)
        val delays = (0 until 8).map { EntranceTimeline.rowDelay(it, reduceMotion = false) }
        assertEquals(0.0, delays.first())
        for ((earlier, later) in delays.zipWithNext()) assertTrue(abs(later - earlier - 0.04) < 0.0001)
        assertTrue(EntranceTimeline.animatesRow(7))
        assertFalse(EntranceTimeline.animatesRow(8))
        // Den sista raden väntar kortare tid än en tredjedels sekund, så att nya sökresultat aldrig känns sena.
        assertTrue(delays.last() < 0.3)
    }

    // Tryck

    @Test
    fun tryckFjadrarOchReduceraRorelseToning() {
        assertEquals(1.0, PressMotion.scale(pressed = false, reduceMotion = false))
        assertEquals(0.96, PressMotion.scale(pressed = true, reduceMotion = false))
        assertEquals(1.0, PressMotion.opacity(pressed = true, reduceMotion = false))
        assertEquals(1.0, PressMotion.scale(pressed = true, reduceMotion = true))
        assertTrue(PressMotion.opacity(pressed = true, reduceMotion = true) < 1)
        assertEquals(1.0, PressMotion.opacity(pressed = false, reduceMotion = true))
    }
}
