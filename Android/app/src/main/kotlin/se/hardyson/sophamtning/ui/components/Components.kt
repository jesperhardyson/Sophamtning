package se.hardyson.sophamtning.ui.components

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.brandText
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Sidmarginalen, som på iOS. */
val PageMargin = 24.dp

/** Från den här textskalan räknas texten som stor, som `isAccessibilitySize` på iOS, och rader läggs under varandra. */
@Composable
fun isLargeText(): Boolean = LocalDensity.current.fontScale >= 1.6f

/** Den lilla datumbrickan i schemaraderna: "11" och "NOV". */
@Composable
fun DayBadge(dayNumber: String, month: String) {
    Column(
        Modifier.widthIn(min = 52.dp).background(ThemeToken.Surface2.color, RoundedCornerShape(12.dp)).padding(vertical = 6.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(dayNumber, style = brandText(22), color = ThemeToken.Text.color, maxLines = 1)
        Text(month, style = uiText(11, Weight.HEAVY), color = ThemeToken.Text2.color, maxLines = 1)
    }
}

// MARK: Meddelanden

enum class MessageStyle { Neutral, Warning }

/** En länk under texten i ett [MessageCard], till exempel "Läs mer hos Avesta Vatten och Avfall". */
data class MessageLink(val title: String, val open: () -> Unit)

/**
 * Meddelanderuta med ikon, rubrik och förklaring, som `MessageCard` på iOS. Valfritt en länk under texten och ett kryss
 * som stänger rutan. Krysset står i rutan, så att texten aldrig hamnar under det.
 */
@Composable
fun MessageCard(
    title: String,
    text: String,
    style: MessageStyle,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    link: MessageLink? = null,
    closeLabel: String = stringResource(R.string.action_close),
    onClose: (() -> Unit)? = null,
) {
    val warning = style == MessageStyle.Warning
    val tint = if (warning) ThemeToken.Warn.color else ThemeToken.Text.color
    Row(
        modifier.fillMaxWidth().background(if (warning) ThemeToken.WarnBg.color else ThemeToken.Surface2.color, RoundedCornerShape(16.dp)),
    ) {
        Row(Modifier.weight(1f).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, style = uiText(15, Weight.HEAVY), color = tint)
                    Text(text, style = uiText(14, Weight.SEMIBOLD), color = if (warning) ThemeToken.Text.color else ThemeToken.Text2.color)
                }
                if (link != null) {
                    Text(
                        link.title,
                        style = uiText(14, Weight.HEAVY).copy(textDecoration = TextDecoration.Underline),
                        color = ThemeToken.Primary.color,
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .heightIn(min = 48.dp)
                            .clickable(role = Role.Button, onClick = link.open)
                            .padding(vertical = 12.dp),
                    )
                }
            }
        }
        if (onClose != null) {
            IconButton(onClick = onClose) {
                Icon(Icons.Filled.Close, contentDescription = closeLabel, tint = ThemeToken.Text2.color, modifier = Modifier.size(18.dp))
            }
        }
    }
}

// MARK: Kort och listor

/** Vit ruta med kant, som träffarna, områdena och schemat (`ResultList` på iOS). */
@Composable
fun SectionCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.fillMaxWidth().background(ThemeToken.Surface.color, shape).border(BorderStroke(1.dp, ThemeToken.Border.color), shape),
        content = content,
    )
}

@Composable
fun SectionDivider() = HorizontalDivider(thickness = 1.dp, color = ThemeToken.Border.color)

/** Rubriken över ett avsnitt, "Kommande" och "Per kärl". Markerad som rubrik för TalkBack. */
@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        style = uiText(20, Weight.BOLD),
        color = ThemeToken.Text2.color,
        modifier = modifier.padding(top = 28.dp, bottom = 12.dp).semantics { heading() },
    )
}

/**
 * Adressen och platsen på en rad, med komma emellan, som `AddressLinesView` på iOS. Har raderna ett namn står det först,
 * något större. TalkBack läser allt som en text, utan mittpunkt.
 */
