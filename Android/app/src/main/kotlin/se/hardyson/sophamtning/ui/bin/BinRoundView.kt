package se.hardyson.sophamtning.ui.bin

import android.view.WindowManager
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import se.hardyson.sophamtning.LocalAppDependencies
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.core.bin.BinBubbleStack
import se.hardyson.sophamtning.core.bin.BinBubbleTimeline
import se.hardyson.sophamtning.core.bin.BinLoaderTexts
import se.hardyson.sophamtning.core.bin.BinLoaderTimeline
import se.hardyson.sophamtning.core.bin.BinRound

/** Testernas namn på kärlet och bubblorna. */
object BinTags {
    const val BIN = "karlet"
    const val BUBBLE = "pratbubbla"
}

/** Om kärlet spelar ett varv just nu. Bara för testerna, och läses aldrig av TalkBack. */
val BinRoundPlaying = SemanticsPropertyKey<Boolean>("BinRoundPlaying")
private var SemanticsPropertyReceiver.binRoundPlaying by BinRoundPlaying

/** Varven, bubblorna och klockan för ett kärl. Tiderna är sekunder från bildklockan. */
private class BinRoundState {
    /** Varvet som spelas eller spelades senast. Styr fraktionen. */
    var round by mutableIntStateOf(0)

    /** När det pågående varvet startade. `null` när kärlet står still. */
    var roundStart by mutableStateOf<Double?>(null)
    var playedFirst = false
    var bubbles by mutableStateOf(BinBubbleStack())

    /** Ingen text upprepas förrän alla visats, och två tryck i rad ger aldrig samma text. */
    val texts = BinLoaderTexts.Queue()

    /** Den senaste bilden. */
    var now by mutableDoubleStateOf(0.0)

    /** Texten som tillkännages för TalkBack, så länge en bubbla syns. */
    var announced by mutableStateOf<String?>(null)

    val animating: Boolean get() = roundStart != null || bubbles.bubbles.isNotEmpty()

    fun pose(reduceMotion: Boolean): BinLoaderTimeline.Pose =
        roundStart?.let { BinLoaderTimeline.roundPose(round, now - it, reduceMotion) } ?: BinLoaderTimeline.Pose.RESTING

    /** En ny bild: ett varv som är slut stannar, och bubblor som visats klart tas bort. */
    fun frame(time: Double) {
        now = time
        roundStart?.let { if (time - it >= BinLoaderTimeline.ROUND_DURATION) roundStart = null }
        if (bubbles.bubbles.any { !BinBubbleTimeline.isShowing(time - it.start) }) bubbles = bubbles.removeExpired(time)
        if (bubbles.bubbles.isEmpty()) announced = null
    }

    /** Tar bort bubblorna, till exempel när skärmen lämnas. */
    fun clearBubbles() {
        bubbles = bubbles.copy(bubbles = emptyList())
        announced = null
    }

    /** Ett tryck: alltid en ny bubbla med nästa text, och ett nytt varv bara om kärlet står still. */
    fun tap(time: Double, reduceMotion: Boolean) {
        now = time
        if (BinBubbleTimeline.startsRound(roundStart?.let { time - it }, reduceMotion)) {
            // Ett tryck före det första varvet ersätter det, så att inget varv spelas två gånger.
            if (playedFirst) round += 1
            roundStart = time
        }
        playedFirst = true
        val text = texts.next()
        bubbles = bubbles.add(text, time)
        announced = text
    }
}

private suspend fun frameSeconds(): Double = withFrameNanos { it } / 1e9

