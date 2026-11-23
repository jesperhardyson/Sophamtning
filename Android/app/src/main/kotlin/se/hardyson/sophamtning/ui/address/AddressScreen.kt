package se.hardyson.sophamtning.ui.address

import se.hardyson.sophamtning.ui.components.MinuteTick
import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.app.StorageProblem
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.kommun.CalendarLink
import se.hardyson.sophamtning.core.kommun.SourceLink
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.FullSchedule
import se.hardyson.sophamtning.navigation.Rename
import se.hardyson.sophamtning.ui.components.AddressPlaceLine
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.CalendarTile
import se.hardyson.sophamtning.ui.components.CapsTracking
import se.hardyson.sophamtning.ui.components.ChipRow
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.components.SectionTitle
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.home.PlacedOutRow
import se.hardyson.sophamtning.ui.home.openNotificationSettings
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText


@Composable
private fun addressViewModel(key: AddressKey): AddressViewModel {
    val dependencies = LocalAppDependencies.current
    return viewModel { AddressViewModel(dependencies, key) }
}

/** Adressvyn, med det viktigaste först: nästa tömning, de närmaste datumen, kärlen, påminnelser och sist källan. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddressScreen(key: AddressKey, navigator: AppNavigator) {
    val vm = addressViewModel(key)
    val ui by vm.ui.collectAsStateWithLifecycle()
    val detail = ui.detail
    var confirmingRemoval by rememberSaveable { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var deniedDialog by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val clock = LocalAppDependencies.current.clock
    LifecycleResumeEffect(Unit) {
        vm.tick()
        onPauseOrDispose {}
    }
    MinuteTick(clock, vm::tick)
    ScreenScaffold(
        title = detail?.title ?: "",
        onBack = { navigator.back() },
        large = true,
        actions = {
            if (detail != null) {
                Box {
                    IconButton(onClick = { menuOpen = true }) { Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.action_more)) }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.action_rename)) }, leadingIcon = { Icon(Icons.Filled.Edit, null) }, onClick = {
                            menuOpen = false
                            navigator.open(Rename(key))
                        })
                        if (!detail.isPrimary) {
                            DropdownMenuItem(text = { Text(stringResource(R.string.action_make_primary)) }, leadingIcon = { Icon(Icons.Filled.Home, null) }, onClick = {
                                menuOpen = false
                                vm.setPrimary()
                            })
                        }
                        DropdownMenuItem(text = { Text(stringResource(R.string.action_remove)) }, leadingIcon = { Icon(Icons.Filled.Delete, null) }, onClick = {
                            menuOpen = false
                            confirmingRemoval = true
                        })
                    }
                }
            }
        },
    ) { padding ->
        RefreshableColumn(onRefresh = vm::refresh, modifier = Modifier.padding(padding)) {
            ui.state.lastStorageError?.let { StorageErrorCard(it, vm::clearStorageError) }
            if (detail == null) {
                MissingAddress(ui.state.storageProblem)
                return@RefreshableColumn
            }
            AddressPlaceLine(detail.lines, Modifier.padding(bottom = 20.dp))
            AddressNotice(detail.notice, onRetry = vm::retry, onSearchAgain = {
                navigator.home()
                navigator.open(AddAddress(replacing = key))
            })
            // Före datumen: den som bor på en sådan gata ska se det innan hen litar på dem.
            detail.otherDays?.let { OtherDaysCard(it, Modifier.padding(bottom = 12.dp)) }
            when (detail.mode) {
                AddressDetail.Mode.Loading -> ScheduleLoadingCard(Modifier.padding(top = 20.dp))
                AddressDetail.Mode.Unavailable -> {}
                AddressDetail.Mode.NoUpcoming -> Box(Modifier.padding(bottom = 4.dp)) { NoUpcomingCard(detail.noUpcomingMessage) }
                AddressDetail.Mode.Schedule -> Schedule(detail, vm, onFullSchedule = { navigator.open(FullSchedule(key)) })
            }
            // Utan hämtningar bara när en påminnelse är på, så att den går att stänga av.
            if (detail.showsReminders) Reminders(detail, ui, vm, onDenied = { deniedDialog = true })
            detail.calendarLink?.let { url ->
                SectionTitle(CalendarLink.SECTION)
                SectionCard { SourceLinkRow(SourceLink.calendar(url)) }
                Text(CalendarLink.FOOTER, style = uiText(13, Weight.SEMIBOLD), color = ThemeToken.Text2.color, modifier = Modifier.padding(horizontal = 20.dp).padding(top = 8.dp))
            }
            SourceCard(key.source, ui.sources, detail, Modifier.padding(top = 28.dp))
        }
    }
    if (confirmingRemoval) {
        RemoveAddressDialog(onRemove = {
            confirmingRemoval = false
            // Gick borttagningen inte att spara är adressen kvar, och felet visas här.
            if (vm.remove()) navigator.home()
        }, onDismiss = { confirmingRemoval = false })
    }
    if (deniedDialog) {
        AlertDialog(
            onDismissRequest = { deniedDialog = false },
            title = { Text(stringResource(R.string.notifications_denied_title)) },
            text = { Text(stringResource(R.string.notifications_denied_text)) },
            confirmButton = {
                TextButton(onClick = {
                    deniedDialog = false
                    context.openNotificationSettings()
                }) { Text(stringResource(R.string.action_open_settings)) }
            },
            dismissButton = { TextButton(onClick = { deniedDialog = false }) { Text(stringResource(R.string.action_ok)) } },
            containerColor = ThemeToken.Surface.color,
        )
    }
}

/** Hela det kommande schemat, i samma format som raderna under "Kommande". Vyn är aldrig tom. */
@Composable
fun FullScheduleScreen(key: AddressKey, navigator: AppNavigator) {
    val vm = addressViewModel(key)
    val ui by vm.ui.collectAsStateWithLifecycle()
    val clock = LocalAppDependencies.current.clock
    LifecycleResumeEffect(Unit) {
        vm.tick()
        onPauseOrDispose {}
    }
    MinuteTick(clock, vm::tick)
    ScreenScaffold(title = stringResource(R.string.full_schedule), onBack = { navigator.back() }, large = true) { padding ->
        RefreshableColumn(onRefresh = vm::refresh, modifier = Modifier.padding(padding)) {
            val detail = ui.detail
            if (detail == null) {
                MissingAddress(ui.state.storageProblem)
                return@RefreshableColumn
            }
            // Rubriken är "Hela schemat", så namnet står här.
            AddressPlaceLine(detail.namedLines, Modifier.padding(bottom = 20.dp))
            AddressNotice(detail.notice, onRetry = vm::retry, onSearchAgain = {
                navigator.home()
                navigator.open(AddAddress(replacing = key))
            })
            detail.otherDays?.let { OtherDaysCard(it, Modifier.padding(bottom = 12.dp)) }
            when (detail.mode) {
                AddressDetail.Mode.Loading -> ScheduleLoadingCard()
                AddressDetail.Mode.Unavailable -> {}
                AddressDetail.Mode.NoUpcoming -> NoUpcomingCard(detail.noUpcomingMessage)
                AddressDetail.Mode.Schedule -> ScheduleList(detail.rows)
            }
            detail.schedulePeriod?.let { SchedulePeriodView(it, Modifier.padding(top = 12.dp)) }
            SourceCard(key.source, ui.sources, detail, Modifier.padding(top = 28.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RefreshableColumn(onRefresh: suspend () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                onRefresh()
                refreshing = false
            }
        },
        modifier = modifier.fillMaxSize(),
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 32.dp), content = content)
    }
}

