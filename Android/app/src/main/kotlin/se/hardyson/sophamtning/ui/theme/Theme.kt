package se.hardyson.sophamtning.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Material-schemat byggt av designens färger. Varje roll har en färg ur designen, så att inga av Materials lila
 * grundfärger syns i kort, fält eller ark. Dynamiska färger från bakgrundsbilden används aldrig.
 */
fun sophamtningColors(dark: Boolean): ColorScheme {
    fun c(token: ThemeToken) = token.color(dark)
    // De fasta rollerna är desamma i ljust och mörkt läge.
    fun fixed(token: ThemeToken) = token.light
    val base = if (dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = c(ThemeToken.Primary),
        onPrimary = c(ThemeToken.OnPrimary),
        primaryContainer = c(ThemeToken.BrandSoft),
        onPrimaryContainer = c(ThemeToken.BrandText),
        inversePrimary = ThemeToken.Primary.color(!dark),
        secondary = c(ThemeToken.Brand),
        onSecondary = c(ThemeToken.OnPrimary),
        secondaryContainer = c(ThemeToken.BrandSoft),
        onSecondaryContainer = c(ThemeToken.BrandText),
        tertiary = c(ThemeToken.Earth),
        onTertiary = c(ThemeToken.OnPrimary),
        tertiaryContainer = c(ThemeToken.EarthSoft),
        onTertiaryContainer = c(ThemeToken.Earth),
        background = c(ThemeToken.Bg),
        onBackground = c(ThemeToken.Text),
        surface = c(ThemeToken.Surface),
        onSurface = c(ThemeToken.Text),
        surfaceVariant = c(ThemeToken.Surface2),
        onSurfaceVariant = c(ThemeToken.Text2),
        // Ingen toning av upphöjda ytor med primärfärgen.
        surfaceTint = Color.Transparent,
        inverseSurface = c(ThemeToken.Text),
        inverseOnSurface = c(ThemeToken.Bg),
        outline = c(ThemeToken.Border),
        outlineVariant = c(ThemeToken.Border),
        surfaceBright = c(ThemeToken.Surface),
        surfaceDim = c(ThemeToken.Surface2),
        surfaceContainerLowest = c(ThemeToken.Surface),
        surfaceContainerLow = c(ThemeToken.Surface),
        surfaceContainer = c(ThemeToken.Surface),
        surfaceContainerHigh = c(ThemeToken.Surface2),
        surfaceContainerHighest = c(ThemeToken.Surface2),
        primaryFixed = fixed(ThemeToken.BrandSoft),
        primaryFixedDim = fixed(ThemeToken.Brand),
        onPrimaryFixed = fixed(ThemeToken.BrandText),
        onPrimaryFixedVariant = fixed(ThemeToken.Primary),
        secondaryFixed = fixed(ThemeToken.BrandSoft),
        secondaryFixedDim = fixed(ThemeToken.Brand),
        onSecondaryFixed = fixed(ThemeToken.BrandText),
        onSecondaryFixedVariant = fixed(ThemeToken.Primary),
        tertiaryFixed = fixed(ThemeToken.EarthSoft),
        tertiaryFixedDim = ThemeToken.Earth.dark,
        onTertiaryFixed = fixed(ThemeToken.Earth),
        onTertiaryFixedVariant = fixed(ThemeToken.Earth),
    )
}

/** Om temat är mörkt, så att designens färger kan väljas direkt med [color]. */
val LocalDarkTheme = staticCompositionLocalOf { false }

/** Designens färg för det aktuella läget, som `Color.Theme.x` på iOS. */
val ThemeToken.color: Color
    @Composable @ReadOnlyComposable get() = color(LocalDarkTheme.current)

@Composable
fun SophamtningTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalDarkTheme provides darkTheme) {
        MaterialTheme(colorScheme = sophamtningColors(darkTheme), typography = SophamtningTypography, content = content)
    }
}
