package se.hardyson.sophamtning.widget

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.Button
import androidx.glance.ButtonDefaults
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.schedule.FractionPickup
import se.hardyson.sophamtning.core.schedule.ScheduleEnding
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.widget.WidgetContent
import se.hardyson.sophamtning.core.widget.WidgetData
import se.hardyson.sophamtning.navigation.AppLink
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.FractionStyle
import se.hardyson.sophamtning.ui.theme.ThemeToken

/**
 * Widgeten Nästa tömning på hemskärmen, i storlekarna liten och mellan, som NextPickupWidget.swift. Den läser bara från
 * lagringen och gör inga nätanrop: appen och bakgrundshämtningen hämtar och sparar. Färgerna följer appens tema i ljust
 * och mörkt läge, inte bakgrundsbildens dynamiska färger. Ett tryck på widgeten öppnar huvudadressen i appen, och knappen
 * Ställ ut kärlen gör samma sak som Klart i Live Updaten.
 */
class NextPickupWidget : GlanceAppWidget() {
    // Glance ritar widgeten för varje storlek här och visar den största som ryms. Texterna och raderna räknas från
    // storleken, så en större widget får större text och fler rader.
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, SMALL_LARGE, MEDIUM, MEDIUM_TALL, MEDIUM_WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = LocalStore(SophamtningApplication.storeDirectory(context))
        val clock = clock(context)
        provideContent {
            // Läses om varje gång appen säger att något har ändrats, och vid midnatt.
            val version by WidgetUpdates.version.collectAsState()
            val data = remember(version) { WidgetData.read(store) }
            val now = remember(version) { clock() }
            NextPickupContent(data, now)
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        // Widgetgalleriet visar exempeldata, aldrig användarens adress, som på iOS.
        provideContent { PickupView(WidgetSample.view) }
    }

    private suspend fun clock(context: Context): () -> Instant = withContext(Dispatchers.Main) {
        (context.applicationContext as? SophamtningApplication)?.dependencies?.clock ?: { Instant.now() }
    }

    companion object {
        val SMALL = DpSize(100.dp, 100.dp)
        val SMALL_LARGE = DpSize(150.dp, 150.dp)
        val MEDIUM = DpSize(240.dp, 100.dp)
        val MEDIUM_TALL = DpSize(240.dp, 180.dp)
        val MEDIUM_WIDE = DpSize(320.dp, 180.dp)

        /** Utan så här mycket bredd ritas den lilla widgeten. */
        val mediumWidth: Dp = MEDIUM.width
    }
}

object WidgetTags {
    const val ROOT = "widget"
    const val PLACE_OUT = "ställUt"
}

/** Det widgeten visar vid en tidpunkt, räknat från lagringen. */
data class WidgetView(
    val content: WidgetContent,
    val info: (String) -> se.hardyson.sophamtning.core.api.FractionInfo,
    val ending: ScheduleEnding?,
    val placedOut: Boolean,
    val placeOut: PlacedOut?,
    /** Adressen som ett tryck på widgeten öppnar. */
    val primary: se.hardyson.sophamtning.core.storage.AddressKey?,
)

fun WidgetData.view(now: Instant): WidgetView = WidgetView(
    content = content(now),
    info = ::info,
    ending = scheduleEnding(now),
    placedOut = placedOut(now),
    placeOut = placeOutEntry(now),
    primary = primaryKey,
)

/** Widgeten för det som är sparat vid [now]. */
@Composable
fun NextPickupContent(data: WidgetData, now: Instant) {
    PickupView(data.view(now))
}

