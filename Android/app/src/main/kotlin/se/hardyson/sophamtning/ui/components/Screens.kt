package se.hardyson.sophamtning.ui.components

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.DpSize
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * En skärm med appfält överst, kant till kant. [large] ger den stora rubriken som krymper när innehållet scrollar, som
 * adressvyn på iOS. Med [onBack] står en bakåtpil först. Systemets bakåtgest gör samma sak, via backstacken.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffold(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    large: Boolean = false,
    snackbarHostState: SnackbarHostState = remember { SnackbarHostState() },
    actions: @Composable RowScope.() -> Unit = {},
    largeTitleLeading: (@Composable () -> Unit)? = null,
    largeTitleLeadingSize: DpSize = DpSize.Zero,
    onLargeTitleTap: (() -> Unit)? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    val scrollBehavior = if (large) {
        TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    } else {
        TopAppBarDefaults.pinnedScrollBehavior()
    }
    val colors = TopAppBarDefaults.topAppBarColors(
        containerColor = ThemeToken.Bg.color,
        scrolledContainerColor = ThemeToken.Surface2.color,
        titleContentColor = ThemeToken.Text.color,
        navigationIconContentColor = ThemeToken.Text.color,
        actionIconContentColor = ThemeToken.Text.color,
    )
    val navigation: @Composable () -> Unit = {
        if (onBack != null) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.action_back)) }
        }
    }
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = ThemeToken.Bg.color,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        // Innehållet går kant till kant, med marginal mot statusfältet, gestfältet och tangentbordet.
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            if (large) {
                // Samma rubrik ritas två gånger: stor under raden med pilen, och liten bredvid pilen när fältet har krympt. Den
                // lilla är en rad, och den stora högst tre. Fältets utfällda höjd följer den stora rubrikens höjd, som på iOS:
                // ingen tom yta ovanför en rubrik på en rad, och plats för tre rader med största text.
                val largeStyle = MaterialTheme.typography.headlineMedium
                val measurer = rememberTextMeasurer()
                val windowWidth = LocalWindowInfo.current.containerSize.width
                val expandedHeight = with(LocalDensity.current) {
                    val leadingWidth = if (largeTitleLeading != null) (largeTitleLeadingSize.width + LEADING_SPACING).roundToPx() else 0
                    val width = (windowWidth - TITLE_HORIZONTAL_SPACE.roundToPx() - leadingWidth).coerceAtLeast(1)
                    val layout = measurer.measure(
                        title.ifEmpty { " " },
                        largeStyle,
                        overflow = TextOverflow.Ellipsis,
                        maxLines = LARGE_TITLE_LINES,
                        constraints = Constraints(maxWidth = width),
                    )
                    var height = layout.size.height.toFloat()
                    if (largeTitleLeading != null) {
                        // Det som står före rubriken står med botten på baslinjen och kan nå högre än texten.
                        height = maxOf(height, largeTitleLeadingSize.height.toPx() * LEADING_BASELINE + layout.size.height - layout.firstBaseline)
                    }
                    COLLAPSED_HEIGHT + height.toDp() + EXPANDED_TITLE_PADDING * 2
                }
                LargeTopAppBar(
                    title = {
                        val small = LocalTextStyle.current.fontSize != largeStyle.fontSize
                        val text: @Composable (Modifier) -> Unit = { textModifier ->
                            Text(
                                title,
                                maxLines = if (small) 1 else LARGE_TITLE_LINES,
                                overflow = TextOverflow.Ellipsis,
                                modifier = textModifier.semantics { heading() },
                            )
                        }
                        if (small || largeTitleLeading == null) {
                            text(Modifier)
                        } else {
                            // Det som står före den stora rubriken, som kärlet på hemskärmen, står med botten på textens
                            // baslinje. Ett tryck på rubriken förblir en rubrik för TalkBack.
                            Row(horizontalArrangement = Arrangement.spacedBy(LEADING_SPACING)) {
                                Box(Modifier.alignBy { (it.measuredHeight * LEADING_BASELINE).toInt() }) { largeTitleLeading() }
                                val tap = onLargeTitleTap?.let { onTap -> Modifier.pointerInput(onTap) { detectTapGestures { onTap() } } } ?: Modifier
                                text(Modifier.alignBy(LastBaseline).then(tap))
                            }
                        }
                    },
                    expandedHeight = expandedHeight,
                    navigationIcon = navigation,
                    actions = actions,
                    colors = colors,
                    scrollBehavior = scrollBehavior,
                )
            } else {
                TopAppBar(
                    title = { Text(title, style = uiText(18, Weight.HEAVY), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() }) },
                    navigationIcon = navigation,
                    actions = actions,
                    colors = colors,
                    scrollBehavior = scrollBehavior,
                )
            }
        },
        content = content,
    )
}

/** Kärlets kropp slutar vid y 441 i SVG:ns viewBox (360 × 560 från y -110), strax ovanför skuggan. */
private const val LEADING_BASELINE = (441f + 110f) / 560f

/** Den stora rubriken visar högst så många rader, och kortas sedan med en ellips. */
private const val LARGE_TITLE_LINES = 3

/** Luften mellan det som står före den stora rubriken och texten. */
private val LEADING_SPACING = 6.dp

/** Den stora rubrikens marginaler i fältet, 16 dp på var sida, och lite till så att höjden hellre räcker till en rad för mycket. */
private val TITLE_HORIZONTAL_SPACE = 40.dp
private val COLLAPSED_HEIGHT = 64.dp

/** Den stora rubriken står mitt i den utfällda delen av fältet, med så mycket luft ovanför och under, som på iOS. */
private val EXPANDED_TITLE_PADDING = 8.dp
