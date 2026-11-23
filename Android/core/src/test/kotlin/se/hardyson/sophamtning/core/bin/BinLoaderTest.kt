package se.hardyson.sophamtning.core.bin

import kotlin.math.abs
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** Som BinLoaderTests på iOS: värdena från karl-lock, karl-gung, karl-fall och karl-bak i Sopors index.html. */
class BinLoaderTest {
    // Tidslinjen

    @Test
    fun lockVilarOchOppnas() {
        assertEquals(0.0, BinLoaderTimeline.lidAngle(0.0))
        assertEquals(0.0, BinLoaderTimeline.lidAngle(0.14))
        assertEquals(38.0, BinLoaderTimeline.lidAngle(0.30))
        assertEquals(33.0, BinLoaderTimeline.lidAngle(0.38))
        assertEquals(33.0, BinLoaderTimeline.lidAngle(0.5))
        assertEquals(33.0, BinLoaderTimeline.lidAngle(0.58))
        assertEquals(0.0, BinLoaderTimeline.lidAngle(0.67))
        assertEquals(0.0, BinLoaderTimeline.lidAngle(1.0))
    }

    @Test
    fun lockOppnasMjuktMellanNyckelbilderna() {
        // Mellan 14 % och 30 % ligger vinkeln mellan 0 och 38 och stiger hela vägen.
        val steps = (14..30).map { BinLoaderTimeline.lidAngle(it / 100.0) }
        assertTrue(steps.zipWithNext().all { (a, b) -> a <= b })
        // cubic-bezier(.2, .8, .3, 1) är snabb i början: halvvägs i tid är locket över halvvägs upp.
        assertTrue(BinLoaderTimeline.lidAngle(0.22) > 19)
        // 30 till 38 % faller från 38 till 33 grader med ease-in-out, 34 % ligger i mitten.
        assertTrue(abs(BinLoaderTimeline.lidAngle(0.34) - 35.5) < 0.01)
        // 58 till 67 % stänger locket med cubic-bezier(.6, 0, 1, .6), som börjar långsamt.
        assertTrue(BinLoaderTimeline.lidAngle(0.625) > 16.5)
    }

    @Test
    fun lockBakOchFram() {
        assertFalse(BinLoaderTimeline.lidIsBehindBody(0.0))
        assertFalse(BinLoaderTimeline.lidIsBehindBody(0.159))
        assertTrue(BinLoaderTimeline.lidIsBehindBody(0.16))
        assertTrue(BinLoaderTimeline.lidIsBehindBody(0.659))
        assertFalse(BinLoaderTimeline.lidIsBehindBody(0.66))
        assertFalse(BinLoaderTimeline.lidIsBehindBody(0.99))
    }

    @Test
    fun karletGungar() {
        assertEquals(0.0, BinLoaderTimeline.bodySway(0.0))
        assertEquals(0.0, BinLoaderTimeline.bodySway(0.14))
        assertEquals(-3.0, BinLoaderTimeline.bodySway(0.30))
        assertEquals(-3.0, BinLoaderTimeline.bodySway(0.62))
        assertEquals(3.0, BinLoaderTimeline.bodySway(0.72))
        assertEquals(-1.5, BinLoaderTimeline.bodySway(0.82))
        assertEquals(0.5, BinLoaderTimeline.bodySway(0.91))
        assertEquals(0.0, BinLoaderTimeline.bodySway(1.0))
    }

    @Test
    fun slingaHarRattPeriod() {
        assertEquals(1.8, BinLoaderTimeline.PERIOD)
        assertTrue(abs(BinLoaderTimeline.progress(1.8 * 3 + 0.9) - 0.5) < 1e-9)
    }