/**
 * Kärlet i hemskärmens tomma läge och bredvid rubriken, som BinRoundView.swift. Det spelar ett varv när det visas och står
 * sedan still med stängt lock. Ett tryck spelar ett nytt varv med nästa fraktion och en lätt vibration, och en av Sopors
 * roliga texter kommer fram i en pratbubbla som svävar och tonas bort efter cirka 2 sekunder. Varje tryck ger en ny
 * bubbla, och de som redan syns står kvar sin tid, högst tre åt gången. Ett tryck under ett varv låter varvet spela klart.
 * Det är dekoration: ingen slinga, så att slingan fortsatt betyder att något hämtas. Utan animationer står kärlet still, och
 * bubblan tonas bara in och ut på plats. Kärlet och bubblan är dolda för TalkBack, och texten tillkännages i stället med
 * låg prioritet.
 *
 * @param width kärlets bredd. Växer med textstorleken, högst till [maxWidth].
 * @param bubbleTip var bubblan står i förhållande till kärlet: mitt under, eller med vänsterkanten vid kärlet.
 * @param firstRound kärlets namn för det första varvet, som spelas en gång per process när kärlet visas, som på iOS där
 *   varvet inte spelas igen vid retur. `null` spelar inget första varv.
 * @param tapTrigger ökar när något annat än kärlet ska räknas som ett tryck på det, till exempel rubriken bredvid.
 * @param reduceMotion tvingar läget. Utan värde läses "Ta bort animationer".
 */
@Composable
fun BinRoundView(
    modifier: Modifier = Modifier,
    width: Dp = 135.dp,
    maxWidth: Dp = BinRound.MAX_WIDTH.dp,
    bubbleTip: BubbleTip = BubbleTip.Center,
    bubblePlacement: BinBubbleTimeline.Placement = BinBubbleTimeline.Placement.BelowBin,
    firstRound: String? = null,
    tapTrigger: Int = 0,
    reduceMotion: Boolean? = null,
) {
    val still = reduceMotion ?: animationsOff()
    val state = remember { BinRoundState() }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val drawn = scaledBinWidth(width, maxWidth)
    val currentStill by rememberUpdatedState(still)
    val firstRounds = LocalAppDependencies.current.binFirstRounds

    fun tapped() {
        // Ett tryck före det första varvet ersätter det.
        firstRound?.let(firstRounds::markShown)
        haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
        scope.launch { state.tap(frameSeconds(), currentStill) }
    }

    LaunchedEffect(firstRound) {
        if (firstRound == null || !firstRounds.shouldPlay(firstRound) || state.playedFirst) return@LaunchedEffect
        firstRounds.markShown(firstRound)
        state.playedFirst = true
        if (!currentStill) state.roundStart = frameSeconds()
    }
    LaunchedEffect(tapTrigger) { if (tapTrigger > 0) tapped() }
    // Bubblorna hör till skärmen som syns. Lämnas den, eller läggs appen i bakgrunden, tas de bort, så att de inte står
    // kvar ovanpå nästa skärm.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val resumed by lifecycle.currentStateAsState()
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { state.clearBubbles() }
    // Bubblorna står i ett eget fönster, så de visas bara medan kärlet syns helt, och inte när det har scrollats bort eller
    // när rubriken har krympt.
    var binShown by remember { mutableStateOf(true) }
    // Klockan går bara medan ett varv spelas eller en bubbla syns.
    LaunchedEffect(state.animating) {
        while (state.animating) withFrameNanos { state.frame(it / 1e9) }
    }

    Box(modifier) {
        BinFigure(
            pose = { state.pose(still) },
            modifier = Modifier
                .size(drawn, drawn * BIN_ASPECT)
                .onGloballyPositioned { coordinates ->
                    val visible = coordinates.boundsInWindow()
                    binShown = coordinates.isAttached && visible.height >= coordinates.size.height - 1 && visible.width >= coordinates.size.width - 1
                }
                .testTag(BinTags.BIN)
                .semantics {
                    hideFromAccessibility()
                    binRoundPlaying = state.roundStart != null
                }
                .pointerInput(Unit) {
                    // Trycket gäller bara själva kärlet, inte den tomma ytan ovanför där fraktionen faller.
                    detectTapGestures { offset ->
                        val scale = size.width / BinArtwork.viewBox.width
                        val area = BinArtwork.tapArea
                        val local = Rect(
                            (area.left - BinArtwork.viewBox.left) * scale,
                            (area.top - BinArtwork.viewBox.top) * scale,
                            (area.right - BinArtwork.viewBox.left) * scale,
                            (area.bottom - BinArtwork.viewBox.top) * scale,
                        )
                        if (local.contains(offset)) tapped()
                    }
                },
        )
        // Kärlet och bubblan är dolda för TalkBack, så texten tillkännages här, med låg prioritet.
        Box(
            Modifier.size(1.dp).semantics {
                liveRegion = LiveRegionMode.Polite
                state.announced?.let { contentDescription = it }
            },
        )
        if (state.bubbles.bubbles.isNotEmpty() && binShown && resumed.isAtLeast(Lifecycle.State.RESUMED)) {
            Bubbles(state, still, drawn, bubbleTip, bubblePlacement)
        }
    }
}

