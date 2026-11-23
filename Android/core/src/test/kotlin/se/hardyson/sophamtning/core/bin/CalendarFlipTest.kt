package se.hardyson.sophamtning.core.bin

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat

/** Kalenderbladets bläddring, som CalendarFlipTests på iOS. */
class CalendarFlipTest {
    private fun day(text: String) = DayDate.parse(text)!!

    /** Som `stride(from:through:by:)` i Swift, utan att felet i flyttalen växer. */
    private fun stride(from: Double, through: Double, by: Double): List<Double> {
        val count = ((through - from) / by + 1e-9).toInt()
        return (0..count).map { from + it * by }
    }

    // Start och datum

    @Test
    fun vidStartVandsBladetFranDagensDatumTillTomningsdagen() {
        val today = day("2026-11-07")
        assertEquals(today, CalendarFlipTimeline.openingDate(today = today, pickup = day("2026-11-12")))
        assertEquals(today, CalendarFlipTimeline.openingDate(today = today, pickup = day("2026-11-08")))
    }

    @Test
    fun tomningIDagVandsInte() {
        val today = day("2026-11-07")
        assertNull(CalendarFlipTimeline.openingDate(today = today, pickup = today))
    }

    @Test
    fun ettBladPerDagUpptillAtta() {
        val from = day("2026-11-07")
        assertEquals(listOf(day("2026-11-08")), CalendarFlipTimeline.dates(from, day("2026-11-08"), reduceMotion = false))
        assertEquals(
            listOf("2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11"),
            CalendarFlipTimeline.dates(from, day("2026-11-11"), reduceMotion = false).map { it.iso },
        )
        assertEquals((1..8).map { from.plusDays(it) }, CalendarFlipTimeline.dates(from, day("2026-11-15"), reduceMotion = false))
    }

    @Test
    fun flerDagarGerAttaJamntFordeladeBladDarSistaArTomningsdagen() {
        val from = day("2026-11-07")
        for (days in listOf(9, 13, 20, 30, 31, 90)) {
            val to = from.plusDays(days)
            val dates = CalendarFlipTimeline.dates(from, to, reduceMotion = false)
            assertEquals(8, dates.size, "$days dagar")
            assertEquals(to, dates.last(), "$days dagar")
            val steps = (listOf(from) + dates).zip(dates).map { (a, b) -> a.daysUntil(b) }
            assertTrue(steps.all { it >= 1 }, "$days dagar")
            assertTrue(steps.max() - steps.min() <= 1, "jämnt fördelade, $days dagar: $steps")
        }
    }

    @Test
    fun bakatOchReduceraRorelseGerEttBlad() {
        assertEquals(listOf(day("2026-11-07")), CalendarFlipTimeline.dates(day("2026-11-12"), day("2026-11-07"), reduceMotion = false))
        assertEquals(listOf(day("2027-01-20")), CalendarFlipTimeline.dates(day("2026-11-07"), day("2027-01-20"), reduceMotion = true))
    }

    // Start per blad och total tid

    @Test
    fun bladenStartarCirkaVar60eMsOchBromsarIn() {
        val four = CalendarFlipTimeline.starts(4)
        assertEquals(4, four.size)
        assertEquals(0.0, four[0])
        assertTrue(abs(four[1] - 0.06) < 0.0001)
        val gaps = four.zipWithNext { a, b -> b - a }
        assertTrue(gaps.zipWithNext().all { (a, b) -> a < b }, "mellanrummen växer: $gaps")
        assertTrue(abs(gaps.last() - 1.5 * gaps.first()) < 0.0001)
        assertEquals(listOf(0.0), CalendarFlipTimeline.starts(1))
        assertEquals(listOf(0.0, 0.06), CalendarFlipTimeline.starts(2))
    }

    @Test
    fun ettBladTarEnKvartsSekundOchAllaHogst06() {
        assertEquals(0.25, CalendarFlipTimeline.FOLD_DURATION)
        assertEquals(0.25, CalendarFlipTimeline.duration(1))
        assertTrue(abs(CalendarFlipTimeline.duration(4) - 0.475) < 0.0001)
        assertTrue(abs(CalendarFlipTimeline.duration(8) - 0.6) < 0.0001)
        var previous = 0.0
        for (pages in 1..8) {
            val total = CalendarFlipTimeline.duration(pages)
            assertTrue(total <= 0.6 + 0.0001, "$pages blad")
            assertTrue(total >= previous, "fler blad tar aldrig kortare tid, $pages blad")
            previous = total
        }
        assertEquals(0.6, CalendarFlipTimeline.LONGEST)
    }

    @Test
    fun attaBladHarAndaSynligaMellanrum() {
        val gaps = CalendarFlipTimeline.starts(8).zipWithNext { a, b -> b - a }
        assertTrue(gaps.min() >= 0.035, "$gaps")
        assertTrue(gaps.last() > gaps.first())
    }

    @Test
    fun klartEfterLangden() {
        assertFalse(CalendarFlipTimeline.isFinished(0.47, 4))
        assertTrue(CalendarFlipTimeline.isFinished(0.475, 4))
        assertTrue(CalendarFlipTimeline.isFinished(0.4, 4, reduceMotion = true))
        assertFalse(CalendarFlipTimeline.isFinished(0.39, 4, reduceMotion = true))
    }

    // Överst och under

    @Test
    fun foreStartenLiggerForstaBladetEnsamt() {
        for (t in listOf(-0.5, 0.0)) {
            val layers = CalendarFlipTimeline.layers(t, 4)
            assertEquals(0, layers.under)
            assertTrue(layers.folds.isEmpty())
            assertEquals(0, layers.top)
        }
    }

