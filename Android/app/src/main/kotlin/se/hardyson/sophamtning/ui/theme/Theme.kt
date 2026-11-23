package se.hardyson.sophamtning.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/** Material-schemat byggt av designens färger. Dynamiska färger från bakgrundsbilden används aldrig. */
fun sophamtningColors(dark: Boolean): ColorScheme {
    fun c(token: ThemeToken) = token.color(dark)
    val base = if (dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = c(ThemeToken.Primary),
        onPrimary = c(ThemeToken.OnPrimary),
        primaryContainer = c(ThemeToken.BrandSoft),
        onPrimaryContainer = c(ThemeToken.BrandText),
        secondary = c(ThemeToken.Brand),
        onSecondary = c(ThemeToken.OnPrimary),
        secondaryContainer = c(ThemeToken.BrandSoft),
        onSecondaryContainer = c(ThemeToken.BrandText),
        tertiary = c(ThemeToken.Earth),
        tertiaryContainer = c(ThemeToken.EarthSoft),
        background = c(ThemeToken.Bg),
        onBackground = c(ThemeToken.Text),
        surface = c(ThemeToken.Surface),
        onSurface = c(ThemeToken.Text),
        surfaceVariant = c(ThemeToken.Surface2),
        onSurfaceVariant = c(ThemeToken.Text2),
        surfaceContainer = c(ThemeToken.Surface),
        surfaceContainerHigh = c(ThemeToken.Surface2),
        outline = c(ThemeToken.Border),
        outlineVariant = c(ThemeToken.Border),
    )
}

@Composable
fun SophamtningTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = sophamtningColors(darkTheme), typography = SophamtningTypography, content = content)
}
