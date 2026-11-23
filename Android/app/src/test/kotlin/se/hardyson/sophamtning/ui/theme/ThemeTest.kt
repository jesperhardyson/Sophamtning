package se.hardyson.sophamtning.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeTest {
    /** Alla färgroller utom fel och scrim, som får behålla Materials värden. */
    private fun ColorScheme.roles(): Map<String, Color> = mapOf(
        "primary" to primary, "onPrimary" to onPrimary, "primaryContainer" to primaryContainer,
        "onPrimaryContainer" to onPrimaryContainer, "inversePrimary" to inversePrimary,
        "secondary" to secondary, "onSecondary" to onSecondary, "secondaryContainer" to secondaryContainer,
        "onSecondaryContainer" to onSecondaryContainer,
        "tertiary" to tertiary, "onTertiary" to onTertiary, "tertiaryContainer" to tertiaryContainer,
        "onTertiaryContainer" to onTertiaryContainer,
        "background" to background, "onBackground" to onBackground,
        "surface" to surface, "onSurface" to onSurface, "surfaceVariant" to surfaceVariant,
        "onSurfaceVariant" to onSurfaceVariant, "surfaceTint" to surfaceTint,
        "inverseSurface" to inverseSurface, "inverseOnSurface" to inverseOnSurface,
        "outline" to outline, "outlineVariant" to outlineVariant,
        "surfaceBright" to surfaceBright, "surfaceDim" to surfaceDim,
        "surfaceContainer" to surfaceContainer, "surfaceContainerHigh" to surfaceContainerHigh,
        "surfaceContainerHighest" to surfaceContainerHighest, "surfaceContainerLow" to surfaceContainerLow,
        "surfaceContainerLowest" to surfaceContainerLowest,
        "primaryFixed" to primaryFixed, "primaryFixedDim" to primaryFixedDim, "onPrimaryFixed" to onPrimaryFixed,
        "onPrimaryFixedVariant" to onPrimaryFixedVariant,
        "secondaryFixed" to secondaryFixed, "secondaryFixedDim" to secondaryFixedDim,
        "onSecondaryFixed" to onSecondaryFixed, "onSecondaryFixedVariant" to onSecondaryFixedVariant,
        "tertiaryFixed" to tertiaryFixed, "tertiaryFixedDim" to tertiaryFixedDim,
        "onTertiaryFixed" to onTertiaryFixed, "onTertiaryFixedVariant" to onTertiaryFixedVariant,
    )

    @Test
    fun allaRollerArDesignensFarger() {
        // Designens färger i båda lägena. Genomskinligt är tillåtet, så att ytor inte tonas med primärfärgen.
        val allowed = ThemeToken.entries.flatMap { listOf(it.light, it.dark) }.toSet() + Color.Transparent
        for (dark in listOf(false, true)) {
            val outside = sophamtningColors(dark).roles().filterValues { it !in allowed }
            assertTrue("Roller utanför designen (mörkt=$dark): ${outside.keys}", outside.isEmpty())
        }
    }
}
