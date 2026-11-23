package se.hardyson.sophamtning.ui.area

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.core.search.AreaRowContent
import se.hardyson.sophamtning.core.search.AreaWarning
import se.hardyson.sophamtning.core.search.LinkedText
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Ett kort i varningsstilen överst i områdesvalet, som `AreaWarningCard` på iOS: källans förklaring, att fel område kan ge
 * en missad tömning och källans hjälprad, där telefonnumret går att trycka på.
 */
@Composable
fun AreaWarningCard(warning: AreaWarning, modifier: Modifier = Modifier) {
    val text = uiText(14, Weight.SEMIBOLD)
    Column(
        modifier.fillMaxWidth().background(ThemeToken.WarnBg.color, RoundedCornerShape(16.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, contentDescription = null, tint = ThemeToken.Warn.color, modifier = Modifier.size(20.dp))
            Text(AreaWarning.title, style = uiText(15, Weight.HEAVY), color = ThemeToken.Warn.color, modifier = Modifier.semantics { heading() })
        }
        for (entry in warning.explanations) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // Källans namn behövs bara när flera källor svarade.
                entry.name?.let { Text(it, style = uiText(14, Weight.HEAVY), color = ThemeToken.Text.color) }
                Text(entry.text, style = text, color = ThemeToken.Text.color)
            }
        }
        if (warning.showsConsequence) Text(AreaWarning.consequence, style = uiText(14, Weight.HEAVY), color = ThemeToken.Text.color)
        for (help in warning.helps) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                help.name?.let { Text(it, style = uiText(14, Weight.HEAVY), color = ThemeToken.Text.color) }
                LinkedTextView(help.text, ThemeToken.Primary.color)
            }
        }
    }
}

/** Text där telefonnumren går att trycka på. */
@Composable
private fun LinkedTextView(linked: LinkedText, linkColor: Color) {
    val styles = TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline))
    val annotated = buildAnnotatedString {
        append(linked.text)
        for (link in linked.links) addLink(LinkAnnotation.Url(link.url, styles), link.range.first, link.range.last + 1)
    }
    Text(annotated, style = uiText(14, Weight.SEMIBOLD), color = ThemeToken.Text.color)
}

/**
 * Ett område som på webbens områdessida, som `AreaDetailsView` på iOS: namnet med en liten etikett, dagen, platserna på en
 * kort rad och platser med andra dagar. TalkBack läser alla platser.
 */
@Composable
fun AreaDetails(
    content: AreaRowContent,
    modifier: Modifier = Modifier,
    titleSize: Int = 20,
    showsAllPlaces: Boolean = false,
    labelBackground: Color = ThemeToken.BrandSoft.color,
) {
    Column(modifier.clearAndSetSemantics { contentDescription = content.accessibilityLabel }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val title: @Composable (Modifier) -> Unit = { m -> Text(content.title, style = uiText(titleSize, Weight.HEAVY), color = ThemeToken.Text.color, modifier = m) }
        val label = content.label
        when {
            label == null -> title(Modifier)
            isLargeText() -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                title(Modifier)
                LabelBadge(label, labelBackground)
            }
            else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                title(Modifier.weight(1f))
                LabelBadge(label, labelBackground)
            }
        }
        content.day?.let {
            Text(
                it,
                style = uiText(16, if (content.detailed) Weight.HEAVY else Weight.SEMIBOLD),
                color = if (content.detailed) ThemeToken.BrandText.color else ThemeToken.Text2.color,
            )
        }
        (if (showsAllPlaces) content.allPlaces else content.places)?.let {
            Text(it, style = uiText(15, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        if (content.otherDays.isNotEmpty()) {
            Text(AreaRowContent.otherDaysHeading, style = uiText(15, Weight.HEAVY), color = ThemeToken.Text2.color, modifier = Modifier.padding(top = 6.dp))
        }
        for (line in content.otherDays) Text(line, style = uiText(15, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
    }
}

@Composable
private fun LabelBadge(label: String, background: Color) {
    Text(
        label,
        style = uiText(13, Weight.HEAVY),
        color = ThemeToken.BrandText.color,
        modifier = Modifier.background(background, CircleShape).padding(horizontal = 10.dp, vertical = 2.dp),
    )
}
