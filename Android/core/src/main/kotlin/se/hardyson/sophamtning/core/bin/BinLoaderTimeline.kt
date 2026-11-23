package se.hardyson.sophamtning.core.bin

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Tidslinjen för kärlets laddningsanimation, som `BinLoaderTimeline` på iOS. Allt är rena funktioner av tid i sekunder,
 * kopierade från CSS:en `karl-gung`, `karl-lock`, `karl-bak`, `karl-fram`, `karl-fall` och `karl-text` i Sopors
 * `index.html`. Vyn ritar om från klockan, så inget animationstillstånd behöver bevaras mellan bildrutor.
 */
object BinLoaderTimeline {
    /** En slinga (`--p: 1.8s`). */
    const val PERIOD = 1.8

    /** Fraktionerna cyklar över tre varv (`calc(var(--p) * 3)`). */
    private const val FRACTION_CYCLE = PERIOD * 3

    /** Texten står i 3,6 sekunder (`karl-text 3.6s`), med 15 % toning in och ut, alltså 0,54 s. */
    const val TEXT_PERIOD = 3.6

    /** Fördröjningen innan allt tonar in, och hur länge toningen tar (`karl-in .25s ease-out .3s`). */
    const val APPEAR_DELAY = 0.3
    const val APPEAR_DURATION = 0.25

    /** Hur långt in i slingan (0 till under 1) en tidpunkt är. */
    fun progress(elapsed: Double): Double {
        val value = (elapsed % PERIOD) / PERIOD
        return if (value < 0) value + 1 else value
    }

    // Lock och kropp

    /** Lockets vinkel i grader runt gångjärnet (`karl-lock`). [progress] är 0 till 1 genom slingan. */
    fun lidAngle(progress: Double): Double {
        val p = clamp(progress)
        val slow = CubicBezier(0.2, 0.8, 0.3, 1.0)
        val close = CubicBezier(0.6, 0.0, 1.0, 0.6)
        return when {
            p < 0.14 -> 0.0
            p < 0.30 -> interpolate(0.0, 38.0, p, 0.14, 0.30, slow)
            p < 0.38 -> interpolate(38.0, 33.0, p, 0.30, 0.38, CubicBezier.EASE_IN_OUT)
            p < 0.58 -> 33.0
            p < 0.67 -> interpolate(33.0, 0.0, p, 0.58, 0.67, close)
            else -> 0.0
        }
    }

    /**
     * Locket ligger bakom kroppen när det är öppet och framför när det är stängt (`karl-bak` och `karl-fram`, båda
     * `step-end`): bakom från 16 % till 66 %.
     */
    fun lidIsBehindBody(progress: Double): Boolean {
        val p = clamp(progress)
        return p >= 0.16 && p < 0.66
    }

    /** Kroppens gungning i grader runt hjulens mitt (`karl-gung`, `ease-in-out` i varje steg). */
    fun bodySway(progress: Double): Double {
        val p = clamp(progress)
        val e = CubicBezier.EASE_IN_OUT
        return when {
            p < 0.14 -> 0.0
            p < 0.30 -> interpolate(0.0, -3.0, p, 0.14, 0.30, e)
            p < 0.62 -> -3.0
            p < 0.72 -> interpolate(-3.0, 3.0, p, 0.62, 0.72, e)
            p < 0.82 -> interpolate(3.0, -1.5, p, 0.72, 0.82, e)
            p < 0.91 -> interpolate(-1.5, 0.5, p, 0.82, 0.91, e)
            else -> interpolate(0.5, 0.0, p, 0.91, 1.0, e)
        }
    }

    // Fraktionen

    /**
     * En fraktions läge: [x] och [y] är förskjutningen i SVG:ns enheter, [rotation] i grader runt SVG:ns origo. [index]
     * 0, 1 och 2 följer ordningen mat, papper, plast som på webben.
     */
    data class FractionState(val index: Int, val opacity: Double, val x: Double, val y: Double, val rotation: Double)

