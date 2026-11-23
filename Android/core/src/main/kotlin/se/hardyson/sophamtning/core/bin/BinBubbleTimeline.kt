package se.hardyson.sophamtning.core.bin

import kotlin.math.max
import kotlin.math.min

/**
 * Tidslinjen för pratbubblan som kommer från kärlet vid ett tryck, som `BinBubbleTimeline` på iOS. Rena funktioner av tid
 * i sekunder. Bubblan tonas in, svävar och tonas bort, cirka 2 sekunder i allt. Utan animationer tonas den bara in och ut
 * på plats.
 */
object BinBubbleTimeline {
    /** Hur länge bubblan syns. */
    const val DURATION = 2.0

    /** Toningen in, och samtidigt växer den till full storlek. */
    const val FADE_IN = 0.2

    /** Toningen bort, sist. */
    const val FADE_OUT = 0.5

    /** Hur långt bubblan svävar, i dp, under hela tiden. */
    const val RISE_DISTANCE = 28.0

    /** Storleken när bubblan börjar tonas in. */
    private const val START_SCALE = 0.85

    /** Luften mellan spetsen och det den pekar på, i dp. */
    private const val TIP_GAP = 4.0

    /** Sant medan bubblan syns, [elapsed] sekunder efter trycket. */
    fun isShowing(elapsed: Double): Boolean = elapsed >= 0 && elapsed < DURATION

    fun opacity(elapsed: Double): Double {
        if (!isShowing(elapsed)) return 0.0
        if (elapsed < FADE_IN) return CubicBezier.EASE_OUT.value(elapsed / FADE_IN)
        val left = DURATION - elapsed
        if (left < FADE_OUT) return CubicBezier.EASE_IN_OUT.value(left / FADE_OUT)
        return 1.0
    }

    /** Hur långt bubblan har svävat, i dp. Snabbast i början och mjukt mot slutet. */
    fun rise(elapsed: Double, reduceMotion: Boolean): Double {
        if (reduceMotion) return 0.0
        val t = min(max(elapsed / DURATION, 0.0), 1.0)
        return RISE_DISTANCE * CubicBezier(0.2, 0.6, 0.4, 1.0).value(t)
    }

    fun scale(elapsed: Double, reduceMotion: Boolean): Double {
        if (reduceMotion) return 1.0
        val t = min(max(elapsed / FADE_IN, 0.0), 1.0)
        return START_SCALE + (1 - START_SCALE) * CubicBezier.EASE_OUT.value(t)
    }

    /** Var bubblan står i förhållande till kärlet. */
    enum class Placement {
        /** Spetsen strax ovanför locket, i den tomma ytan där fraktionen faller. */
        OverLid,

        /** Spetsen ovanför kärlets hela ram. */
        AboveBin,

        /**
         * Spetsen under kärlets ram, och bubblan växer nedåt. För kärlet i rubriken och i tomt läge, där fältet ovanför
         * annars döljer bubblan.
         */
        BelowBin;

        /** Sant när bubblan står under kärlet och spetsen pekar uppåt. */
        val isBelow: Boolean get() = this == BelowBin
    }

    /**
     * Var spetsen står, i dp från kärlets överkant (negativt är ovanför). Locket börjar vid y 150 i kärlets 360 × 560 (y 40
     * i SVG:ns viewBox, som börjar vid y -110).
     */
    fun tipY(binWidth: Double, placement: Placement): Double = when (placement) {
        Placement.OverLid -> binWidth * 150 / 360 - TIP_GAP
        Placement.AboveBin -> -TIP_GAP
        Placement.BelowBin -> binWidth * 560 / 360 + TIP_GAP
    }

    /**
     * Om ett tryck på kärlet startar ett nytt varv. Varje tryck ger en ny bubbla, men ett pågående varv får spela klart,
     * så att kärlet inte hoppar mitt i rörelsen. Utan animationer spelas inget varv.
     *
     * @param roundElapsed sekunder sedan det senaste varvet startade, eller `null` om inget har spelats.
     */
    fun startsRound(roundElapsed: Double?, reduceMotion: Boolean): Boolean {
        if (reduceMotion) return false
        if (roundElapsed == null) return true
        return !BinLoaderTimeline.isPlayingRound(roundElapsed, reduceMotion)
    }
}