@Composable
fun PickupView(view: WidgetView) {
    val context = LocalContext.current
    val link = view.primary?.let { AppLink.OpenAddress(it) } ?: AppLink.Home
    GlanceTheme(colors = WidgetTheme.colors) {
        Box(
            GlanceModifier
                .fillMaxSize()
                .background(WidgetTheme.surface)
                .cornerRadius(20.dp)
                .padding(12.dp)
                .clickable(actionStartActivity(link.intent(context)))
                .semantics { testTag = WidgetTags.ROOT },
        ) {
            when (val content = view.content) {
                is WidgetContent.Pickup -> {
                    if (LocalSize.current.width >= NextPickupWidget.mediumWidth) MediumPickup(view, content) else SmallPickup(view, content)
                }
                WidgetContent.NoAddress -> Message(AppSymbols.Map, context.getString(R.string.widget_no_address), null, null)
                // Filerna går inte att läsa just nu. Adressen är inte borta.
                WidgetContent.Unavailable ->
                    Message(AppSymbols.ErrorOutline, context.getString(R.string.widget_unavailable), context.getString(R.string.widget_unavailable_detail), null)
                is WidgetContent.NoSchedule ->
                    Message(AppSymbols.Schedule, context.getString(R.string.widget_no_schedule), context.getString(R.string.widget_no_schedule_detail), content.name)
                is WidgetContent.Failed ->
                    Message(AppSymbols.ErrorOutline, context.getString(R.string.widget_failed), context.getString(R.string.widget_failed_detail), content.name)
                is WidgetContent.NotFound ->
                    Message(AppSymbols.LocationCity, context.getString(R.string.widget_not_found), context.getString(R.string.widget_not_found_detail), content.name)
                is WidgetContent.NoUpcoming -> Message(AppSymbols.CalendarMonth, context.getString(R.string.widget_no_upcoming), null, content.name)
            }
        }
    }
}

// MARK: Storlek

/**
 * Texterna krymper hellre än att klippas, som `minimumScaleFactor` på iOS: widgeten kan inte mäta texten, så storleken
 * räknas fram från platsen och systemets textstorlek. Högst ner till [MIN_SCALE].
 */
private const val MIN_SCALE = WidgetLayout.MIN_SCALE

/** Ungefärlig bredd per tecken i fet text, i förhållande till textstorleken. Hellre för bred än för smal. */
private const val CHAR_WIDTH = 0.62f

@Composable
private fun fontScale(): Float = LocalContext.current.resources.configuration.fontScale

/** En storlek för [text] på en rad som ryms i [width], med [scale] redan inräknad. */
private fun fitted(text: String, size: Float, width: Dp, fontScale: Float, scale: Float, min: Float = MIN_SCALE / 1.2f): TextUnit {
    val wanted = text.length * CHAR_WIDTH * size * scale * fontScale
    val factor = if (wanted <= width.value) 1f else (width.value / wanted).coerceAtLeast(min)
    return (size * scale * factor).sp
}


// MARK: Liten

/** Liten: dagen, datumet och kärlen som ikoner. En ensam fraktion visas också med sitt namn. */
@Composable
private fun SmallPickup(view: WidgetView, content: WidgetContent.Pickup) {
    val context = LocalContext.current
    val size = LocalSize.current
    val fontScale = fontScale()
    val width = size.width - 24.dp
    val inner = size.height.value - 24
    val shown = firstDay(content.fractions)
    // Kärlen syns alltid. Rubrikerna krymper, eller tas bort, så att inget klipps.
    val layout = WidgetLayout.small(size.height.value - 24, fontScale, view.placedOut, view.ending != null)
    val scale = layout.scale
    Column(
        GlanceModifier.fillMaxSize().semantics { contentDescription = spokenSummary(context, view, content, content.shortDate) },
    ) {
        if (layout.showsName) Text(content.name, maxLines = 1, style = TextStyle(WidgetTheme.text2, fitted(content.name, 14f, width, fontScale, scale), FontWeight.Bold))
        val relative = capitalized(content.relative)
        Text(relative, maxLines = 1, style = TextStyle(WidgetTheme.text, fitted(relative, 28f, width, fontScale, scale, min = 0.5f), FontWeight.Bold))
        if (layout.showsDate) {
            Text(content.shortDate, maxLines = 1, style = TextStyle(WidgetTheme.brandText, fitted(content.shortDate, 16f, width, fontScale, scale), FontWeight.Bold))
        }
        Spacer(GlanceModifier.defaultWeight())
        SmallIcons(view, shown, width, fontScale)
        if (layout.showsPlacedOut) PlacedOutLine(13f, fontScale, scale, GlanceModifier.padding(top = 6.dp))
        if (layout.showsEnding) view.ending?.let { EndingLine(it.shortText, 12f, width, fontScale, scale, GlanceModifier.padding(top = 6.dp)) }
    }
}

