package se.hardyson.sophamtning.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import se.hardyson.sophamtning.core.bin.CalendarFlipTimeline
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.ui.bin.animationsOff
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.brandText
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Bladen som syns i brickan, det översta först. Bara för testerna: TalkBack läser aldrig de mellanliggande datumen. */
val CalendarSheets = SemanticsPropertyKey<List<DayDate>>("CalendarSheets")
private var SemanticsPropertyReceiver.calendarSheets by CalendarSheets

object CalendarTileTags {
    const val TILE = "kalenderbricka"
}

/** Vibrationerna under bläddringen: en lätt per blad och en tydligare när sista bladet landar. */
object FlipHaptics {
    val PAGE = HapticFeedbackType.SegmentFrequentTick
    val LANDING = HapticFeedbackType.SegmentTick
}

/** En pågående bläddring: datumet som visades när den började, och hur länge efter sin första bildruta den börjar. */
private data class Flip(val from: DayDate, val delay: Double)

/**
 * Kalenderbricka: månaden i versaler överst, dagens nummer och veckodagen, som `CalendarTile` på iOS. TalkBack läser bara
 * [day], också medan bladen bläddras.
 *
 * Byter [day] värde bläddras bladen fram till det nya datumet som i en blockkalender, ett per dag och högst 8
 * (`CalendarFlipTimeline`), men inte när brickan visas första gången. Nästa blad ligger alltid under det som viks upp, så
 * att inget blinkar. Ett datum bakåt ger ett blad. Med "Ta bort animationer" tonas brickan i stället, en gång, utan
 * vibration. Pågår redan en bläddring tas den över från bladet som ligger överst just nu.
 *
 * @param opening ett annat datum som brickan visar först och bläddrar från till [day] efter [openingDelay] sekunder, som
 *   huvudkortet vid start.
 * @param reduceMotion tvingar läget. Utan värde läses "Ta bort animationer".
 */
@Composable
fun CalendarTile(
    day: DayDate,
    modifier: Modifier = Modifier,
    opening: DayDate? = null,
    openingDelay: Double = 0.0,
    reduceMotion: Boolean? = null,
) {
    val still = reduceMotion ?: animationsOff()
    val haptics = LocalHapticFeedback.current
    val target by rememberUpdatedState(day)
    var flip by remember { mutableStateOf(opening?.takeIf { it != day }?.let { Flip(it, openingDelay) }) }
    // Sekunder sedan bläddringen började. Negativ medan den väntar.
    var elapsed by remember { mutableDoubleStateOf(-1.0) }
    // Datumet förra gången, för att se om det har bytts.
    val last = remember { arrayOf(day) }

    fun dates(from: DayDate) = CalendarFlipTimeline.dates(from, target, still)

    if (last[0] != day) {
        // Ett nytt datum: bläddra från bladet som ligger överst nu.
        val visible = flip?.let { current ->
            if (elapsed < 0) current.from else CalendarFlipTimeline.shownDate(elapsed, current.from, CalendarFlipTimeline.dates(current.from, last[0], still))
        } ?: last[0]
        last[0] = day
        flip = if (visible == day) null else Flip(visible, 0.0)
        elapsed = -1.0
    }

    LaunchedEffect(flip) {
        val current = flip ?: return@LaunchedEffect
        val pages = dates(current.from).size
        val pending = CalendarFlipTimeline.haptics(pages, still).toMutableList()
        val begin = withFrameNanos { it } / 1e9 + current.delay
        while (true) {
            val now = withFrameNanos { it } / 1e9 - begin
            elapsed = now
            // Vibrationerna följer bladen. Har en bildruta hoppat över flera, ges bara den senaste.
            val due = pending.filter { it.time <= now }
            if (due.isNotEmpty()) {
                pending.removeAll(due)
                haptics.performHapticFeedback(if (due.last().kind == CalendarFlipTimeline.Haptic.Kind.Landing) FlipHaptics.LANDING else FlipHaptics.PAGE)
            }
            if (CalendarFlipTimeline.isFinished(now, pages, still) && pending.isEmpty()) break
        }
        flip = null
        elapsed = -1.0
    }

    // Brickan växer med textstorleken, som `@ScaledMetric` på iOS, men högst till dubbla bredden.
    val width = 78.dp * LocalDensity.current.fontScale.coerceIn(1f, 2f)
    val current = flip
    val dates = current?.let { dates(it.from) }.orEmpty()
    val layers = current?.takeIf { !still }?.let { CalendarFlipTimeline.layers(elapsed, dates.size) }
    val faded = current?.takeIf { still }?.let { CalendarFlipTimeline.fadedDate(maxOf(elapsed, 0.0), it.from, day) }
    fun dateOf(sheet: Int) = CalendarFlipTimeline.dateOfSheet(sheet, current!!.from, dates)
    val shown = when {
        layers != null -> layers.folds.map { dateOf(it.sheet) } + dateOf(layers.under)
        faded != null -> listOf(faded)
        else -> listOf(day)
    }
    Box(
        modifier
            .width(width)
            .testTag(CalendarTileTags.TILE)
            .clearAndSetSemantics {
                contentDescription = SwedishFormat.longDate(day, capitalized = false)
                calendarSheets = shown
            },
    ) {
        when {
            layers != null -> {
                // Bladet under ligger stilla, och bladen som viks ligger ovanpå, det äldsta överst.
                Sheet(dateOf(layers.under), Modifier.zIndex(-layers.under.toFloat()))
                for (fold in layers.folds) {
                    val progress = fold.progress.toFloat()
                    Sheet(
                        dateOf(fold.sheet),
                        Modifier
                            .zIndex(-fold.sheet.toFloat())
                            .graphicsLayer {
                                // Bladet viks upp kring överkanten, med underkanten mot betraktaren.
                                transformOrigin = TransformOrigin(0.5f, 0f)
                                rotationX = CalendarFlipTimeline.angle(fold.progress).toFloat()
                                cameraDistance = 6 * density
                            }
                            .shadow(3.dp * (1 - progress), sheetShape, clip = false)
                            // Bladet mörknar när det viks upp och vänder bort från ljuset.
                            .drawWithContent {
                                drawContent()
                                drawOutline(sheetShape.createOutline(size, layoutDirection, this), Color.Black.copy(alpha = 0.25f * progress))
                            },
                    )
                }
            }
            faded != null -> Sheet(faded, Modifier.graphicsLayer { alpha = CalendarFlipTimeline.opacity(elapsed).toFloat() })
            else -> Sheet(day)
        }
    }
}

private val sheetShape = RoundedCornerShape(16.dp)

/** Ett blad med givet datum. Varje blad har egen form och kant, så att ett blad som viks kan gå utanför brickan. */
@Composable
private fun Sheet(day: DayDate, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(ThemeToken.Surface.color, sheetShape)
            .border(1.dp, ThemeToken.Border.color, sheetShape),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.fillMaxWidth().background(ThemeToken.Primary.color, RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)).heightIn(min = 26.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(SwedishFormat.monthUppercased(day), style = uiText(12, 900), color = ThemeToken.OnPrimary.color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(Modifier.padding(horizontal = 4.dp, vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(SwedishFormat.dayNumber(day), style = brandText(38), color = ThemeToken.Text.color, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(SwedishFormat.weekdayName(day), style = uiText(12, Weight.BOLD), color = ThemeToken.Text2.color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