/**
 * Bubblorna i ett eget fönster, så att de står framför rubriken och innehållet och aldrig klipps. Fönstret tar inte emot
 * tryck. Flera bubblor staplas: den nyaste står närmast kärlet och skjuter de äldre utåt. Bara den nyaste har en spets.
 */
@Composable
private fun Bubbles(state: BinRoundState, still: Boolean, binWidth: Dp, tip: BubbleTip, placement: BinBubbleTimeline.Placement) {
    val density = LocalDensity.current
    val below = placement.isBelow
    val tipY = with(density) { BinBubbleTimeline.tipY(binWidth.value.toDouble(), placement).toFloat().dp.roundToPx() }
    val position = remember(tipY, tip, below) { BubblePosition(tipY, tip, below) }
    Popup(
        popupPositionProvider = position,
        properties = PopupProperties(
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        ),
    ) {
        val bubbles = state.bubbles.bubbles
        val newest = bubbles.lastOrNull()?.id
        // Den nyaste närmast kärlet: överst när bubblorna står under kärlet, annars nederst.
        val stack = if (below) bubbles.reversed() else bubbles
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (bubble in stack) {
                key(bubble.id) {
                    BinSpeechBubble(
                        text = bubble.text,
                        tip = tip,
                        pointsUp = below,
                        showsTip = bubble.id == newest,
                        modifier = Modifier
                            .testTag(BinTags.BUBBLE)
                            .clearAndSetSemantics { hideFromAccessibility() }
                            .graphicsLayer {
                                val elapsed = state.now - bubble.start
                                val scale = BinBubbleTimeline.scale(elapsed, still).toFloat()
                                scaleX = scale
                                scaleY = scale
                                transformOrigin = TransformOrigin(if (tip == BubbleTip.Start) 0f else 0.5f, if (below) 0f else 1f)
                                alpha = BinBubbleTimeline.opacity(elapsed).toFloat()
                                translationY = (if (below) 1 else -1) * BinBubbleTimeline.rise(elapsed, still).toFloat() * density.density
                            },
                    )
                }
            }
        }
    }
}

/**
 * Var bubblorna står: spetsen [tipY] px från kärlets överkant. Under kärlet växer de nedåt därifrån, annars uppåt, så att
 * de aldrig täcker kärlet. Mitt under kärlet, eller med vänsterkanten vid kärlet, och alltid inom fönstret.
 */
private class BubblePosition(private val tipY: Int, private val tip: BubbleTip, private val below: Boolean) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val x = if (tip == BubbleTip.Start) anchorBounds.left else anchorBounds.left + ((anchorBounds.width - popupContentSize.width) / 2f).roundToInt()
        val y = if (below) anchorBounds.top + tipY else anchorBounds.top + tipY - popupContentSize.height
        return IntOffset(x.coerceIn(0, maxOf(0, windowSize.width - popupContentSize.width)), y)
    }
}
