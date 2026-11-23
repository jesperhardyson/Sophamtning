package se.hardyson.sophamtning.core.bin

import kotlin.test.Test
import kotlin.test.assertEquals

/** Kärlet i tomt läge växer med textstorleken, men högst till 200 dp, så att sökfältet inte trycks långt ned. */
class BinRoundWidthTest {
    @Test
    fun normalStorlekArOforandrad() {
        assertEquals(135.0, BinRound.drawnWidth(scaled = 135.0))
    }

    @Test
    fun storstaTextenStannarVid200() {
        assertEquals(200.0, BinRound.MAX_WIDTH)
        assertEquals(200.0, BinRound.drawnWidth(scaled = 200.0))
        assertEquals(200.0, BinRound.drawnWidth(scaled = 320.0))
    }
}