@Composable
private fun StorageErrorCard(error: String, onClear: () -> Unit) {
    MessageCard(
        title = stringResource(R.string.error_title),
        text = stringResource(R.string.error_tap_to_close, error),
        style = MessageStyle.Warning,
        icon = Icons.Filled.Warning,
        modifier = Modifier.padding(bottom = 16.dp).clickable(role = Role.Button, onClick = onClear),
    )
}

/** Adressen togs bort, eller adresserna går inte att läsa just nu. Ett läsfel får aldrig se ut som en borttagen adress. */
@Composable
private fun MissingAddress(problem: StorageProblem?) {
    if (problem == StorageProblem.AddressesUnreadable || problem == StorageProblem.AddressesUnavailable) {
        MessageCard(stringResource(R.string.storage_addresses_unavailable), stringResource(R.string.missing_unreadable_text), MessageStyle.Warning, Icons.Filled.Warning)
    } else {
        MessageCard(stringResource(R.string.missing_removed_title), stringResource(R.string.missing_removed_text), MessageStyle.Neutral, AppSymbols.LocationCity)
    }
}

@Composable
private fun Schedule(detail: AddressDetail, vm: AddressViewModel, onFullSchedule: () -> Unit) {
    detail.next?.let { NextCard(it, detail.nextDeviation) }
    detail.placedOut?.let { line ->
        PlacedOutRow(line, onCard = false, onPlaceOut = vm::placeOut, onUndo = vm::undoPlaceOut, modifier = Modifier.padding(top = 16.dp))
    }
    detail.nextWarning?.let { MessageCard(stringResource(R.string.source_warning), it, MessageStyle.Warning, Icons.Filled.Warning, Modifier.padding(top = 12.dp)) }
    if (detail.upcoming.isNotEmpty()) {
        if (isLargeText()) {
            SectionTitle(stringResource(R.string.section_upcoming))
            if (detail.hasFullSchedule) FullScheduleLink(onFullSchedule, Modifier.padding(bottom = 12.dp))
        } else {
            Row(verticalAlignment = Alignment.Bottom) {
                SectionTitle(stringResource(R.string.section_upcoming), Modifier.weight(1f))
                if (detail.hasFullSchedule) FullScheduleLink(onFullSchedule, Modifier.padding(bottom = 4.dp))
            }
        }
        ScheduleList(detail.upcoming)
    }
    // Hur långt schemat gäller, direkt under de kommande tömningarna.
    detail.schedulePeriod?.let { SchedulePeriodView(it, Modifier.padding(top = 12.dp)) }
    detail.scheduleEnding?.let { MessageCard(it.title, it.message, MessageStyle.Neutral, AppSymbols.CalendarMonth, Modifier.padding(top = 12.dp)) }
    SectionTitle(stringResource(R.string.section_bins))
    SectionCard {
        detail.bins.forEachIndexed { index, bin ->
            if (index > 0) SectionDivider()
            BinRow(bin)
        }
    }
}