@Composable
fun AddressPlaceLine(
    lines: HomeContent.AddressLines,
    modifier: Modifier = Modifier,
    size: Int = 18,
    color: Color = ThemeToken.Text2.color,
    weight: Int = Weight.SEMIBOLD,
) {
    Column(modifier.clearAndSetSemantics { contentDescription = lines.accessibilityLabel }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (lines.name.isNotEmpty()) Text(lines.name, style = uiText(size + 2, Weight.HEAVY), color = ThemeToken.Text.color)
        if (lines.singleLine.isNotEmpty()) Text(lines.singleLine, style = uiText(size, weight), color = color)
    }
}

// MARK: Knappar och fält

/** Primärknapp, minst 52 hög och helt rund, som `PrimaryButtonLabel` på iOS. */
@Composable
fun PrimaryButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = 52.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = ThemeToken.Primary.color, contentColor = ThemeToken.OnPrimary.color),
    ) {
        Text(title, style = uiText(17, Weight.HEAVY), textAlign = TextAlign.Center)
    }
}

/** En knapp som bara är text i accentfärg, till exempel "Inte nu" och "Börja om". */
@Composable
fun PlainButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TextButton(onClick = onClick, modifier = modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(title, style = uiText(17, Weight.HEAVY), color = ThemeToken.Primary.color, textAlign = TextAlign.Center)
    }
}

/** Sökfältet i flödet, runt och med förstoringsglas, som `FlowSearchField` på iOS. Får fokus när skärmen visas. */
@Composable
fun FlowSearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, focus: Boolean = true) {
    val requester = remember { FocusRequester() }
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).focusRequester(requester),
        placeholder = { Text(placeholder, style = uiText(18, Weight.SEMIBOLD), color = ThemeToken.Text2.color) },
        textStyle = uiText(18, Weight.SEMIBOLD).copy(color = ThemeToken.Text.color),
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = ThemeToken.Text.color) },
        trailingIcon = if (value.isEmpty()) null else {
            { IconButton(onClick = { onValueChange("") }) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.action_clear), tint = ThemeToken.Text2.color) } }
        },
        singleLine = true,
        shape = CircleShape,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = ThemeToken.Surface.color,
            unfocusedContainerColor = ThemeToken.Surface.color,
            focusedBorderColor = ThemeToken.Primary.color,
            unfocusedBorderColor = ThemeToken.Border.color,
            cursorColor = ThemeToken.Primary.color,
        ),
    )
    if (focus) LaunchedEffect(Unit) { runCatching { requester.requestFocus() } }
}

/**
 * En rad med en ikon i en rund platta, en rubrik, en förklarande rad och en pil, som `IconPlateRowLabel` på iOS. Används
 * för "Välj område i …" och "Vet du inte vilket område?". TalkBack läser rubriken och raden under.
 */
@Composable
fun IconPlateRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit, horizontalPadding: Int = 16, verticalPadding: Int = 14) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = horizontalPadding.dp, vertical = verticalPadding.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(40.dp).background(ThemeToken.BrandSoft.color, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = ThemeToken.BrandText.color, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
            Text(subtitle, style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        Chevron()
    }
}

@Composable
fun Chevron() = Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = ThemeToken.Text2.color)

/** "Söker …" med en snurra. */
@Composable
fun SearchingRow(text: String, modifier: Modifier = Modifier) {
    Row(modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        androidx.compose.material3.CircularProgressIndicator(Modifier.size(20.dp), color = ThemeToken.Primary.color, strokeWidth = 2.dp)
        Text(text, style = uiText(17, Weight.BOLD), color = ThemeToken.Text2.color)
    }
}

/** Ett tomt avstånd i dp, för läsbarhetens skull i långa kolumner. */
@Composable
fun Gap(height: Int) = Spacer(Modifier.height(height.dp))

/** Fet text med iOS-vikten, när en stil behöver justeras. */
val HeavyWeight = FontWeight(Weight.HEAVY)

/** Bokstavsavstånd för "NÄSTA TÖMNING". */
val CapsTracking = 1.2.sp
