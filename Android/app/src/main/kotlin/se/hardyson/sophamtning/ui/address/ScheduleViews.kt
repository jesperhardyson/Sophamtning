package se.hardyson.sophamtning.ui.address

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.kommun.SourceLink
import se.hardyson.sophamtning.core.search.OtherDaysNote
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.ChipRow
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.components.DayBadge
import se.hardyson.sophamtning.ui.components.FractionChip
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.bin.BinLoaderView
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.components.openExternal
import se.hardyson.sophamtning.ui.components.openWebLink
import se.hardyson.sophamtning.ui.search.sourceName
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

// Delar som adressvyn och Hela schemat delar, som ScheduleViews.swift och SourceCard.swift.

/** En dag i schemat: liten datumbricka, kärlen som chips och dagar kvar till höger. Avvikelse och varning står under. */
@Composable
fun ScheduleRow(row: AddressDetail.Row) {
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = row.accessibilityLabel }.padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val days: @Composable (Modifier) -> Unit = { m ->
            Text(row.shortDaysText, style = uiText(15, Weight.HEAVY), color = ThemeToken.BrandText.color, textAlign = TextAlign.End, modifier = m)
        }
        if (isLargeText()) {
            // Under varandra, så att chipsen och dagarna får hela bredden.
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                DayBadge(row.dayNumber, row.month)
                days(Modifier)
            }
            ChipRow(row.fractions, spacing = 6.dp)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                DayBadge(row.dayNumber, row.month)
                ChipRow(row.fractions, Modifier.weight(1f), spacing = 6.dp)
                days(Modifier.padding(start = 4.dp))
            }
        }
        row.deviation?.let { Text(it, style = uiText(15, Weight.BOLD), color = ThemeToken.Warn.color) }
        row.warning?.let { warning ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, contentDescription = null, tint = ThemeToken.Warn.color, modifier = Modifier.size(16.dp))
                Text(warning, style = uiText(15, Weight.BOLD), color = ThemeToken.Warn.color)
            }
        }
    }
}

/** Raderna i en vit ruta. */
@Composable
fun ScheduleList(rows: List<AddressDetail.Row>) {
    SectionCard {
        rows.forEachIndexed { index, row ->
            if (index > 0) SectionDivider()
            ScheduleRow(row)
        }
    }
}

/** En rad per kärl under "Per kärl": chipset till vänster, och datum och dagar kvar till höger. */
@Composable
fun BinRow(bin: AddressDetail.Bin) {
    val dates: @Composable (Alignment.Horizontal) -> Unit = { alignment ->
        Column(horizontalAlignment = alignment, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(bin.dateText, style = uiText(15, Weight.BOLD), color = ThemeToken.Text.color)
            Text(bin.daysText, style = uiText(14, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
    }
    val modifier = Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = bin.accessibilityLabel }.padding(horizontal = 16.dp, vertical = 12.dp)
    if (isLargeText()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FractionChip(bin.id, bin.info)
            dates(Alignment.Start)
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.weight(1f)) { FractionChip(bin.id, bin.info) }
            dates(Alignment.End)
        }
    }
}

