package se.hardyson.sophamtning.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.Composable
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.net.toUri
import androidx.lifecycle.compose.LifecycleResumeEffect
import android.content.Context
import android.content.Intent
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.hardyson.sophamtning.BuildConfig
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.app.AppState
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.reminders.ReminderSettingsTexts
import se.hardyson.sophamtning.core.reminders.title
import se.hardyson.sophamtning.navigation.LiveUpdateTiming
import se.hardyson.sophamtning.navigation.ReminderTimes
import se.hardyson.sophamtning.reminders.Alarms
import se.hardyson.sophamtning.ui.home.openNotificationSettings
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.Changelog
import se.hardyson.sophamtning.navigation.DataSources
import se.hardyson.sophamtning.navigation.PrimaryAddressChoice
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.components.openWeb

/** Integritetspolicyn på `sopor.hardyson.se`. */
private const val PRIVACY_URL = "https://sopor.hardyson.se/integritet"

/**
 * Inställningarna, som SettingsView.swift utan hushållet och Siri: notiserna, Live Update, huvudadressen och om appen.
 * Notiserna, Meddelanden från källan och Live Update visas bara när påminnelserna finns ([AppState.remindersAvailable]).
 */
@Composable
fun SettingsScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(dependencies) }
    val sourcesVm: SourcesViewModel = viewModel { SourcesViewModel(dependencies) }
    val state by vm.state.collectAsStateWithLifecycle()
    val sources by sourcesVm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current
    ScreenScaffold(title = stringResource(R.string.settings_title), onBack = { navigator.back() }, large = true) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 32.dp),
        ) {
            state.lastStorageError?.let { error ->
                MessageCard(
                    title = stringResource(R.string.error_title),
                    text = stringResource(R.string.error_tap_to_close, error),
                    style = MessageStyle.Warning,
                    icon = Icons.Filled.Warning,
                    modifier = Modifier.padding(top = 8.dp).clickable(role = Role.Button, onClick = vm::clearStorageError),
                )
            }
            if (state.remindersAvailable) Reminders(state, vm, navigator, missedReminder = state.missedReminderText(dependencies.clock()))
            state.primary?.let { primary ->
                SettingsHeading(stringResource(R.string.settings_primary))
                SectionCard { SettingsRow(primary.displayName, "") { navigator.open(PrimaryAddressChoice) } }
                SettingsFootnote(ReminderSettingsTexts.PRIMARY_FOOTER)
            }
            SettingsHeading(stringResource(R.string.settings_about))
            SectionCard {
                SettingsRow(stringResource(R.string.settings_sources), sources.shown?.size?.toString() ?: "") { navigator.open(DataSources) }
                SectionDivider()
                SettingsRow(stringResource(R.string.settings_privacy), "") { context.openWeb(PRIVACY_URL) }
                SectionDivider()
                SettingsRow(stringResource(R.string.settings_version), BuildConfig.VERSION_NAME) { navigator.open(Changelog) }
            }
            MessageCard(
                title = stringResource(R.string.settings_unofficial_title),
                text = stringResource(R.string.settings_unofficial_text),
                style = MessageStyle.Neutral,
                icon = Icons.Filled.Info,
                modifier = Modifier.padding(top = 24.dp),
            )
        }
    }
}

/**
 * Notiser, Meddelanden från källan och Live Update, var och en i ett eget kort med en rad under om vad den gäller. Raden
 * Exakta tider visas bara när en påminnelse är på och systemet inte tillåter exakta alarm. Den öppnar systemets
 * inställning, och appen begär aldrig exakta alarm själv.
 */
