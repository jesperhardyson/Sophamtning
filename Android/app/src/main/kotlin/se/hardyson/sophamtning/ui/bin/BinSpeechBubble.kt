package se.hardyson.sophamtning.ui.bin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Var spetsen står i bubblans bredd, så att den pekar på kärlet. */
enum class BubbleTip { Center, Start }

/**
 * Textens största skala i bubblan, ungefär den största vanliga textstorleken på iOS (xxxLarge). Bubblan är kort och
 * tillfällig, så den täcker inte rubriken eller skärmen med de största textstorlekarna.
 */
private const val MAX_FONT_SCALE = 1.35f

/**
 * Pratbubblan med en av Sopors roliga texter, som BinSpeechBubble.swift. Spetsen pekar mot kärlet: uppåt när bubblan står
 * under kärlet ([pointsUp]). [showsTip] är falskt för de äldre bubblorna i en stapel, men spetsen tar ändå sin plats, så
 * att bubblan inte hoppar. Bubblan är dold för TalkBack. Texten tillkännages i stället av kärlet.
 */
@Composable
internal fun BinSpeechBubble(text: String, tip: BubbleTip, pointsUp: Boolean, showsTip: Boolean, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val surface = ThemeToken.Surface.color
    val border = ThemeToken.Border.color
    val shape = RoundedCornerShape(14.dp)
    val align = if (tip == BubbleTip.Start) Alignment.Start else Alignment.CenterHorizontally
    CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale.coerceAtMost(MAX_FONT_SCALE))) {
        Column(modifier, horizontalAlignment = align) {
            if (pointsUp) TipShape(surface, border, pointsUp = true, Modifier.alpha(if (showsTip) 1f else 0f).zIndex(1f))
            Text(
                text,
                style = uiText(15, Weight.BOLD),
                color = ThemeToken.Text.color,
                modifier = Modifier
                    .widthIn(max = 220.dp)
                    .shadow(4.dp, shape, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
                    .background(surface, shape)
                    .border(1.dp, border, shape)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
            if (!pointsUp) TipShape(surface, border, pointsUp = false, Modifier.alpha(if (showsTip) 1f else 0f).zIndex(1f))
        }
    }
}

/**
 * Spetsen: en triangel mot kärlet. Kanten mot bubblan ritas inte, och spetsen går en punkt in över bubblans kant, så att
 * kanten inte syns där de möts.
 */
@Composable
private fun TipShape(fill: Color, stroke: Color, pointsUp: Boolean, modifier: Modifier) {
    Canvas(modifier.padding(horizontal = 12.dp).size(14.dp, 8.dp)) {
        val overlap = 1.dp.toPx()
        rotate(if (pointsUp) 180f else 0f) {
            val path = Path().apply {
                moveTo(0f, -overlap)
                lineTo(size.width / 2, size.height)
                lineTo(size.width, -overlap)
                close()
            }
            drawPath(path, fill)
            val edge = Path().apply {
                moveTo(0f, -overlap)
                lineTo(size.width / 2, size.height)
                lineTo(size.width, -overlap)
            }
            drawPath(edge, stroke, style = Stroke(width = 1.dp.toPx()))
        }
    }
}
