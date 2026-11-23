package se.hardyson.sophamtning.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import se.hardyson.sophamtning.R

// Fredoka för rubriker och Nunito för text, som på iOS. Båda är variabla typsnitt, så vikten sätts med en variation.
@OptIn(ExperimentalTextApi::class)
private fun variable(resource: Int, weights: IntRange) = FontFamily(
    listOf(300, 400, 500, 600, 700, 800, 900).filter { it in weights }.map { weight ->
        Font(resource, FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))
    },
)

val Fredoka = variable(R.font.fredoka, 300..700)
val Nunito = variable(R.font.nunito, 200..1000)

private val base = Typography()

/** Systemets textstilar med appens typsnitt. Storlekarna följer systemets textstorlek. */
val SophamtningTypography = Typography(
    displayLarge = base.displayLarge.brand(),
    displayMedium = base.displayMedium.brand(),
    displaySmall = base.displaySmall.brand(),
    headlineLarge = base.headlineLarge.brand(),
    headlineMedium = base.headlineMedium.brand(),
    headlineSmall = base.headlineSmall.brand(),
    titleLarge = base.titleLarge.brand(),
    titleMedium = base.titleMedium.ui(FontWeight.Bold),
    titleSmall = base.titleSmall.ui(FontWeight.Bold),
    bodyLarge = base.bodyLarge.ui(FontWeight.Medium),
    bodyMedium = base.bodyMedium.ui(FontWeight.Medium),
    bodySmall = base.bodySmall.ui(FontWeight.Medium),
    labelLarge = base.labelLarge.ui(FontWeight.Bold),
    labelMedium = base.labelMedium.ui(FontWeight.Bold),
    labelSmall = base.labelSmall.ui(FontWeight.Bold),
)

private fun TextStyle.brand() = copy(fontFamily = Fredoka, fontWeight = FontWeight.SemiBold)
private fun TextStyle.ui(weight: FontWeight) = copy(fontFamily = Nunito, fontWeight = weight, letterSpacing = 0.sp)

/**
 * Gränssnittstext i Nunito, som `Font.ui` på iOS. Storleken är i sp och följer systemets textstorlek. 600 är semibold, 700
 * bold, 800 heavy.
 */
fun uiText(size: Int, weight: Int = 700) = TextStyle(fontFamily = Nunito, fontWeight = FontWeight(weight), fontSize = size.sp, lineHeight = (size * 1.3).sp)

/** Varumärke och rubriker i Fredoka (600), som `Font.brand` på iOS. */
fun brandText(size: Int) = TextStyle(fontFamily = Fredoka, fontWeight = FontWeight.SemiBold, fontSize = size.sp, lineHeight = (size * 1.2).sp)

/** Vikterna med iOS-namnen. */
object Weight {
    const val SEMIBOLD = 600
    const val BOLD = 700
    const val HEAVY = 800
}
