package se.hardyson.sophamtning.core.bin

/**
 * Pratbubblorna som syns just nu, som `BinBubbleStack` på iOS. Varje tryck lägger till en, och var och en syns sin egen
 * tid ([BinBubbleTimeline.DURATION]) räknat från sitt eget tryck. Högst [MAX_COUNT] åt gången, så att snabba tryck inte
 * täcker skärmen: blir de fler får den äldsta lämna plats. Tiderna är sekunder från vilken klocka som helst, så länge
 * samma klocka används hela vägen.
 */
data class BinBubbleStack(
    /** Äldst först, så att den nyaste står närmast kärlet. */
    val bubbles: List<Bubble> = emptyList(),
    private val nextId: Int = 0,
) {
    data class Bubble(val id: Int, val text: String, val start: Double)

    /** Med en bubbla till. Bubblor som redan visats klart tas bort, och den äldsta lämnar plats om de blir för många. */
    fun add(text: String, at: Double): BinBubbleStack {
        val kept = removeExpired(at).bubbles + Bubble(nextId, text, at)
        return BinBubbleStack(kept.takeLast(MAX_COUNT), nextId + 1)
    }

    /** Utan de bubblor som har visats klart. */
    fun removeExpired(at: Double): BinBubbleStack = copy(bubbles = bubbles.filter { BinBubbleTimeline.isShowing(at - it.start) })

    /** När nästa bubbla har tonats bort, eller `null` om ingen syns. Den äldsta försvinner först. */
    val nextExpiry: Double? get() = bubbles.firstOrNull()?.let { it.start + BinBubbleTimeline.DURATION }

    companion object {
        /** Flest bubblor samtidigt. */
        const val MAX_COUNT = 3
    }
}