/** Rutan för ett område där vissa gator har en annan hämtdag. Står före datumen. */
@Composable
fun OtherDaysCard(note: OtherDaysNote, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().background(ThemeToken.Surface2.color, RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.Info, contentDescription = null, tint = ThemeToken.Text.color, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(note.heading, style = uiText(15, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.semantics { heading() })
            for (row in note.rows) Text(row, style = uiText(14, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
    }
}

/** Meddelandet högst upp i adressvyn och i Hela schemat när hämtningen eller sparandet har misslyckats. */
@Composable
fun AddressNotice(notice: AddressDetail.Notice?, onRetry: () -> Unit, onSearchAgain: () -> Unit) {
    val padded = Modifier.padding(bottom = 20.dp)
    when (notice) {
        null -> {}
        is AddressDetail.Notice.SavedShown -> MessageCard(
            title = stringResource(R.string.notice_saved_title),
            text = listOfNotNull(stringResource(R.string.notice_saved_text), notice.fetched).joinToString(" "),
            style = MessageStyle.Neutral,
            icon = AppSymbols.ErrorOutline,
            modifier = padded,
        )
        AddressDetail.Notice.SourceUnavailable -> Column(padded, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            MessageCard(stringResource(R.string.notice_unavailable_title), stringResource(R.string.notice_unavailable_text), MessageStyle.Warning, AppSymbols.ErrorOutline)
            PrimaryButton(stringResource(R.string.action_retry), onRetry)
        }
        AddressDetail.Notice.NotFound -> Column(padded, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            MessageCard(stringResource(R.string.notice_not_found_title), stringResource(R.string.notice_not_found_text), MessageStyle.Warning, Icons.Filled.Warning)
            PrimaryButton(stringResource(R.string.action_search_again), onSearchAgain)
        }
        // Samma anrop upprepas inte, så det finns ingen Försök igen.
        AddressDetail.Notice.BadRequest -> MessageCard(
            title = stringResource(R.string.notice_bad_request_title),
            text = stringResource(R.string.notice_bad_request_text),
            style = MessageStyle.Warning,
            icon = Icons.Filled.Warning,
            modifier = padded,
        )
        AddressDetail.Notice.StorageFailed -> Column(padded, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            MessageCard(
                stringResource(R.string.notice_storage_title),
                stringResource(R.string.notice_storage_text),
                MessageStyle.Warning,
                Icons.Filled.Warning,
            )
            PrimaryButton(stringResource(R.string.action_retry), onRetry)
        }
    }
}

/** Schemat hämtas för första gången. */
@Composable
fun ScheduleLoadingCard(modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth().background(ThemeToken.Surface.color, RoundedCornerShape(20.dp)).padding(vertical = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        BinLoaderView(textColor = ThemeToken.Text.color)
    }
}

@Composable
fun NoUpcomingCard(message: AddressDetail.NoUpcomingMessage) {
    MessageCard(message.title, message.message, MessageStyle.Neutral, AppSymbols.CalendarMonth)
}

/** "Schemat gäller till 10 januari 2027." och källans orsak i mindre text under. */
@Composable
fun SchedulePeriodView(line: AddressDetail.SchedulePeriodLine, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.DateRange, contentDescription = null, tint = ThemeToken.Text2.color, modifier = Modifier.size(18.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(line.text, style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text.color)
            line.reason?.let { Text(it, style = uiText(14, Weight.SEMIBOLD), color = ThemeToken.Text2.color) }
        }
    }
}

/**
 * "Ansvarar för hämtningen": källans namn, länkarna och när schemat hämtades, som SourceCard.swift. Webbsidor öppnas i
 * Custom Tabs, telefon och e-post av systemet.
 */
@Composable
fun SourceCard(source: String, sources: List<Source>?, detail: AddressDetail, modifier: Modifier = Modifier) {
    val links = SourceLink.links(sources?.firstOrNull { it.id == source }, detail.webLink)
    val fetched = if (detail.mode == AddressDetail.Mode.Loading) null else detail.fetchedText
    SectionCard(modifier) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.source_card_title), style = uiText(15, Weight.HEAVY), color = ThemeToken.Text2.color, modifier = Modifier.semantics { heading() })
            Text(sourceName(source, sources), style = uiText(20, Weight.HEAVY), color = ThemeToken.Text.color)
        }
        for (link in links) {
            SectionDivider()
            SourceLinkRow(link)
        }
        fetched?.let {
            SectionDivider()
            Text(it, style = uiText(13, Weight.SEMIBOLD), color = ThemeToken.Text2.color, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp))
        }
    }
}

/** En länk till källan, med ikon, som en rad i en lista. Telefonnumret står i accentfärg. */
@Composable
fun SourceLinkRow(link: SourceLink, source: String? = null) {
    val context = LocalContext.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button) {
                val web = link.webLink
                if (web != null) context.openWebLink(web) else context.openExternal(link.url)
            }
            // Källans namn i beskrivningen där flera källor står i samma lista, så att TalkBack säger vilken länken hör till.
            .clearAndSetSemantics { contentDescription = source?.let { "${link.accessibilityLabel}, $it" } ?: link.accessibilityLabel }
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(link.icon, contentDescription = null, tint = ThemeToken.Primary.color, modifier = Modifier.size(22.dp))
        Text(
            link.title,
            style = uiText(17, if (link.isPrimaryAction) Weight.HEAVY else Weight.SEMIBOLD),
            color = if (link.isPrimaryAction) ThemeToken.Primary.color else ThemeToken.Text.color,
            modifier = Modifier.weight(1f),
        )
        if (link.showsChevron) Chevron()
    }
}

/** Ikonen för varje slags länk. */
private val SourceLink.icon: ImageVector
    get() = when (kind) {
        SourceLink.Kind.Website -> AppSymbols.Language
        SourceLink.Kind.KommunInfo -> AppSymbols.LocationCity
        SourceLink.Kind.Phone -> AppSymbols.Phone
        SourceLink.Kind.Email -> Icons.Filled.Email
        SourceLink.Kind.ContactPage -> AppSymbols.Mail
        SourceLink.Kind.Calendar -> AppSymbols.CalendarMonth
    }
