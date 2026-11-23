package se.hardyson.sophamtning.ui.home

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
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
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

    // Hämtar när appen kommer i förgrunden och när man kommer tillbaka till hemskärmen.
    LifecycleResumeEffect(Unit) {
        vm.onShown()
        onPauseOrDispose {}
    }
    // Räknar om dagen vid varje minutbyte medan skärmen syns, till exempel vid midnatt.
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000L - dependencies.clock().toEpochMilli() % 60_000L)
            vm.tick()
        }
    }

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
        title = if (filled) "Sophämtning" else "",
        onBack = null,
        large = filled,
        snackbarHostState = snackbar,
        actions = {
            if (filled) {
                IconButton(onClick = { navigator.open(AddAddress()) }) { Icon(Icons.Filled.Add, contentDescription = "Lägg till") }
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
                        title = "Något gick fel",
                        text = "$error Tryck för att stänga.",
                        style = MessageStyle.Warning,
                        icon = Icons.Filled.Warning,
                        modifier = Modifier.padding(top = 12.dp).clickable(role = Role.Button) { vm.clearStorageError() },
                    )
                }
                when {
                    problem != null -> StorageProblemView(problem, vm::retryStorage, vm::startOver)
                    primary != null -> Filled(ui, primary, content.others, vm, navigator, placeOut)
                    else -> StartContent(onSearch = { navigator.open(AddAddress()) }, onKommun = { navigator.open(KommunCheck) })
                }
                Text(
                    "Inofficiell app, inte kopplad till någon kommun. Vid avvikelser gäller kommunens information.",
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
) {
    val context = LocalContext.current
    Column(Modifier.padding(top = 8.dp)) {
        for (item in ui.messages) {
            SourceMessageCard(item, ui.state.sourceNames[item.source], onOpen = context::openWebLink, onClose = { vm.dismissMessage(item) })
        }
        if (ui.showsReminderOffer) {
            ReminderOfferCard(onAccept = { vm.acceptReminderOffer(primary.key) }, onDecline = vm::declineReminderOffer, modifier = Modifier.padding(bottom = 16.dp))
        }
        SwipeToRemove(onRemove = { vm.remove(primary.key) }, cornerRadius = 28.dp) {
            PrimaryCard(primary, onOpen = { navigator.open(Address(primary.key)) }) {
                val reminder = primary.reminder.takeIf { primary.status is HomeContent.Status.Upcoming }
                if (reminder?.showsDeniedNotice == true) DeniedReminderNotice { context.openNotificationSettings() }
                primary.placedOut?.let { line ->
                    PlacedOutRow(line, onCard = true, onPlaceOut = { placeOut(primary) }, onUndo = { vm.undoPlaceOut(primary) })
                }
            }
        }
        if (others.isNotEmpty()) {
            OthersTitle()
            for (entry in others) {
                SwipeToRemove(onRemove = { vm.remove(entry.key) }, cornerRadius = 20.dp, modifier = Modifier.padding(bottom = 12.dp)) {
                    AddressRow(entry, onOpen = { navigator.open(Address(entry.key)) })
                }
            }
        }
    }
}

/** Ett meddelande från källan, till exempel att hämtrutterna läggs om. Länken har samma ordval som på sajten. */
@Composable
private fun SourceMessageCard(item: ActiveSourceMessage, sourceName: String?, onOpen: (WebLink) -> Unit, onClose: () -> Unit) {
    // Bara https-länkar visas, och de öppnas i Custom Tabs.
    val link = item.message.url?.let { WebLink(it) }?.let { web ->
        MessageLink(sourceName?.let { "Läs mer hos $it" } ?: "Läs mer") { onOpen(web) }
    }
    MessageCard(
        title = item.message.title,
        text = item.message.text,
        style = MessageStyle.Neutral,
        icon = AppSymbols.Campaign,
        link = link,
        closeLabel = "Stäng meddelandet",
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
                Text("Vill du bli påmind?", style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.semantics { heading() })
                Text("Få en notis kvällen före varje tömning. Du kan ändra det när som helst.", style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
            }
        }
        if (isLargeText()) {
            PrimaryButton("Påminn mig", onAccept)
            PlainButton("Inte nu", onDecline)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PrimaryButton("Påminn mig", onAccept, Modifier.weight(1f))
                PlainButton("Inte nu", onDecline, Modifier.weight(1f))
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
        TextButton(onClick = onOpenSettings) { Text("Öppna inställningar", style = uiText(15, Weight.HEAVY), color = ThemeToken.OnPrimary.color) }
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
        StorageProblem.AddressesUnreadable -> "Dina sparade adresser kunde inte läsas"
        StorageProblem.AddressesUnavailable -> "Dina adresser kan inte läsas just nu"
        StorageProblem.SettingsUnreadable -> "Dina inställningar kunde inte läsas"
        StorageProblem.SettingsUnavailable -> "Dina inställningar kan inte läsas just nu"
    }
    var confirming by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.Start) {
        Text(title, style = brandText(30), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 32.dp).semantics { heading() })
        MessageCard(
            title = "Inget har raderats",
            text = if (corrupt) {
                "Filen på telefonen är skadad. Försök igen. Fungerar det inte kan du börja om."
            } else {
                "Lås upp telefonen och försök igen. Är den upplåst kan filen vara skyddad en kort stund efter en omstart."
            },
            style = MessageStyle.Warning,
            icon = Icons.Filled.Warning,
        )
        PrimaryButton("Försök igen", onRetry)
        if (corrupt) PlainButton("Börja om", { confirming = true })
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(if (addresses) "Börja om utan sparade adresser?" else "Använda standardinställningarna?") },
            text = {
                Text(
                    if (addresses) {
                        "Dina sparade adresser tas bort från appen och appens väntande påminnelser avbryts. Den skadade filen sparas åt sidan på telefonen. Därefter kan du lägga till adresser igen."
                    } else {
                        "Påminnelsetid och Live Update återställs till standard (kl. 18:00, Live Update av). Dina adresser behålls. Den skadade filen sparas åt sidan på telefonen."
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    onStartOver()
                }) { Text(if (addresses) "Ta bort sparade adresser och börja om" else "Använd standardinställningar", color = ThemeToken.Warn.color) }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Avbryt") } },
            containerColor = ThemeToken.Surface.color,
        )
    }
}