@Composable
private fun Reminders(state: AppState, vm: SettingsViewModel, navigator: AppNavigator, missedReminder: String?) {
    val context = LocalContext.current
    val authorized = state.notificationAuthorization == NotificationAuthorization.Authorized
    // Läses om när appen kommer tillbaka, till exempel från systemets inställning för exakta tider.
    var resumed by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        resumed++
        onPauseOrDispose {}
    }
    val anyOn = state.addresses.any(state::remindersOn) || state.settings.liveActivityOn
    val exactNeeded = resumed >= 0 && anyOn && !Alarms.canScheduleExact(context)

    SettingsHeading(stringResource(R.string.settings_notifications))
    SectionCard {
        SettingsRow(stringResource(R.string.settings_time), state.settings.settingsValue) { navigator.open(ReminderTimes) }
        if (exactNeeded) {
            SectionDivider()
            SettingsRow(stringResource(R.string.settings_exact_times), stringResource(R.string.settings_exact_times_value)) {
                context.openExactAlarmSettings()
            }
        }
    }
    SettingsFootnote(
        ReminderSettingsTexts.notificationsFooter(ReminderSettingsTexts.homeOrder(state.addresses).filter(state::remindersOn).map { it.displayName }),
    )
    if (exactNeeded) SettingsFootnote(stringResource(R.string.settings_exact_times_footer))
    missedReminder?.let {
        MessageCard(stringResource(R.string.reminder_missed), it, MessageStyle.Neutral, AppSymbols.Schedule, Modifier.padding(top = 12.dp))
    }
    // Reglaget frågar aldrig om tillstånd, och utan tillstånd i systemet går det inte att ändra.
    SectionCard(Modifier.padding(top = 16.dp)) {
        SettingsToggleRow(
            stringResource(R.string.settings_source_messages),
            checked = state.settings.sourceMessagesOn,
            onChange = vm::setSourceMessages,
            icon = AppSymbols.Campaign,
            enabled = authorized,
        )
    }
    SettingsFootnote(ReminderSettingsTexts.sourceMessagesFooter(authorized))

    SettingsHeading(stringResource(R.string.live_update))
    SectionCard {
        ReminderToggleRow(stringResource(R.string.live_update), AddressDetail.liveActivityText(state.settings), state.settings.liveActivityOn, vm::setLiveActivity)
        if (state.settings.liveActivityOn) {
            SectionDivider()
            SettingsRow(
                stringResource(R.string.settings_live_update_from),
                "${state.settings.liveActivityTiming.title}, ${SwedishFormat.clock(state.settings.liveActivityStartMinutes)}",
            ) { navigator.open(LiveUpdateTiming) }
        }
    }
    state.primary?.let { SettingsFootnote(ReminderSettingsTexts.liveActivityFooter(it.displayName)) }
    LiveUpdateNotices(state)
}

/**
 * Rutorna när Live Update är på men systemet inte visar den, med en knapp till appens notisinställningar, och när den
 * inte gick att lägga in. Som LiveActivityNotices i SettingsView.swift.
 */
@Composable
private fun LiveUpdateNotices(state: AppState) {
    val context = LocalContext.current
    if (state.settings.liveActivityOn && !state.liveActivitiesEnabled) {
        Column(Modifier.padding(top = 12.dp)) {
            MessageCard(stringResource(R.string.live_update_off_title), stringResource(R.string.live_update_off_text), MessageStyle.Warning, Icons.Filled.Warning)
            TextButton(onClick = { context.openNotificationSettings() }) {
                Text(stringResource(R.string.action_open_settings), style = uiText(17, Weight.HEAVY), color = ThemeToken.Primary.color)
            }
        }
    }
    state.liveActivityError?.let {
        MessageCard(stringResource(R.string.live_update_missing_title), it, MessageStyle.Warning, Icons.Filled.Warning, Modifier.padding(top = 12.dp))
    }
}

/** Systemets inställning för exakta tider för appen. */
private fun Context.openExactAlarmSettings() {
    val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:$packageName".toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(intent) }
}

/** Välj huvudadress, i hemskärmens ordning som på iOS. */
@Composable
fun PrimaryAddressScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(dependencies) }
    val state by vm.state.collectAsStateWithLifecycle()
    ScreenScaffold(title = stringResource(R.string.settings_primary), onBack = { navigator.back() }, large = true) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(vertical = 16.dp)) {
            state.lastStorageError?.let { error ->
                MessageCard(
                    title = stringResource(R.string.error_title),
                    text = stringResource(R.string.error_tap_to_close, error),
                    style = MessageStyle.Warning,
                    icon = Icons.Filled.Warning,
                    modifier = Modifier.padding(bottom = 12.dp).clickable(role = Role.Button, onClick = vm::clearStorageError),
                )
            }
            SectionCard {
                state.addresses.forEachIndexed { index, address ->
                    if (index > 0) SectionDivider()
                    ChoiceRow(address.displayName, selected = address.isPrimary) { vm.setPrimary(address.key) }
                }
            }
        }
    }
}
