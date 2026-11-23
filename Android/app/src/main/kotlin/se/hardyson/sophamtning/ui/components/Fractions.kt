package se.hardyson.sophamtning.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Ikonen för varje ikonnamn från API:t. Namnen är Lucide-namnen som iOS-appen har med sig, och varje namn har en Material
 * Symbol som liknar den. Ett okänt namn ger återvinningssymbolen.
 */
object FractionIcons {
    val recycling: ImageVector get() = AppSymbols.Recycling

    private val byName: Map<String, () -> ImageVector> = mapOf(
        "trash-2" to { AppSymbols.Delete },
        "trash" to { AppSymbols.Delete },
        "apple" to { AppSymbols.Compost },
        "leaf" to { AppSymbols.Eco },
        "package" to { AppSymbols.Inventory2 },
        "cup-soda" to { AppSymbols.LocalDrink },
        "wine" to { AppSymbols.WineBar },
        "cylinder" to { AppSymbols.Hardware },
        "newspaper" to { AppSymbols.Newspaper },
        "container" to { AppSymbols.DeleteSweep },
        "recycle" to { AppSymbols.Recycling },
    )

    fun forName(name: String): ImageVector = byName[name]?.invoke() ?: recycling
}

/** Den enda platsen som väljer färg och ikon för en fraktion, som `FractionStyle` på iOS. */
class FractionStyle(val id: String, info: FractionInfo) {
    val name: String = info.name

    /** Källans korta namn, eller hela namnet när det korta saknas. */
    val shortName: String = info.short.trim().ifEmpty { info.name }
    val icon: ImageVector
    val foreground: ThemeToken
    val background: ThemeToken

    /** Fraktionen har färger och ikon i temat. */
    val isKnown: Boolean

    init {
        val themed = themes[id]
        if (themed != null) {
            foreground = themed.first
            background = themed.second
            icon = FractionIcons.forName(themed.third)
            isKnown = true
        } else {
            // API:ts färg används inte, eftersom den är en fast ljus färg som blir oläslig i mörkt läge.
            foreground = ThemeToken.Text2
            background = ThemeToken.Surface2
            icon = FractionIcons.forName(info.icon)
            isKnown = false
        }
    }

    private companion object {
        val themes = mapOf(
            "rest" to Triple(ThemeToken.FracRest, ThemeToken.FracRestBg, "trash-2"),
            "karl" to Triple(ThemeToken.FracRest, ThemeToken.FracRestBg, "container"),
            "mat" to Triple(ThemeToken.FracMat, ThemeToken.FracMatBg, "apple"),
            "papper" to Triple(ThemeToken.FracPapper, ThemeToken.FracPapperBg, "package"),
            "tidningar" to Triple(ThemeToken.FracTidningar, ThemeToken.FracTidningarBg, "newspaper"),
            "plast" to Triple(ThemeToken.FracPlast, ThemeToken.FracPlastBg, "cup-soda"),
            "glas" to Triple(ThemeToken.FracGlas, ThemeToken.FracGlasBg, "wine"),
            "metall" to Triple(ThemeToken.FracMetall, ThemeToken.FracMetallBg, "cylinder"),
        )
    }
}

/**
 * Pillerformad märkning med färg, ikon och hela namnet, som `FractionChip` på iOS. Ett långt namn bryts hellre än att
 * klippas. Med [short] står källans korta namn, men TalkBack läser alltid hela namnet.
 */
@Composable
fun FractionChip(id: String, info: FractionInfo, modifier: Modifier = Modifier, short: Boolean = false) {
    val style = FractionStyle(id, info)
    val foreground = style.foreground.color
    Row(
        modifier = modifier
            .background(style.background.color, CircleShape)
            .padding(start = 8.dp, end = 12.dp, top = 6.dp, bottom = 6.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(style.icon, contentDescription = style.name, tint = foreground, modifier = Modifier.size(16.dp))
        // Ikonen bär namnet för TalkBack, så att det läses en gång och aldrig som det korta namnet.
        Text(
            if (short) style.shortName else style.name,
            style = uiText(14, Weight.BOLD),
            color = foreground,
            overflow = TextOverflow.Clip,
            modifier = Modifier.semantics { hideFromAccessibility() },
        )
    }
}

/** Chipsen på rader, som bryts till nästa rad när de inte får plats (`FlowLayout` på iOS). */
@Composable
fun ChipRow(fractions: List<HomeContent.FractionItem>, modifier: Modifier = Modifier, spacing: Dp = 8.dp, short: Boolean = false) {
    FlowRow(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(spacing)) {
        for (fraction in fractions) FractionChip(fraction.id, fraction.info, short = short)
    }
}

/** Fraktionens ikon i en rundad ruta, 44 dp som standard. Ikonen har alltid fraktionens namn för TalkBack. */
@Composable
fun FractionIconBox(id: String, info: FractionInfo, size: Dp = 44.dp) {
    val style = FractionStyle(id, info)
    Box(
        Modifier.size(size).background(style.background.color, RoundedCornerShape(size * 14 / 44)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(style.icon, contentDescription = style.name, tint = style.foreground.color, modifier = Modifier.size(size / 2))
    }
}
