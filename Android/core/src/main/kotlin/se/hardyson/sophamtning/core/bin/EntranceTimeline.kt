package se.hardyson.sophamtning.core.bin

import java.time.Instant

/**
 * Hur korten och listorna kommer in, som `EntranceTimeline` på iOS. Rena värden i sekunder och dp, så att fördelningen
 * kan testas.
 */
object EntranceTimeline {
    /** Sträckan ett kort på hemskärmen glider. */
    const val CARD_DISTANCE = 24.0
    const val CARD_DURATION = 0.45
    private const val CARD_STAGGER = 0.06

    /** Sträckan en rad i en lista glider. */
    const val ROW_DISTANCE = 14.0
    const val ROW_DURATION = 0.32
    private const val ROW_STAGGER = 0.04

    /** Bara de första raderna kommer in en efter en. Resten står stilla från början, så att långa listor inte väntar. */
    const val ROW_LIMIT = 8

    fun cardDelay(index: Int, reduceMotion: Boolean): Double = if (reduceMotion) 0.0 else index * CARD_STAGGER

    fun rowDelay(index: Int, reduceMotion: Boolean): Double = if (reduceMotion) 0.0 else minOf(index, ROW_LIMIT - 1) * ROW_STAGGER

    fun animatesRow(index: Int): Boolean = index < ROW_LIMIT

    /** Utan animationer glider inget, och allt är en enkel toning. */
    fun offset(distance: Double, reduceMotion: Boolean): Double = if (reduceMotion) 0.0 else distance

    /** När kalenderbladet ska börja vändas, räknat från att korten startade: när kortet kommit in. */
    fun flipDelay(cardIndex: Int, reduceMotion: Boolean): Double =
        cardDelay(cardIndex, reduceMotion) + if (reduceMotion) 0.2 else CARD_DURATION
}

/** Hemskärmens start: korten väntar på introt, kommer in en gång, och sedan är det klart för resten av processen. */
class StartEntrance private constructor(private val phase: Phase) {
    private sealed interface Phase {
        data object Waiting : Phase
        data class Running(val begin: Instant) : Phase
        data object Finished : Phase
    }

    constructor(plays: Boolean) : this(if (plays) Phase.Waiting else Phase.Finished)

    /** Sant medan korten väntar på att få komma in. */
    val hidesCards: Boolean get() = phase == Phase.Waiting

    /** När korten startade, medan de håller på. */
    val begin: Instant? get() = (phase as? Phase.Running)?.begin

    /** Kalenderbladet får bara vändas som en del av starten. */
    val allowsOpeningFlip: Boolean get() = phase != Phase.Finished

    /** Startar korten. Har de redan startat eller är klara händer inget. */
    fun start(at: Instant): StartEntrance = if (phase == Phase.Waiting) StartEntrance(Phase.Running(at)) else this

    /** Starten är klar, eller ska inte spelas alls. Går aldrig tillbaka. */
    fun finish(): StartEntrance = StartEntrance(Phase.Finished)

    override fun equals(other: Any?) = other is StartEntrance && other.phase == phase

    override fun hashCode() = phase.hashCode()

    companion object {
        /** Hemskärmens kort kommer in en gång per process, aldrig i UI-tester. */
        fun shouldPlay(skipsIntro: Boolean, alreadyPlayed: Boolean): Boolean = !skipsIntro && !alreadyPlayed
    }
}

/** Minns vilka listor som redan visats i den här processen, så att de inte kommer in på nytt vid retur. */
class ShownOnce<K> {
    private val shown = mutableSetOf<K>()

    fun shouldPlay(key: K): Boolean = key !in shown

    fun markShown(key: K) {
        shown += key
    }
}

/** Gemensamma rörelser. Utan animationer blir alla en enkel, kort toning, som `Motion` på iOS. */
object Motion {
    /** Något som fälls ut eller ihop. Utan animationer fälls det ut direkt, så att innehållet under inte glider. */
    fun expands(reduceMotion: Boolean): Boolean = !reduceMotion
}

/** Hur knappar och rader fjädrar när de trycks ned. Utan animationer tonas de lite i stället. */
object PressMotion {
    fun scale(pressed: Boolean, reduceMotion: Boolean): Double = if (pressed && !reduceMotion) 0.96 else 1.0

    fun opacity(pressed: Boolean, reduceMotion: Boolean): Double = if (pressed && reduceMotion) 0.7 else 1.0
}
