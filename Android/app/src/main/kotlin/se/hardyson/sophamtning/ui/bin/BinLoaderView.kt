package se.hardyson.sophamtning.ui.bin

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.bin.BinLoaderTexts
import se.hardyson.sophamtning.core.bin.BinLoaderTimeline
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Sopors laddningsanimation, som BinLoaderView.swift: ett grönt kärl som öppnar locket, tar emot en fraktion, slår igen
 * locket och gungar. Allt räknas från klockan, så en omritning stör inte slingan. Utan animationer står kärlet still med
 * stängt lock och en fast text. TalkBack läser alltid "Hämtar schema", aldrig de roliga texterna.
 *
 * @param width kärlets bredd. Höjden följer SVG:ns proportioner. Hemkortet använder 150, som på webben.
 * @param showsText den roliga texten under kärlet. Av i små storlekar, där raden redan har egen text.
 */
@Composable
fun BinLoaderView(
    modifier: Modifier = Modifier,
    width: Dp = 150.dp,
    showsText: Boolean = true,
    textColor: Color = ThemeToken.Text2.color,
    reduceMotion: Boolean? = null,
) {
    val still = reduceMotion ?: animationsOff()
    val label = stringResource(R.string.loading_schedule)
    var elapsed by remember { mutableDoubleStateOf(0.0) }
    var settled by remember { mutableStateOf(false) }
    // Ingen text upprepas förrän alla visats, och samma text står kvar vid omritning.
    val texts = remember { TextSequence() }
    LaunchedEffect(still) {
        if (still) {
            // Bara den enkla toningen in finns kvar.
            delay((BinLoaderTimeline.APPEAR_DELAY * 1000).toLong())
            settled = true
        } else {
            // Slingan står still när appen inte syns, eftersom inga bilder ritas då.
            var start = -1L
            while (true) {
                withInfiniteAnimationFrameNanos { frame ->
                    if (start < 0) start = frame
                    elapsed = (frame - start) / 1e9
                }
            }
        }
    }
    val settledAlpha by animateFloatAsState(if (settled) 1f else 0f, tween((BinLoaderTimeline.APPEAR_DURATION * 1000).toInt()), label = "inToning")
    val cycle by remember { derivedStateOf { BinLoaderTimeline.textCycle(elapsed) } }
    Column(
        modifier
            .graphicsLayer { alpha = if (still) settledAlpha else BinLoaderTimeline.appearOpacity(elapsed).toFloat() }
            .clearAndSetSemantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        BinFigure(
            pose = { if (still) BinLoaderTimeline.Pose.RESTING else BinLoaderTimeline.loopPose(elapsed) },
            modifier = Modifier.size(width, width * BIN_ASPECT),
        )
        if (showsText) {
            Text(
                if (still) stringResource(R.string.loading_schedule_text) else texts.text(cycle),
                style = uiText(20, Weight.SEMIBOLD),
                color = textColor,
                textAlign = TextAlign.Center,
                minLines = 2,
                maxLines = 2,
                modifier = Modifier
                    .widthIn(max = 340.dp)
                    .graphicsLayer { alpha = if (still) 1f else BinLoaderTimeline.textOpacity(elapsed).toFloat() },
            )
        }
    }
}

/** En ny text slumpas först när cykeln byter, och ingen upprepas förrän alla visats. */
private class TextSequence {
    private val queue = BinLoaderTexts.Queue()
    private val drawn = mutableListOf<String>()

    fun text(cycle: Int): String {
        while (drawn.size <= cycle) drawn += queue.next()
        return drawn[cycle]
    }
}
