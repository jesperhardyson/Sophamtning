package se.hardyson.sophamtning.core.bin

import kotlin.math.min

/** Måtten för kärlet i tomt läge och bredvid rubriken, som `BinRoundView` på iOS. */
object BinRound {
    /** Största bredden i dp, så att sökfältet under kärlet inte trycks långt ned med största text. */
    const val MAX_WIDTH = 200.0

    /** Kärlets bredd: den skalade bredden, högst [maxWidth]. */
    fun drawnWidth(scaled: Double, maxWidth: Double = MAX_WIDTH): Double = min(scaled, maxWidth)
}
