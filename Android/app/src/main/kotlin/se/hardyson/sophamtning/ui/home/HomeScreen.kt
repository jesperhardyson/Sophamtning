package se.hardyson.sophamtning.ui.home

import androidx.compose.runtime.key
import se.hardyson.sophamtning.ui.components.MinuteTick
import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings as SettingsIcon
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.app.StorageProblem
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.kommun.WebLink
import se.hardyson.sophamtning.core.messages.ActiveSourceMessage
import se.hardyson.sophamtning.core.placedout.PlacedOutTexts
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.KommunCheck
import se.hardyson.sophamtning.navigation.Rename
import se.hardyson.sophamtning.navigation.Settings as SettingsKey
import se.hardyson.sophamtning.ui.bin.BIN_ASPECT
import se.hardyson.sophamtning.ui.bin.BinRoundView
import se.hardyson.sophamtning.ui.bin.scaledBinWidth
import androidx.compose.ui.unit.DpSize
import se.hardyson.sophamtning.ui.bin.BubbleTip
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageLink
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.PlainButton
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.components.openWebLink
import se.hardyson.sophamtning.ui.start.StartContent
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.brandText
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Hemskärmen: startvyn utan adresser, annars huvudkortet och övriga adresser, som HomeView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: HomeViewModel = viewModel { HomeViewModel(dependencies) }
    val ui by vm.ui.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var refreshing by remember { mutableStateOf(false) }
    // Ett tryck på rubriken räknas som ett tryck på kärlet bredvid.
    var titleTaps by remember { mutableIntStateOf(0) }
    val titleBinWidth = scaledBinWidth(TITLE_BIN_WIDTH, TITLE_BIN_MAX_WIDTH)

    // Hämtningen när appen kommer i förgrunden görs för hela appen, i AppNavigation. Här räknas bara dagen om.
    LifecycleResumeEffect(Unit) {
        vm.tick()
        onPauseOrDispose {}
    }
    MinuteTick(dependencies.clock, vm::tick)

    val content = ui.content
    val primary = content.primary
    val problem = ui.state.storageProblem
    val filled = primary != null && problem == null
    val placeOut = { entry: HomeContent.Entry ->
        vm.placeOut(entry) { ok ->
            // Ångra finns också i en snackbar, direkt efter trycket.
            if (ok) scope.launch {
                snackbar.currentSnackbarData?.dismiss()
                val result = snackbar.showSnackbar(PlacedOutTexts.OWN_PLACED_OUT, actionLabel = PlacedOutTexts.UNDO, duration = SnackbarDuration.Short)
                if (result == SnackbarResult.ActionPerformed) vm.undoPlaceOut(entry)
            }
        }
    }
    ScreenScaffold(
        title = if (filled) stringResource(R.string.app_title) else "",
        onBack = null,
        large = filled,
        snackbarHostState = snackbar,
        largeTitleLeading = { BinRoundView(width = TITLE_BIN_WIDTH, maxWidth = TITLE_BIN_MAX_WIDTH, bubbleTip = BubbleTip.Start, firstRound = "rubrik", tapTrigger = titleTaps) },
        largeTitleLeadingSize = titleBinWidth.let { DpSize(it, it * BIN_ASPECT) },
        onLargeTitleTap = { titleTaps += 1 },
        actions = {
            // Vid lagringsfel finns inga knappar.
            if (problem == null) {
                IconButton(onClick = { navigator.open(SettingsKey) }) { Icon(Icons.Filled.SettingsIcon, contentDescription = stringResource(R.string.settings_title)) }
            }
            if (filled) {
                IconButton(onClick = { navigator.open(AddAddress()) }) { Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.action_add)) }
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    vm.refresh()
                    refreshing = false
                }
            },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 24.dp)) {
                ui.state.lastStorageError?.let { error ->
                    // Ett felmeddelande i flödet, som stängs med ett tryck.
                    MessageCard(
                        title = stringResource(R.string.error_title),
                        text = stringResource(R.string.error_tap_to_close, error),
                        style = MessageStyle.Warning,
                        icon = Icons.Filled.Warning,
                        modifier = Modifier.padding(top = 12.dp).clickable(role = Role.Button) { vm.clearStorageError() },
                    )
                }
                when {
                    problem != null -> StorageProblemView(problem, vm::retryStorage, vm::startOver)
                    primary != null -> Filled(ui, primary, content.others, vm, navigator, placeOut, undo = { entry ->
                        // Snackbaren med sitt eget Ångra stängs, så att den inte ångrar något som redan är ångrat.
                        snackbar.currentSnackbarData?.dismiss()
                        vm.undoPlaceOut(entry)
                    })
                    else -> StartContent(onSearch = { navigator.open(AddAddress()) }, onKommun = { navigator.open(KommunCheck) })
                }
                Text(
                    stringResource(R.string.disclaimer),
                    style = uiText(15, Weight.SEMIBOLD),
                    color = ThemeToken.Text2.color,
                    modifier = Modifier.padding(top = 32.dp),
                )
            }
        }
    }
}

