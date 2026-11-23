package se.hardyson.sophamtning.core.bin

import se.hardyson.sophamtning.core.dates.DayDate

/**
 * Tidslinjen när kalenderbladet bläddras som en blockkalender, från ett datum till ett annat, som `CalendarFlipTimeline`
 * på iOS. Rena funktioner av tid i sekunder, så att vyn ritar från klockan och en ny bläddring kan ta över mitt i en gammal.
 *
 * Bladen ligger i en bunt. Blad 0 är startdatumet och ligger överst, blad `n` är tömningsdagen och ligger underst. Bladen
 * 0 till `n - 1` viks upp kring överkanten, ett i taget men överlappande: ett nytt blad börjar cirka var 60:e ms, och
 * avståndet växer mot slutet, så att bläddringen bromsar in mot tömningsdagen. Nästa blad ligger alltid redan under det
 * som viks, så att inget blinkar. Ett blad tar 0,25 s och allt är klart inom 0,6 s. Utan animationer tonas brickan i
 * stället, en gång.
 */
object CalendarFlipTimeline {
    /** Tiden ett blad tar att vikas upp. */
    const val FOLD_DURATION = 0.25

    /** Tiden mellan de första bladen. */
    const val FIRST_GAP = 0.06

    /** Hur mycket längre det sista mellanrummet är än det första. */
    private const val SLOWDOWN = 1.5

    /** Den längsta bläddringen, med 8 blad. */
    const val LONGEST = 0.6

    /** Fler dagar än så bläddras med jämnt fördelade datum. */
    const val MAX_PAGES = 8

    /** Toningen utan animationer: ut och sedan in. */
    const val FADE_DURATION = 0.4

    private val foldCurve = CubicBezier(0.45, 0.0, 0.75, 1.0)

    /** Datumet bladet vänds från vid start: dagens datum, eller `null` om tömningen är i dag och inget ska vändas. */
    fun openingDate(today: DayDate, pickup: DayDate): DayDate? = if (today == pickup) null else today

    /**
     * Bladen som bläddras fram, i ordning. Det sista är alltid [to]. Ett blad per dag, och vid fler än 8 dagar 8 jämnt
     * fördelade datum. Ett datum bakåt, samma datum och utan animationer ger ett enda blad.
     */
    fun dates(from: DayDate, to: DayDate, reduceMotion: Boolean): List<DayDate> {
        val days = from.daysUntil(to)
        if (reduceMotion || days <= 1) return listOf(to)
        if (days <= MAX_PAGES) return (1..days).map { from.plusDays(it) }
        return (1..MAX_PAGES).map { from.plusDays((it * days + MAX_PAGES / 2) / MAX_PAGES) }
    }

    /** När varje blad börjar vikas upp, räknat från bläddringens start. Det första börjar direkt. */
    fun starts(pages: Int): List<Double> {
        val count = maxOf(pages, 1)
        if (count == 1) return listOf(0.0)
        // Mellanrummen växer jämnt från det första till det sista, så att farten bromsar in.
        val weights = (0 until count - 1).map { if (count == 2) 1.0 else 1 + (SLOWDOWN - 1) * it.toDouble() / (count - 2).toDouble() }
        val gap = minOf(FIRST_GAP, (LONGEST - FOLD_DURATION) / weights.fold(0.0) { sum, weight -> sum + weight })
        val starts = mutableListOf(0.0)
        for (weight in weights) starts += starts.last() + weight * gap
        return starts
    }

    /** Hela bläddringen: tills det sista bladet har vikts upp och tömningsdagen ligger kvar. Utan animationer toningen. */
    fun duration(pages: Int, reduceMotion: Boolean = false): Double =
        if (reduceMotion) FADE_DURATION else starts(pages).last() + FOLD_DURATION

    fun isFinished(elapsed: Double, pages: Int, reduceMotion: Boolean = false): Boolean =
        elapsed >= duration(pages, reduceMotion)

    /** Ett blad som håller på att vikas upp, och hur långt det kommit (0 till 1). */
    data class Fold(val sheet: Int, val progress: Double)

    /** Bladen som syns vid en tidpunkt: bladet som ligger stilla under, och bladen ovanpå som viks upp. */
    data class Layers(
        /** Det översta bladet som inte har börjat vikas. Det ligger under alla som viks. */
        val under: Int,
        /** Bladen som viks, överst först. */
        val folds: List<Fold>,
    ) {
        /** Bladet som ligger överst i bunten. */
        val top: Int get() = folds.firstOrNull()?.sheet ?: under
    }

    /** Vilka blad som syns vid en tidpunkt. Före starten ligger blad 0 ensamt, efter slutet blad [pages]. */
    fun layers(elapsed: Double, pages: Int): Layers {
        val count = maxOf(pages, 1)
        val folds = mutableListOf<Fold>()
        var under = count
        for ((sheet, start) in starts(count).withIndex()) {
            if (elapsed <= start) {
                under = sheet
                break
            }
            if (elapsed < start + FOLD_DURATION) folds += Fold(sheet, (elapsed - start) / FOLD_DURATION)
        }
        return Layers(under, folds)
    }

    /** Datumet på ett blad: startdatumet för blad 0, och sedan bladen i [dates]. */
    fun dateOfSheet(sheet: Int, from: DayDate, dates: List<DayDate>): DayDate =
        if (sheet == 0) from else dates[minOf(sheet, dates.size) - 1]

    /** Datumet på det översta bladet. */
    fun shownDate(elapsed: Double, from: DayDate, dates: List<DayDate>): DayDate =
        dateOfSheet(layers(elapsed, dates.size).top, from, dates)

    /**
     * Vinkeln i grader kring bladets överkant medan det viks upp: från 0 till 90, där det står på kanten och inte syns.
     * Positiv vinkel för underkanten mot betraktaren, som när man lyfter ett blad i en blockkalender.
     */
    fun angle(progress: Double): Double = 90 * foldCurve.value(progress.coerceIn(0.0, 1.0))

    /** Toningen utan animationer: bort i första halvan och in i andra. */
    fun opacity(elapsed: Double): Double {
        val half = FADE_DURATION / 2
        if (elapsed <= 0 || elapsed >= FADE_DURATION) return 1.0
        val curve = CubicBezier.EASE_IN_OUT
        if (elapsed < half) return 1 - curve.value(elapsed / half)
        return curve.value((elapsed - half) / half)
    }

    /** Datumet som syns utan animationer: startdatumet tills brickan har tonats bort. */
    fun fadedDate(elapsed: Double, from: DayDate, to: DayDate): DayDate = if (elapsed < FADE_DURATION / 2) from else to

    /** En vibration under bläddringen. */
    data class Haptic(val time: Double, val kind: Kind) {
        enum class Kind {
            /** Lätt, när ett blad börjar vikas. */
            Page,

            /** Tydligare, när det sista bladet har landat. */
            Landing,
        }
    }

    /** En lätt vibration per blad och en tydligare när tömningsdagen ligger kvar. Ingen utan animationer. */
    fun haptics(pages: Int, reduceMotion: Boolean): List<Haptic> {
        if (reduceMotion) return emptyList()
        return starts(pages).map { Haptic(it, Haptic.Kind.Page) } + Haptic(duration(pages), Haptic.Kind.Landing)
    }
}
