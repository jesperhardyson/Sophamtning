package se.hardyson.sophamtning.ui.bin

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import se.hardyson.sophamtning.core.bin.BinLoaderTimeline
import se.hardyson.sophamtning.core.bin.BinRound
import se.hardyson.sophamtning.ui.components.FractionIcons
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.color

/** Kärlets höjd i förhållande till bredden, från SVG:ns viewBox (360 × 560). */
internal const val BIN_ASPECT = 560f / 360f

/**
 * Om "Ta bort animationer" är på i Android (`ANIMATOR_DURATION_SCALE` är 0). Kärlet gör då som med Reducera rörelse på
 * iOS: inget varv, och bubblan tonas bara in och ut. Läses igen när appen kommer tillbaka i förgrunden.
 */
@Composable
fun animationsOff(): Boolean {
    val resolver = LocalContext.current.contentResolver
    fun read() = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    var off by remember(resolver) { mutableStateOf(read()) }
    LifecycleResumeEffect(resolver) {
        off = read()
        onPauseOrDispose {}
    }
    return off
}

/** Kärlets bredd: [width] växer med textstorleken som logotypen, högst till [maxWidth]. */
@Composable
internal fun scaledBinWidth(width: Dp, maxWidth: Dp): Dp {
    val scale = LocalDensity.current.fontScale.coerceAtLeast(1f)
    return BinRound.drawnWidth(scaled = (width.value * scale).toDouble(), maxWidth = maxWidth.value.toDouble()).toFloat().dp
}

/** Fraktionerna i slingan, i webbens ordning: mat, papper, plast. Färgerna följer temat, som på webben. */
private val tileIcons = listOf("apple", "package", "cup-soda")
private val tileColors = listOf(
    ThemeToken.FracMat to ThemeToken.FracMatBg,
    ThemeToken.FracPapper to ThemeToken.FracPapperBg,
    ThemeToken.FracPlast to ThemeToken.FracPlastBg,
)

/**
 * Kärlet i ett givet läge, som BinFigure i BinLoaderView.swift. Ritas i SVG:ns eget mått (360 × 560) och skalas till
 * modifierns storlek. [pose] läses vid ritningen, så att en ny bild inte kräver en ny komposition.
 */
@Composable
internal fun BinFigure(pose: () -> BinLoaderTimeline.Pose, modifier: Modifier = Modifier) {
    val painters = tileIcons.map { rememberVectorPainter(FractionIcons.forName(it)) }
    val colors = tileColors.map { (fg, bg) -> fg.color to bg.color }
    val shadow = ThemeToken.Surface2.color
    Canvas(modifier) {
        val box = BinArtwork.viewBox
        val scale = size.width / box.width
        val current = pose()
        withTransform({
            scale(scale, scale, pivot = Offset.Zero)
            translate(-box.left, -box.top)
        }) {
            drawOval(shadow, topLeft = BinArtwork.shadow.topLeft, size = BinArtwork.shadow.size)
            rotate(current.bodySway.toFloat(), pivot = BinArtwork.bodyPivot) {
                if (current.lidIsBehindBody) drawLid(current.lidAngle)
                val fraction = current.fraction
                if (fraction.opacity > 0) drawFraction(fraction, painters[fraction.index], colors[fraction.index])
                drawParts(BinArtwork.bodyParts)
                if (!current.lidIsBehindBody) drawLid(current.lidAngle)
            }
        }
    }
}

private fun DrawScope.drawParts(parts: List<BinArtwork.Part>) {
    for (part in parts) {
        when (part) {
            is BinArtwork.PathPart -> drawPath(part.path, part.color)
            is BinArtwork.EllipsePart -> rotate(part.rotation, pivot = part.bounds.center) {
                drawOval(part.color, topLeft = part.bounds.topLeft, size = part.bounds.size)
            }
        }
    }
}

private fun DrawScope.drawLid(angle: Double) {
    rotate(angle.toFloat(), pivot = BinArtwork.hinge) { drawParts(BinArtwork.lidParts) }
}

/** Fraktionens platta (88 × 88, radie 28, halvgenomskinlig) med ikon. Vrids runt sitt hörn och flyttas sedan. */
private fun DrawScope.drawFraction(
    state: BinLoaderTimeline.FractionState,
    painter: VectorPainter,
    colors: Pair<androidx.compose.ui.graphics.Color, androidx.compose.ui.graphics.Color>,
) {
    val alpha = state.opacity.toFloat()
    translate(state.x.toFloat(), state.y.toFloat()) {
        rotate(state.rotation.toFloat(), pivot = Offset.Zero) {
            drawRoundRect(colors.second.copy(alpha = 0.5f), size = Size(88f, 88f), cornerRadius = CornerRadius(28f), alpha = alpha)
            translate(22f, 22f) {
                with(painter) { draw(Size(44f, 44f), alpha = alpha, colorFilter = ColorFilter.tint(colors.first)) }
            }
        }
    }
}