@Composable
private fun Filled(
    ui: HomeViewModel.Ui,
    primary: HomeContent.Entry,
    others: List<HomeContent.Entry>,
    vm: HomeViewModel,
    navigator: AppNavigator,
    placeOut: (HomeContent.Entry) -> Unit,
    undo: (HomeContent.Entry) -> Unit,
) {
    val context = LocalContext.current
    Column(Modifier.padding(top = 8.dp)) {
        for (item in ui.messages) {
            SourceMessageCard(item, ui.state.sourceNames[item.source], onOpen = context::openWebLink, onClose = { vm.dismissMessage(item) })
        }
        if (ui.showsReminderOffer) {
            ReminderOfferCard(onAccept = { vm.acceptReminderOffer(primary.key) }, onDecline = vm::declineReminderOffer, modifier = Modifier.padding(bottom = 16.dp))
        }
        // En ny huvudadress får ett eget svep, så att inget läge följer med från den borttagna.
        key(primary.key) {
            SwipeToRemove(onRemove = { vm.remove(primary.key) }, cornerRadius = 28.dp) {
                AddressMenu(menuChoices(ui, primary, vm, navigator)) { onLongPress, actions ->
                    PrimaryCard(primary, onOpen = { navigator.open(Address(primary.key)) }, onLongPress = onLongPress, actions = actions) {
                        val reminder = primary.reminder.takeIf { primary.status is HomeContent.Status.Upcoming }
                        if (reminder?.showsDeniedNotice == true) DeniedReminderNotice { context.openNotificationSettings() }
                        primary.placedOut?.let { line ->
                            PlacedOutRow(line, onCard = true, onPlaceOut = { placeOut(primary) }, onUndo = { undo(primary) })
                        }
                    }
                }
            }
        }
        if (others.isNotEmpty()) {
            OthersTitle()
            for (entry in others) {
                // Varje rad behåller sitt svep och sin bekräftelse när en annan adress tas bort.
                key(entry.key) {
                    SwipeToRemove(onRemove = { vm.remove(entry.key) }, cornerRadius = 20.dp, modifier = Modifier.padding(bottom = 12.dp)) {
                        AddressMenu(menuChoices(ui, entry, vm, navigator)) { onLongPress, actions ->
                            AddressRow(entry, onOpen = { navigator.open(Address(entry.key)) }, onLongPress = onLongPress, actions = actions)
                        }
                    }
                }
            }
        }
    }
}

/** Det lilla kärlet bredvid rubriken, ungefär lika högt som texten, och som störst med största text. */
private val TITLE_BIN_WIDTH = 30.dp
private val TITLE_BIN_MAX_WIDTH = 56.dp

/** Snabbmenyns val för en adress på hemskärmen. */
private fun menuChoices(ui: HomeViewModel.Ui, entry: HomeContent.Entry, vm: HomeViewModel, navigator: AppNavigator): AddressMenuChoices {
    val state = ui.state
    val address = state.address(entry.key)
    return AddressMenuChoices(
        isPrimary = address?.isPrimary ?: false,
        remindersAvailable = state.remindersAvailable,
        remindersOn = address?.let(state::remindersOn) ?: false,
        liveUpdateOn = state.settings.liveActivityOn,
        onRename = { navigator.open(Rename(entry.key)) },
        onMakePrimary = { vm.setPrimary(entry.key) },
        onNotifications = { on, onDenied -> vm.setNotifications(on, entry.key, onDenied) },
        onLiveUpdate = vm::setLiveActivity,
        onRemove = { vm.remove(entry.key) },
    )
}

/** Ett meddelande från källan, till exempel att hämtrutterna läggs om. Länken har samma ordval som på sajten. */
@Composable
private fun SourceMessageCard(item: ActiveSourceMessage, sourceName: String?, onOpen: (WebLink) -> Unit, onClose: () -> Unit) {
    // Bara https-länkar visas, och de öppnas i Custom Tabs.
    val link = item.message.url?.let { WebLink(it) }?.let { web ->
        MessageLink(sourceName?.let { stringResource(R.string.message_read_more_at, it) } ?: stringResource(R.string.message_read_more)) { onOpen(web) }
    }
    MessageCard(
        title = item.message.title,
        text = item.message.text,
        style = MessageStyle.Neutral,
        icon = AppSymbols.Campaign,
        link = link,
        closeLabel = stringResource(R.string.message_close),
        onClose = onClose,
        modifier = Modifier.padding(bottom = 16.dp),
    )
}