    /**
     * Fraktionen som hör till tidpunkten (`karl-fall`). Varje fraktion har en cykel på tre varv och startar ett varv efter
     * den förra, så varje varv visas en ny. [elapsed] är sekunder sedan animationen startade.
     */
    fun fractionState(elapsed: Double): FractionState {
        val loop = max(0, floor(elapsed / PERIOD).toInt())
        val index = loop % 3
        // Fraktionens egen tid i cykeln: den startade vid början av sitt varv.
        val local = elapsed - loop * PERIOD
        val u = max(0.0, local) / FRACTION_CYCLE
        val startX = 172.0
        val startY = -96.0
        val startR = -8.0
        val endX = 172.0
        val endY = 140.0
        val endR = 6.0
        fun make(opacity: Double, x: Double, y: Double, r: Double) = FractionState(index, opacity, x, y, r)
        return when {
            u < 0.09 -> make(0.0, startX, startY, startR)
            // Linjär toning in (animation-timing-function: linear).
            u < 0.11 -> make(interpolate(0.0, 1.0, u, 0.09, 0.11, CubicBezier.LINEAR), startX, startY, startR)
            u < 0.13 -> make(1.0, startX, startY, startR)
            u < 0.20 -> {
                val t = CubicBezier(0.5, 0.0, 1.0, 0.7).value((u - 0.13) / 0.07)
                make(1.0, startX + (endX - startX) * t, startY + (endY - startY) * t, startR + (endR - startR) * t)
            }
            u < 0.205 -> make(interpolate(1.0, 0.0, u, 0.20, 0.205, CubicBezier.LINEAR), endX, endY, endR)
            else -> make(0.0, endX, endY, endR)
        }
    }

    // Hela kärlet i en bild

    /** Kärlets läge i en bild: locket, om det ligger bakom kroppen, gungningen och fraktionen. */
    data class Pose(val lidAngle: Double, val lidIsBehindBody: Boolean, val bodySway: Double, val fraction: FractionState) {
        companion object {
            /** Stilla med stängt lock och utan fraktion. */
            val RESTING = Pose(0.0, false, 0.0, FractionState(0, 0.0, 0.0, 0.0, 0.0))
        }
    }

    /** Slingans läge, [elapsed] sekunder efter att den startade. */
    fun loopPose(elapsed: Double): Pose {
        val p = progress(elapsed)
        return Pose(lidAngle(p), lidIsBehindBody(p), bodySway(p), fractionState(elapsed))
    }

    // Ett varv i tomt läge

    /** Ett varv i tomt läge är lika långt som ett varv i slingan. */
    const val ROUND_DURATION = PERIOD

    /** Sant medan ett varv pågår, [elapsed] sekunder efter att det startade. Utan animationer spelas inget varv. */
    fun isPlayingRound(elapsed: Double, reduceMotion: Boolean): Boolean = !reduceMotion && elapsed >= 0 && elapsed < ROUND_DURATION

    /**
     * Kärlets läge under ett varv. [round] räknar varven och ger fraktionen, så att varje varv visar nästa. Före och efter
     * varvet, och utan animationer, står kärlet stilla med stängt lock.
     */
    fun roundPose(round: Int, elapsed: Double, reduceMotion: Boolean): Pose {
        if (!isPlayingRound(elapsed, reduceMotion)) return Pose.RESTING
        // Samma bild som slingans varv nummer `round`, så att fraktionen byts likadant.
        return loopPose(max(round, 0) * PERIOD + elapsed)
    }

    // Text och inträde

    /** Textens opacitet (`karl-text`: 0 till 1 vid 15 %, 1 till 0 från 85 %, `ease-in-out`). */
    fun textOpacity(elapsed: Double): Double {
        val u = (elapsed % TEXT_PERIOD) / TEXT_PERIOD
        val e = CubicBezier.EASE_IN_OUT
        return when {
            u < 0.15 -> interpolate(0.0, 1.0, u, 0.0, 0.15, e)
            u < 0.85 -> 1.0
            else -> interpolate(1.0, 0.0, u, 0.85, 1.0, e)
        }
    }

    /** Vilken text som gäller: byts varje gång textens cykel börjar om (som `animationiteration` på webben). */
    fun textCycle(elapsed: Double): Int = max(0, floor(elapsed / TEXT_PERIOD).toInt())

    /** Hela animationens opacitet: osynlig i 300 ms och sedan 0,25 s `ease-out`, så att snabba svar inte blinkar. */
    fun appearOpacity(elapsed: Double): Double {
        val t = (elapsed - APPEAR_DELAY) / APPEAR_DURATION
        if (t <= 0) return 0.0
        if (t >= 1) return 1.0
        return CubicBezier.EASE_OUT.value(t)
    }

    private fun clamp(p: Double) = min(max(p, 0.0), 1.0)
}