@Composable
private fun SmallIcons(view: WidgetView, shown: List<FractionPickup>, width: Dp, fontScale: Float) {
    val only = shown.singleOrNull()
    if (only != null) {
        val info = view.info(only.fraction)
        val style = FractionStyle(only.fraction, info)
        Row(verticalAlignment = Alignment.CenterVertically) {
            FractionIcon(style, 40.dp)
            // Det fulla namnet om det ryms på en rad, annars det korta. TalkBack läser alltid det fulla.
            val room = width - 48.dp
            val name = if (style.name.length * CHAR_WIDTH * 14 * fontScale <= room.value) style.name else style.shortName
            Text(
                name,
                maxLines = 1,
                modifier = GlanceModifier.padding(start = 8.dp),
                style = TextStyle(style.foreground.provider, fitted(name, 14f, room, fontScale, 1f), FontWeight.Bold),
            )
        }
    } else {
        // Får fler än tre inte plats visas två och "+N".
        val visible = if (shown.size > 3) shown.take(2) else shown
        Row(verticalAlignment = Alignment.CenterVertically) {
            for ((index, pickup) in visible.withIndex()) {
                FractionIcon(FractionStyle(pickup.fraction, view.info(pickup.fraction)), 38.dp, if (index > 0) GlanceModifier.padding(start = 6.dp) else GlanceModifier)
            }
            if (shown.size > visible.size) {
                Box(
                    GlanceModifier.padding(start = 6.dp).size(38.dp).background(WidgetTheme.surface2).cornerRadius(12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+${shown.size - visible.size}", maxLines = 1, style = TextStyle(WidgetTheme.text2, (14f / fontScale.coerceAtLeast(1f)).sp, FontWeight.Bold))
                }
            }
        }
    }
}

// MARK: Mellan

/** Mellan: kalenderbricka till vänster, och ett kärl per rad till höger, utan datum eftersom datumet står på bladet. */
@Composable
private fun MediumPickup(view: WidgetView, content: WidgetContent.Pickup) {
    val context = LocalContext.current
    val size = LocalSize.current
    val fontScale = fontScale()
    val first = content.fractions.firstOrNull()
    val sameDay = firstDay(content.fractions)
    // Brickan, raderna och knappen ryms på höjden. Det som inte ryms blir "+N till" eller tas bort, och klipps aldrig.
    val layout = WidgetLayout.medium(size.height.value - 24, fontScale, sameDay.size, view.placeOut != null, view.placedOut, view.ending != null)
    val scale = layout.scale
    val rightWidth = size.width - 24.dp - TILE_WIDTH - 16.dp
    val relative = capitalized(content.relative)
    val relativeSize = fitted(relative, 24f, rightWidth, fontScale, scale, min = 0.5f)
    val spokenDate = first?.let { SwedishFormat.shortDate(it.date) } ?: ""
    Row(
        GlanceModifier.fillMaxSize().semantics { contentDescription = spokenSummary(context, view, content, spokenDate) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (first != null) {
            Column(GlanceModifier.width(TILE_WIDTH), horizontalAlignment = Alignment.CenterHorizontally) {
                CalendarSheet(first.date, fontScale, scale)
                Text(
                    content.name,
                    maxLines = 1,
                    modifier = GlanceModifier.padding(top = 4.dp),
                    style = TextStyle(WidgetTheme.text2, fitted(content.name, 13f, TILE_WIDTH, fontScale, scale), FontWeight.Bold, textAlign = TextAlign.Center),
                )
            }
            Spacer(GlanceModifier.width(16.dp))
        }
        Column(GlanceModifier.defaultWeight()) {
            Text(relative, maxLines = 1, style = TextStyle(WidgetTheme.text, relativeSize, FontWeight.Bold))
            for (pickup in sameDay.take(layout.rows)) {
                val style = FractionStyle(pickup.fraction, view.info(pickup.fraction))
                Row(GlanceModifier.padding(top = WidgetLayout.ROW_SPACING.dp), verticalAlignment = Alignment.CenterVertically) {
                    FractionIcon(style, 28.dp)
                    Text(
                        style.name,
                        maxLines = 1,
                        modifier = GlanceModifier.padding(start = 8.dp),
                        style = TextStyle(WidgetTheme.text, fitted(style.name, 15f, rightWidth - 36.dp, fontScale, scale), FontWeight.Bold),
                    )
                }
            }
            val target = view.placeOut
            if (target != null) {
                // Ett tryck markerar tömningen utan att öppna appen, som Klart i Live Updaten.
                Button(
                    context.getString(R.string.widget_place_out),
                    onClick = actionRunCallback<PlaceOutAction>(PlaceOutAction.parameters(target)),
                    modifier = GlanceModifier.padding(top = WidgetLayout.BUTTON_SPACING.dp).height(WidgetLayout.BUTTON_HEIGHT.dp).semantics { testTag = WidgetTags.PLACE_OUT },
                    colors = ButtonDefaults.buttonColors(backgroundColor = WidgetTheme.primary, contentColor = WidgetTheme.onPrimary),
                    maxLines = 1,
                )
            }
            if (layout.hidden > 0) {
                Text(
                    context.getString(R.string.widget_more, layout.hidden),
                    maxLines = 1,
                    modifier = GlanceModifier.padding(top = 6.dp),
                    style = TextStyle(WidgetTheme.text2, (13f * scale).sp, FontWeight.Bold),
                )
            }
            if (layout.showsPlacedOut) PlacedOutLine(13f, fontScale, scale, GlanceModifier.padding(top = 6.dp))
            if (layout.showsEnding) view.ending?.let { EndingLine(it.shortText, 13f, rightWidth, fontScale, scale, GlanceModifier.padding(top = 6.dp)) }
        }
    }
}

private const val TILE_HEADER = WidgetLayout.TILE_HEADER
private val TILE_WIDTH = 78.dp

/** Kalenderbladet i den mellanstora widgeten, utan bläddring: widgeten byter blad vid midnatt. */
@Composable
private fun CalendarSheet(day: DayDate, fontScale: Float, scale: Float) {
    Column(
        GlanceModifier.width(TILE_WIDTH).background(WidgetTheme.border).cornerRadius(16.dp).padding(1.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(GlanceModifier.fillMaxWidth().background(WidgetTheme.sheet).cornerRadius(15.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(GlanceModifier.fillMaxWidth().height(TILE_HEADER.dp).background(WidgetTheme.primary), contentAlignment = Alignment.Center) {
                Text(SwedishFormat.monthUppercased(day), maxLines = 1, style = TextStyle(WidgetTheme.onPrimary, (12f * scale / fontScale.coerceAtLeast(1f)).sp, FontWeight.Bold))
            }
            Text(SwedishFormat.dayNumber(day), maxLines = 1, style = TextStyle(WidgetTheme.text, (32f * scale).sp, FontWeight.Bold))
            Text(
                SwedishFormat.weekdayName(day),
                maxLines = 1,
                modifier = GlanceModifier.padding(bottom = 6.dp),
                style = TextStyle(WidgetTheme.text2, fitted(SwedishFormat.weekdayName(day), 12f, TILE_WIDTH - 8.dp, fontScale, scale), FontWeight.Bold),
            )
        }
    }
}

// MARK: Delar

@Composable
private fun FractionIcon(style: FractionStyle, size: Dp, modifier: GlanceModifier = GlanceModifier) {
    Box(
        modifier.size(size).background(style.background.provider).cornerRadius(size * 12 / 40),
        contentAlignment = Alignment.Center,
    ) {
        // Namnet läses i widgetens sammanfattning, så ikonen är dold för TalkBack.
        Image(
            ImageProvider(WidgetIcons.bitmap(style.icon)),
            contentDescription = null,
            modifier = GlanceModifier.size(size * 0.55f),
            colorFilter = ColorFilter.tint(style.foreground.provider),
        )
    }
}

/** En fylld bock och "Utställda", när kärlen är utställda för nästa tömning. */
@Composable
private fun PlacedOutLine(size: Float, fontScale: Float, scale: Float, modifier: GlanceModifier) {
    val context = LocalContext.current
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Image(
            ImageProvider(WidgetIcons.bitmap(Checkmark)),
            contentDescription = null,
            modifier = GlanceModifier.size((size * fontScale * scale).dp),
            colorFilter = ColorFilter.tint(WidgetTheme.brandText),
        )
        Text(context.getString(R.string.widget_placed_out), maxLines = 1, modifier = GlanceModifier.padding(start = 4.dp), style = TextStyle(WidgetTheme.brandText, (size * scale).sp, FontWeight.Bold))
    }
}

/** "Schemat slutar 10 jan": en rad med liten ikon. Raden krymper hellre än att brytas. */
@Composable
private fun EndingLine(text: String, size: Float, width: Dp, fontScale: Float, scale: Float, modifier: GlanceModifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Image(
            ImageProvider(WidgetIcons.bitmap(AppSymbols.Schedule)),
            contentDescription = null,
            modifier = GlanceModifier.size((size * fontScale * scale).dp),
            colorFilter = ColorFilter.tint(WidgetTheme.text2),
        )
        Text(text, maxLines = 1, modifier = GlanceModifier.padding(start = 4.dp), style = TextStyle(WidgetTheme.text2, fitted(text, size, width - 20.dp, fontScale, scale), FontWeight.Bold))
    }
}

/** Lägena utan kommande hämtning: ingen adress, tekniskt fel och så vidare. Ett läge ser aldrig ut som ett annat. */
@Composable
private fun Message(icon: ImageVector, title: String, detail: String?, name: String?) {
    val fontScale = fontScale()
    val width = LocalSize.current.width - 24.dp
    val spoken = listOfNotNull(name, title, detail).joinToString(". ")
    Column(
        GlanceModifier.fillMaxSize().semantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            ImageProvider(WidgetIcons.bitmap(icon)),
            contentDescription = null,
            modifier = GlanceModifier.size(22.dp),
            colorFilter = ColorFilter.tint(WidgetTheme.primary),
        )
        if (name != null) {
            Text(name, maxLines = 1, modifier = GlanceModifier.padding(top = 6.dp), style = TextStyle(WidgetTheme.text2, fitted(name, 13f, width, fontScale, 1f), FontWeight.Bold))
        }
        Text(title, maxLines = 3, modifier = GlanceModifier.padding(top = 4.dp), style = TextStyle(WidgetTheme.text, (15f / fontScale.coerceAtLeast(1f).coerceAtMost(1.3f)).sp, FontWeight.Bold, textAlign = TextAlign.Center))
        if (detail != null) {
            Text(detail, maxLines = 3, modifier = GlanceModifier.padding(top = 4.dp), style = TextStyle(WidgetTheme.text2, (12f / fontScale.coerceAtLeast(1f).coerceAtMost(1.3f)).sp, FontWeight.Medium, textAlign = TextAlign.Center))
        }
    }
}

/** Versal först, som "Om 3 dagar" i designen. */
private fun capitalized(text: String) = text.replaceFirstChar { it.uppercase() }

/** Fraktionerna som hämtas första datumet. */
private fun firstDay(fractions: List<FractionPickup>): List<FractionPickup> {
    val first = fractions.firstOrNull() ?: return emptyList()
    return fractions.filter { it.date == first.date }
}

/**
 * Allt widgeten visar som en mening, för TalkBack. Alla fraktioner med namn, också de som bara syns som ikoner, de senare
 * med datum, och raden om att schemat slutar också när den inte rymdes.
 */
internal fun spokenSummary(context: Context, view: WidgetView, content: WidgetContent.Pickup, shortDate: String): String {
    val today = firstDay(content.fractions)
    val names = today.joinToString(", ") { view.info(it.fraction).name }
    val later = content.fractions.drop(today.size).map { "${view.info(it.fraction).name} ${WidgetContent.rowDate(it)}" }
    return (
        listOf(content.name, "${capitalized(content.relative)}, $shortDate", names) +
            listOfNotNull(
                context.getString(R.string.widget_placed_out).takeIf { view.placedOut },
                later.takeIf { it.isNotEmpty() }?.let { context.getString(R.string.widget_later, it.joinToString(", ")) },
                view.ending?.spokenText,
            )
        ).joinToString(". ")
}

/** Appens färger i ljust och mörkt läge. Widgeten följer systemets läge, och aldrig bakgrundsbildens färger. */
internal object WidgetTheme {
    val surface = ThemeToken.Surface.provider
    val surface2 = ThemeToken.Surface2.provider
    val sheet = ThemeToken.Surface.provider
    val border = ThemeToken.Border.provider
    val text = ThemeToken.Text.provider
    val text2 = ThemeToken.Text2.provider
    val brandText = ThemeToken.BrandText.provider
    val primary = ThemeToken.Primary.provider
    val onPrimary = ThemeToken.OnPrimary.provider

    /** Glance-komponenterna, som knappen, får appens gröna färger i stället för systemets dynamiska. */
    val colors = androidx.glance.material3.ColorProviders(
        light = androidx.compose.material3.lightColorScheme(
            primary = ThemeToken.Primary.light,
            onPrimary = ThemeToken.OnPrimary.light,
            surface = ThemeToken.Surface.light,
            onSurface = ThemeToken.Text.light,
            background = ThemeToken.Bg.light,
            onBackground = ThemeToken.Text.light,
        ),
        dark = androidx.compose.material3.darkColorScheme(
            primary = ThemeToken.Primary.dark,
            onPrimary = ThemeToken.OnPrimary.dark,
            surface = ThemeToken.Surface.dark,
            onSurface = ThemeToken.Text.dark,
            background = ThemeToken.Bg.dark,
            onBackground = ThemeToken.Text.dark,
        ),
    )
}

internal val ThemeToken.provider: ColorProvider get() = ColorProvider(day = light, night = dark)

/** Bocken i raden Utställda. Materials ikon i kärnbiblioteket, eftersom appen inte tar med hela ikonbiblioteket. */
private val Checkmark: ImageVector get() = Icons.Filled.Check

/** Exempeldata för widgetgalleriet: tre dagar kvar, två fraktioner på måndag och papper senare, som `.sample` på iOS. */
internal object WidgetSample {
    private val infos = mapOf(
        "rest" to se.hardyson.sophamtning.core.api.FractionInfo(name = "Restavfall", short = "Rest", color = "#474C48", icon = "trash-2"),
        "mat" to se.hardyson.sophamtning.core.api.FractionInfo(name = "Matavfall", short = "Mat", color = "#7A4A1E", icon = "apple"),
        "papper" to se.hardyson.sophamtning.core.api.FractionInfo(name = "Papper", short = "Papper", color = "#2E5E86", icon = "package"),
    )
    private val monday = DayDate(2026, 11, 9)

    val view = WidgetView(
        content = WidgetContent.Pickup(
            name = "Hemma",
            relative = "om 3 dagar",
            shortDate = "Mån 9 nov",
            fractions = listOf(
                FractionPickup("rest", monday, false, null, 3),
                FractionPickup("mat", monday, false, null, 3),
                FractionPickup("papper", DayDate(2026, 11, 12), true, null, 6),
            ),
        ),
        info = { id -> se.hardyson.sophamtning.core.schedule.ScheduleLogic.displayInfo(id, infos) },
        ending = null,
        placedOut = false,
        placeOut = null,
        primary = null,
    )
}

