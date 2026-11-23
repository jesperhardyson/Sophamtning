package se.hardyson.sophamtning.ui.components

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.layout.PaddingValues
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
                // lilla är en rad, och den stora högst tre. Fältets höjd växer med textstorleken, så att tre rader ryms.
                val largeStyle = MaterialTheme.typography.headlineMedium
                val expandedHeight = with(LocalDensity.current) {
                    maxOf(TopAppBarDefaults.LargeAppBarExpandedHeight, COLLAPSED_HEIGHT + (largeStyle.lineHeight * LARGE_TITLE_LINES).toDp() + EXPANDED_BOTTOM_PADDING)
                }
                LargeTopAppBar(
                    title = {
                        val small = LocalTextStyle.current.fontSize != largeStyle.fontSize
                        Text(
                            title,
                            maxLines = if (small) 1 else LARGE_TITLE_LINES,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.semantics { heading() },
                        )
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

/** Den stora rubriken visar högst så många rader, och kortas sedan med en ellips. */
private const val LARGE_TITLE_LINES = 3
private val COLLAPSED_HEIGHT = 64.dp
private val EXPANDED_BOTTOM_PADDING = 28.dp