@Composable
private fun FullScheduleLink(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.full_schedule), style = uiText(16, Weight.HEAVY), color = ThemeToken.Primary.color)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = ThemeToken.Primary.color)
    }
}

@Composable
private fun NextCard(next: HomeContent.Pickup, deviation: String?) {
    val shape = RoundedCornerShape(28.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(ThemeToken.Surface.color, shape)
            .border(1.dp, ThemeToken.Border.color, shape)
            .clearAndSetSemantics { contentDescription = listOfNotNull(next.accessibilityLabel, deviation).joinToString(". ") }
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        val text: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.next_pickup_caps), style = uiText(13, Weight.HEAVY).copy(letterSpacing = CapsTracking), color = ThemeToken.BrandText.color)
                Text(next.headline, style = uiText(32, Weight.HEAVY), color = ThemeToken.Text.color)
                Text(next.longDate, style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
                // Står här och inte under Kommande, som börjar efter nästa tömning.
                deviation?.let { Text(it, style = uiText(15, Weight.BOLD), color = ThemeToken.Warn.color) }
            }
        }
        if (isLargeText()) {
            CalendarTile(next.date)
            text()
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                CalendarTile(next.date)
                text()
            }
        }
        ChipRow(next.fractions)
    }
}

@Composable
private fun Reminders(detail: AddressDetail, ui: AddressViewModel.Ui, vm: AddressViewModel, onDenied: () -> Unit) {
    val context = LocalContext.current
    SectionTitle(stringResource(R.string.section_reminders))
    detail.missedReminder?.let { MessageCard(stringResource(R.string.reminder_missed), it, MessageStyle.Neutral, AppSymbols.Schedule, Modifier.padding(bottom = 12.dp)) }
    if (ui.notificationsDenied) {
        Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            MessageCard(stringResource(R.string.notifications_denied_title), stringResource(R.string.notifications_denied_text), MessageStyle.Warning, Icons.Filled.Warning)
            TextButton(onClick = { context.openNotificationSettings() }) {
                Text(stringResource(R.string.action_open_settings), style = uiText(17, Weight.HEAVY), color = ThemeToken.Primary.color)
            }
        }
    }
    SectionCard {
        ToggleRow(HomeContent.reminderTitle(), detail.reminderText, ui.remindersOn) { on -> vm.setNotifications(on, onDenied) }
        // Live Update gäller bara huvudadressen.
        if (detail.isPrimary) {
            SectionDivider()
            ToggleRow(stringResource(R.string.live_update), detail.liveActivityText, ui.state.settings.liveActivityOn, vm::setLiveActivity)
        }
    }
}

/** En rad med reglage, som ReminderToggleRow.swift. Hela raden är reglaget för TalkBack. */
@Composable
private fun ToggleRow(title: String, text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
            Text(text, style = uiText(15, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(checkedTrackColor = ThemeToken.Primary.color, checkedThumbColor = ThemeToken.OnPrimary.color),
        )
    }
}