    @Test
    fun fraktionenFallerOchFaderUt() {
        val p = BinLoaderTimeline.PERIOD
        // Osynlig vid vila och precis före 9 % av 5,4 s.
        assertEquals(0.0, BinLoaderTimeline.fractionState(0.0).opacity)
        // Ovanför kärlet vid 11 till 13 % av 5,4 s, det vill säga 33 till 39 % av första varvet.
        val top = BinLoaderTimeline.fractionState(0.36 * p)
        assertTrue(top.index == 0 && top.opacity == 1.0)
        assertTrue(top.x == 172.0 && top.y == -96.0 && top.rotation == -8.0)
        // Halvvägs i toningen (10 % av 5,4 s).
        assertTrue(abs(BinLoaderTimeline.fractionState(0.30 * p).opacity - 0.5) < 1e-9)
        // Nere i kärlet vid 20 %, sedan borta vid 20,5 %.
        val bottom = BinLoaderTimeline.fractionState(0.6 * p)
        assertTrue(bottom.opacity == 1.0 && bottom.y == 140.0 && bottom.rotation == 6.0)
        assertEquals(0.0, BinLoaderTimeline.fractionState(0.615 * p).opacity)
        assertEquals(0.0, BinLoaderTimeline.fractionState(0.9 * p).opacity)
        // Faller med cubic-bezier(.5, 0, 1, .7): långsamt i början.
        val early = BinLoaderTimeline.fractionState(0.47 * p)
        assertTrue(early.y < -96 + (140 + 96) * 0.5)
    }

    @Test
    fun fraktionernaVaxlarOverTreVarv() {
        val p = BinLoaderTimeline.PERIOD
        val kinds = (0 until 7).map { BinLoaderTimeline.fractionState((it + 0.36) * p).index }
        assertEquals(listOf(0, 1, 2, 0, 1, 2, 0), kinds)
        // Varje varv ser likadant ut.
        val a = BinLoaderTimeline.fractionState(0.5 * p)
        val b = BinLoaderTimeline.fractionState(1.5 * p)
        assertTrue(abs(a.y - b.y) < 1e-9 && abs(a.opacity - b.opacity) < 1e-9 && a.index != b.index)
    }

    @Test
    fun textenTonarInOchUt() {
        assertEquals(0.0, BinLoaderTimeline.textOpacity(0.0))
        assertEquals(1.0, BinLoaderTimeline.textOpacity(0.54))
        assertEquals(1.0, BinLoaderTimeline.textOpacity(1.8))
        assertTrue(abs(BinLoaderTimeline.textOpacity(3.6 - 0.54) - 1) < 1e-9)
        assertTrue(abs(BinLoaderTimeline.textOpacity(3.6)) < 1e-9)
        assertEquals(3.6, BinLoaderTimeline.TEXT_PERIOD)
        assertEquals(0, BinLoaderTimeline.textCycle(3.59))
        assertEquals(1, BinLoaderTimeline.textCycle(3.6))
    }

    @Test
    fun inToningenStartarEfter300ms() {
        assertEquals(0.0, BinLoaderTimeline.appearOpacity(0.0))
        assertEquals(0.0, BinLoaderTimeline.appearOpacity(0.3))
        assertEquals(1.0, BinLoaderTimeline.appearOpacity(0.55))
        val mid = BinLoaderTimeline.appearOpacity(0.425)
        assertTrue(mid > 0.5 && mid < 1) // ease-out
    }

    // Ett varv i tomt läge

    @Test
    fun ettVarvTar18Sekunder() {
        assertEquals(1.8, BinLoaderTimeline.ROUND_DURATION)
        assertTrue(BinLoaderTimeline.isPlayingRound(0.0, reduceMotion = false))
        assertTrue(BinLoaderTimeline.isPlayingRound(1.79, reduceMotion = false))
        assertFalse(BinLoaderTimeline.isPlayingRound(1.8, reduceMotion = false))
        assertFalse(BinLoaderTimeline.isPlayingRound(-0.1, reduceMotion = false))
    }

