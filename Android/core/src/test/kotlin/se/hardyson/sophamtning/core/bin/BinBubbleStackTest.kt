package se.hardyson.sophamtning.core.bin

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Flera pratbubblor samtidigt: varje tryck lägger till en, och var och en syns sin egen tid. Tiderna är i sekunder. */
class BinBubbleStackTest {
    private val start = 1000.0

    @Test
    fun varjeTryckLaggerTillEnBubbla() {
        val stack = BinBubbleStack().add("Ett", start).add("Två", start + 0.3)
        // Äldst först, så att den nyaste står närmast kärlet.
        assertEquals(listOf("Ett", "Två"), stack.bubbles.map { it.text })
        assertEquals(2, stack.bubbles.map { it.id }.toSet().size)
    }

    @Test
    fun varjeBubblaSynsSinEgenTid() {
        var stack = BinBubbleStack().add("Ett", start).add("Två", start + 1)
        // Den första har visats klart, den andra syns kvar.
        stack = stack.removeExpired(start + BinBubbleTimeline.DURATION)
        assertEquals(listOf("Två"), stack.bubbles.map { it.text })
        stack = stack.removeExpired(start + 1 + BinBubbleTimeline.DURATION)
        assertTrue(stack.bubbles.isEmpty())
    }

    @Test
    fun nastaBubblaSomTonasBortStyrKlockan() {
        assertNull(BinBubbleStack().nextExpiry)
        val stack = BinBubbleStack().add("Ett", start).add("Två", start + 0.5)
        assertEquals(start + BinBubbleTimeline.DURATION, stack.nextExpiry)
    }

    @Test
    fun hogstTreBubblorSamtidigt() {
        var stack = BinBubbleStack()
        for ((index, text) in listOf("Ett", "Två", "Tre", "Fyra").withIndex()) {
            stack = stack.add(text, start + index * 0.1)
        }
        // Den äldsta får lämna plats.
        assertEquals(3, BinBubbleStack.MAX_COUNT)
        assertEquals(listOf("Två", "Tre", "Fyra"), stack.bubbles.map { it.text })
    }

    @Test
    fun enUtgangenBubblaForsvinnerNarEnNyLaggsTill() {
        val stack = BinBubbleStack().add("Ett", start).add("Två", start + 5)
        assertEquals(listOf("Två"), stack.bubbles.map { it.text })
    }
}
