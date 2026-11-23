package se.hardyson.sophamtning.ui.home

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.ui.components.AddressPlaceLine
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.CalendarTile
import se.hardyson.sophamtning.ui.components.CapsTracking
import se.hardyson.sophamtning.ui.components.ChipRow
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Rubriken "Fler adresser". */
@Composable
fun OthersTitle() {
    Text(
        stringResource(R.string.home_others),
        style = uiText(20, Weight.BOLD),
        color = ThemeToken.Text2.color,
        modifier = Modifier.padding(top = 28.dp, bottom = 14.dp).semantics { heading() },
    )
}

/**
 * Huvudkortet, som PrimaryCard.swift: huvudadressens nästa tömning och det man behöver göra. Hela kortet öppnar adressvyn,
 * och TalkBack läser det som en knapp. [below] är det som står under kortets knapp, till exempel Ställ ut kärlen.
 */
@Composable
fun PrimaryCard(entry: HomeContent.Entry, onOpen: () -> Unit, modifier: Modifier = Modifier, below: @Composable () -> Unit = {}) {
    val foreground = ThemeToken.OnPrimary.color
    val reminder = entry.reminder.takeIf { entry.status is HomeContent.Status.Upcoming }
    val spoken = buildList {
        add(entry.accessibilityLabel)
        entry.dayNote?.let(::add)
        if (reminder != null) {
            if (reminder.showsDeniedNotice) add(HomeContent.RowReminder.Denied.text) else reminder.line?.let(::add)
        }
    }.joinToString(", ")
    Column(
        modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(ThemeToken.Primary.color, ThemeToken.BrandText.color)), RoundedCornerShape(28.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button, onClickLabel = stringResource(R.string.home_open_address), onClick = onOpen)
                .clearAndSetSemantics { contentDescription = spoken },
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CardHeader(entry, foreground)
            when (val status = entry.status) {
                is HomeContent.Status.Upcoming -> {
                    NextPickup(status.pickup, entry.dayNote, foreground)
                    ChipRow(status.pickup.fractions)
                    entry.scheduleEnding?.let { FooterLabel(it.shortText, AppSymbols.CalendarMonth, foreground) }
                    reminder?.line?.let { line ->
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            HorizontalDivider(color = foreground.copy(alpha = 0.25f))
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) { FooterLabel(line, Icons.Filled.Notifications, foreground) }
                        }
                    }
                }
                HomeContent.Status.Loading -> Text(stringResource(R.string.loading_schedule), style = uiText(15, Weight.BOLD), color = foreground)
                HomeContent.Status.NoUpcoming, is HomeContent.Status.Failed ->
                    Text(entry.summary, style = uiText(20, Weight.HEAVY), color = foreground)
            }
            if (entry.refreshFailed) {
                Text(stringResource(R.string.home_refresh_failed), style = uiText(13, Weight.SEMIBOLD), color = foreground.copy(alpha = 0.85f))
            }
        }
        below()
    }
}

/** Namnet och under det gatan och orten. Med största text står inget hus och ingen pil, så att texten får hela bredden. */
@Composable
private fun CardHeader(entry: HomeContent.Entry, foreground: Color) {
    val large = isLargeText()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        if (!large) Icon(Icons.Filled.Home, contentDescription = null, tint = foreground, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(entry.title, style = uiText(18, Weight.HEAVY), color = foreground)
            val address = entry.lines.singleLine
            if (address.isNotEmpty()) Text(address, style = uiText(15, Weight.SEMIBOLD), color = foreground.copy(alpha = 0.9f))
        }
        if (!large) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = foreground)
    }
}

/** Kalenderbrickan och raden om nästa tömning, under varandra med största text. */
@Composable
private fun NextPickup(pickup: HomeContent.Pickup, dayNote: String?, foreground: Color) {
    val text: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.next_pickup_caps), style = uiText(13, Weight.HEAVY).copy(letterSpacing = CapsTracking), color = foreground.copy(alpha = 0.9f))
            Text(pickup.headline, style = uiText(32, Weight.HEAVY), color = foreground)
            Text(pickup.longDate, style = uiText(17, Weight.BOLD), color = foreground)
            // På tömningsdagen säger kortet vad som gäller, i stället för bara "I dag".
            dayNote?.let { Text(it, style = uiText(15, Weight.SEMIBOLD), color = foreground.copy(alpha = 0.9f)) }
        }
    }
    if (isLargeText()) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            CalendarTile(pickup.date)
            text()
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
            CalendarTile(pickup.date)
            text()
        }
    }
}

@Composable
private fun FooterLabel(text: String, icon: ImageVector, foreground: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = foreground.copy(alpha = 0.9f), modifier = Modifier.size(16.dp))
        Text(text, style = uiText(15, Weight.BOLD), color = foreground.copy(alpha = 0.9f))
    }
}

/**
 * En adress under "Fler adresser", som AddressRow i HomeView.swift. Kärlen visas som chips, och raden läses med
 * fraktionernas hela namn.
 */
@Composable
fun AddressRow(entry: HomeContent.Entry, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(20.dp)
    val summaryColor = when (entry.summaryTone) {
        HomeContent.Entry.SummaryTone.Date -> ThemeToken.BrandText.color
        HomeContent.Entry.SummaryTone.Neutral -> ThemeToken.Text2.color
        HomeContent.Entry.SummaryTone.Warning -> ThemeToken.Warn.color
    }
    val spoken = listOfNotNull(entry.accessibilityLabel, entry.placedOut?.placedOutText, entry.rowReminder?.text).joinToString(", ")
    Column(
        modifier
            .fillMaxWidth()
            .background(ThemeToken.Surface.color, shape)
            .border(1.dp, ThemeToken.Border.color, shape)
            .clickable(role = Role.Button, onClick = onOpen)
            .clearAndSetSemantics { contentDescription = spoken }
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(entry.title, style = uiText(22, Weight.HEAVY), color = ThemeToken.Text.color)
            AddressPlaceLine(entry.lines, size = 17)
            Text(entry.summary, style = uiText(16, if (entry.summaryTone == HomeContent.Entry.SummaryTone.Neutral) Weight.BOLD else Weight.HEAVY), color = summaryColor)
            entry.placedOut?.placedOutText?.let { RowLabel(it, Icons.Filled.Notifications, ThemeToken.Text.color) }
            entry.rowReminder?.let { RowLabel(it.text, Icons.Filled.Notifications, ThemeToken.Text2.color) }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            val status = entry.status
            if (status is HomeContent.Status.Upcoming) ChipRow(status.pickup.fractions, Modifier.weight(1f), spacing = 6.dp) else Column(Modifier.weight(1f).height(0.dp)) {}
            Chevron()
        }
    }
}

@Composable
private fun RowLabel(text: String, icon: ImageVector, color: Color) {
    Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = ThemeToken.BrandText.color, modifier = Modifier.size(16.dp))
        Text(text, style = uiText(15, Weight.BOLD), color = color)
    }
}