/**
 * "Vill du bli påmind?" efter att den första adressen har sparats. Påminnelser är avstängda från början, och inget
 * schemaläggs förrän användaren trycker **Påminn mig**.
 */
@Composable
private fun ReminderOfferCard(onAccept: () -> Unit, onDecline: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.fillMaxWidth().background(ThemeToken.Surface.color, shape).border(1.dp, ThemeToken.Border.color, shape).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(AppSymbols.NotificationsActive, contentDescription = null, tint = ThemeToken.Primary.color, modifier = Modifier.size(24.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.offer_title), style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.semantics { heading() })
                Text(stringResource(R.string.offer_text), style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
            }
        }
        if (isLargeText()) {
            PrimaryButton(stringResource(R.string.offer_accept), onAccept)
            PlainButton(stringResource(R.string.offer_decline), onDecline)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PrimaryButton(stringResource(R.string.offer_accept), onAccept, Modifier.weight(1f))
                PlainButton(stringResource(R.string.offer_decline), onDecline, Modifier.weight(1f))
            }
        }
    }
}

/** Rutan när påminnelsen är på men systemet nekar notiser, med en knapp till appens notisinställningar. */
@Composable
private fun DeniedReminderNotice(onOpenSettings: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(ThemeToken.CardOverlay.color, RoundedCornerShape(16.dp)).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(HomeContent.RowReminder.Denied.text, style = uiText(15, Weight.BOLD), color = ThemeToken.OnPrimary.color)
        TextButton(onClick = onOpenSettings) { Text(stringResource(R.string.action_open_settings), style = uiText(15, Weight.HEAVY), color = ThemeToken.OnPrimary.color) }
    }
}

/** Appens notisinställningar i systemet, där användaren kan slå på notiser igen. */
fun Context.openNotificationSettings() {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(intent) }
}

/** En fil som inte går att läsa är inte ett tomt läge: inget är raderat, och inget skrivs över. */
@Composable
private fun StorageProblemView(problem: StorageProblem, onRetry: () -> Unit, onStartOver: () -> Unit) {
    val addresses = problem == StorageProblem.AddressesUnreadable || problem == StorageProblem.AddressesUnavailable
    // Bara en skadad fil kan göras om. En fil som bara är otillgänglig just nu rörs aldrig.
    val corrupt = problem == StorageProblem.AddressesUnreadable || problem == StorageProblem.SettingsUnreadable
    val title = when (problem) {
        StorageProblem.AddressesUnreadable -> stringResource(R.string.storage_addresses_unreadable)
        StorageProblem.AddressesUnavailable -> stringResource(R.string.storage_addresses_unavailable)
        StorageProblem.SettingsUnreadable -> stringResource(R.string.storage_settings_unreadable)
        StorageProblem.SettingsUnavailable -> stringResource(R.string.storage_settings_unavailable)
    }
    var confirming by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.Start) {
        Text(title, style = brandText(30), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 32.dp).semantics { heading() })
        MessageCard(
            title = stringResource(R.string.storage_nothing_removed),
            text = if (corrupt) {
                stringResource(R.string.storage_corrupt_text)
            } else {
                stringResource(R.string.storage_unavailable_text)
            },
            style = MessageStyle.Warning,
            icon = Icons.Filled.Warning,
        )
        PrimaryButton(stringResource(R.string.action_retry), onRetry)
        if (corrupt) PlainButton(stringResource(R.string.storage_start_over), { confirming = true })
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(if (addresses) stringResource(R.string.storage_start_over_addresses_title) else stringResource(R.string.storage_start_over_settings_title)) },
            text = {
                Text(
                    if (addresses) {
                        stringResource(R.string.storage_start_over_addresses_text)
                    } else {
                        stringResource(R.string.storage_start_over_settings_text)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    onStartOver()
                }) { Text(if (addresses) stringResource(R.string.storage_start_over_addresses_confirm) else stringResource(R.string.storage_start_over_settings_confirm), color = ThemeToken.Warn.color) }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.action_cancel)) } },
            containerColor = ThemeToken.Surface.color,
        )
    }
}