    @Test
    fun varvetFoljerSlingansForstaVarv() {
        // Mitt i varvet är locket öppet och fraktionen syns, som i slingans första varv.
        val pose = BinLoaderTimeline.roundPose(round = 0, elapsed = 0.36 * 1.8, reduceMotion = false)
        assertEquals(BinLoaderTimeline.lidAngle(0.36), pose.lidAngle)
        assertTrue(pose.lidIsBehindBody)
        assertEquals(-3.0, pose.bodySway)
        assertTrue(pose.fraction.opacity == 1.0 && pose.fraction.index == 0)
    }

    @Test
    fun slutlagetArStangtLock() {
        for (elapsed in listOf(1.8, 2.5, 100.0)) {
            assertEquals(BinLoaderTimeline.Pose.RESTING, BinLoaderTimeline.roundPose(round = 4, elapsed = elapsed, reduceMotion = false))
        }
        // Före start står det också still.
        assertEquals(BinLoaderTimeline.Pose.RESTING, BinLoaderTimeline.roundPose(round = 0, elapsed = -1.0, reduceMotion = false))
        assertEquals(0.0, BinLoaderTimeline.Pose.RESTING.lidAngle)
        assertFalse(BinLoaderTimeline.Pose.RESTING.lidIsBehindBody)
        assertEquals(0.0, BinLoaderTimeline.Pose.RESTING.bodySway)
        assertEquals(0.0, BinLoaderTimeline.Pose.RESTING.fraction.opacity)
        // Precis före slutet är locket redan stängt och kärlet nästan stilla.
        val end = BinLoaderTimeline.roundPose(round = 0, elapsed = 1.799, reduceMotion = false)
        assertTrue(end.lidAngle == 0.0 && !end.lidIsBehindBody && abs(end.bodySway) < 0.01)
    }

    @Test
    fun nastaVarvGerNastaFraktion() {
        val kinds = (0 until 4).map { BinLoaderTimeline.roundPose(round = it, elapsed = 0.36 * 1.8, reduceMotion = false).fraction.index }
        assertEquals(listOf(0, 1, 2, 0), kinds)
    }

    @Test
    fun reduceraRorelseGerIngetVarv() {
        assertFalse(BinLoaderTimeline.isPlayingRound(0.5, reduceMotion = true))
        for (elapsed in listOf(0.0, 0.36 * 1.8, 1.0, 1.8)) {
            assertEquals(BinLoaderTimeline.Pose.RESTING, BinLoaderTimeline.roundPose(round = 1, elapsed = elapsed, reduceMotion = true))
        }
    }

    // Texterna

    @Test
    fun texternaStammerMedWebben() {
        assertTrue("Plattar till pizzakartongen…" in BinLoaderTexts.ALL)
        assertEquals(22, BinLoaderTexts.ALL.size)
        assertEquals("Slänger rester från middagen…", BinLoaderTexts.ALL.first())
        assertEquals("Sorterar som ett proffs…", BinLoaderTexts.ALL[20])
        assertEquals("Tjabba, tjena hallå! /Louie", BinLoaderTexts.ALL.last())
    }

    @Test
    fun textBytsAldrigTillSamma() {
        val random = Random.Default
        var current = BinLoaderTexts.ALL[0]
        repeat(100) {
            val next = BinLoaderTexts.next(after = current, random = random)
            assertNotEquals(current, next)
            assertTrue(next in BinLoaderTexts.ALL)
            current = next
        }
    }

    @Test
    fun koVisarAllaInnanNagonUpprepas() {
        val queue = BinLoaderTexts.Queue()
        var previous: String? = null
        repeat(5) {
            val round = BinLoaderTexts.ALL.indices.map { queue.next(Random.Default) }
            assertEquals(BinLoaderTexts.ALL.size, round.toSet().size)
            assertNotEquals(previous, round.first())
            previous = round.last()
        }
    }

    @Test
    fun koBytsAldrigTillSammaIEnFoljd() {
        val queue = BinLoaderTexts.Queue()
        var last = queue.next(Random.Default)
        repeat(500) {
            val next = queue.next(Random.Default)
            assertNotEquals(last, next)
            last = next
        }
    }
}