    @Test
    fun nastaBladLiggerRedanUnderDetSomViks() {
        // 0,03 s: blad 0 viks, blad 1 ligger under.
        val early = CalendarFlipTimeline.layers(0.03, 4)
        assertEquals(listOf(0), early.folds.map { it.sheet })
        assertEquals(1, early.under)
        assertEquals(0, early.top)
        // 0,15 s: tre blad viks samtidigt och överlappar, blad 3 ligger under.
        val mid = CalendarFlipTimeline.layers(0.15, 4)
        assertEquals(listOf(0, 1, 2), mid.folds.map { it.sheet })
        assertEquals(3, mid.under)
        assertTrue(mid.folds[0].progress > mid.folds[1].progress)
        // Det sista bladet viks och tömningsdagen ligger under.
        val late = CalendarFlipTimeline.layers(0.4, 4)
        assertEquals(listOf(3), late.folds.map { it.sheet })
        assertEquals(4, late.under)
    }

    @Test
    fun varjeTidpunktHarEttBladUnderSomInteViks() {
        for (pages in 1..8) {
            val total = CalendarFlipTimeline.duration(pages)
            for (t in stride(-0.05, total + 0.05, 0.001)) {
                val layers = CalendarFlipTimeline.layers(t, pages)
                assertTrue(layers.under in 0..pages)
                assertTrue(layers.folds.all { it.sheet < layers.under && it.progress > 0 && it.progress < 1 })
            }
        }
    }

    @Test
    fun efterSlutetLiggerTomningsdagenEnsam() {
        val layers = CalendarFlipTimeline.layers(CalendarFlipTimeline.duration(8), 8)
        assertEquals(8, layers.under)
        assertTrue(layers.folds.isEmpty())
    }

    @Test
    fun varjeDatumLiggerOverstIOrdningOchSistaArTomningsdagen() {
        val from = day("2026-11-07")
        val dates = CalendarFlipTimeline.dates(from, day("2026-11-11"), reduceMotion = false)
        val total = CalendarFlipTimeline.duration(dates.size)
        val underDates = mutableListOf<DayDate>()
        for (t in stride(-0.1, total + 0.1, 0.001)) {
            val under = CalendarFlipTimeline.dateOfSheet(CalendarFlipTimeline.layers(t, dates.size).under, from, dates)
            if (underDates.lastOrNull() != under) underDates += under
        }
        assertEquals(listOf(from) + dates, underDates)
        assertEquals(day("2026-11-11"), CalendarFlipTimeline.shownDate(total, from, dates))
        assertEquals(from, CalendarFlipTimeline.shownDate(0.0, from, dates))
    }

    @Test
    fun manadsradenFoljerMedOverManadsskiftet() {
        val from = day("2026-11-07")
        val dates = CalendarFlipTimeline.dates(from, day("2026-12-07"), reduceMotion = false)
        val shown = (0..dates.size).map { CalendarFlipTimeline.dateOfSheet(it, from, dates) }
        assertEquals(from, shown.first())
        assertEquals(day("2026-12-07"), shown.last())
        assertEquals(setOf("NOV", "DEC"), shown.map { SwedishFormat.monthUppercased(it) }.toSet())
    }

    // Vinkel och toning

    @Test
    fun bladetViksUppFranRaktTillKanten() {
        assertEquals(0.0, CalendarFlipTimeline.angle(0.0))
        assertEquals(90.0, CalendarFlipTimeline.angle(1.0))
        val angles = stride(0.0, 1.0, 0.05).map { CalendarFlipTimeline.angle(it) }
        assertTrue(angles.zipWithNext().all { (a, b) -> a <= b })
    }

    @Test
    fun reduceraRorelseGerEnToning() {
        assertEquals(1.0, CalendarFlipTimeline.opacity(0.0))
        assertEquals(0.0, CalendarFlipTimeline.opacity(0.2))
        assertEquals(1.0, CalendarFlipTimeline.opacity(0.4))
        val from = day("2026-11-07")
        val to = day("2026-11-11")
        assertEquals(from, CalendarFlipTimeline.fadedDate(0.19, from, to))
        assertEquals(to, CalendarFlipTimeline.fadedDate(0.2, from, to))
        assertEquals(0.4, CalendarFlipTimeline.duration(8, reduceMotion = true))
    }

    // Vibrationer

    @Test
    fun enLattVibrationPerBladOchEnTydligareNarDetLandar() {
        for (pages in listOf(1, 4, 8)) {
            val haptics = CalendarFlipTimeline.haptics(pages, reduceMotion = false)
            assertEquals(pages, haptics.count { it.kind == CalendarFlipTimeline.Haptic.Kind.Page })
            assertEquals(1, haptics.count { it.kind == CalendarFlipTimeline.Haptic.Kind.Landing })
            assertEquals(CalendarFlipTimeline.Haptic(CalendarFlipTimeline.duration(pages), CalendarFlipTimeline.Haptic.Kind.Landing), haptics.last())
            assertEquals(CalendarFlipTimeline.starts(pages), haptics.filter { it.kind == CalendarFlipTimeline.Haptic.Kind.Page }.map { it.time })
        }
    }

    @Test
    fun ingenVibrationMedReduceraRorelse() {
        assertTrue(CalendarFlipTimeline.haptics(4, reduceMotion = true).isEmpty())
    }
}
