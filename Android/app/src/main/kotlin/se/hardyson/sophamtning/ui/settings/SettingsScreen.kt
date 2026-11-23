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
import androidx.compose.runtime.getValue
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
import se.hardyson.sophamtning.core.app.NotificationAuthorization
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.reminders.ReminderSettingsTexts
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
            if (state.remindersAvailable) Reminders(state, vm, missedReminder = state.primary?.let { state.missedReminderText(it, dependencies.clock()) })
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
 * Notiser, Meddelanden från källan och Live Update, var och en i ett eget kort med en rad under om vad den gäller. Sidorna
 * för tiderna byggs med påminnelserna i plan 5, så raden Tid visar bara värdet tills dess.
 */
@Composable
private fun Reminders(state: AppState, vm: SettingsViewModel, missedReminder: String?) {
    val authorized = state.notificationAuthorization == NotificationAuthorization.Authorized
    SettingsHeading(stringResource(R.string.settings_notifications))
    SectionCard { SettingsRow(stringResource(R.string.settings_time), state.settings.settingsValue, onClick = null) }
    SettingsFootnote(
        ReminderSettingsTexts.notificationsFooter(ReminderSettingsTexts.homeOrder(state.addresses).filter(state::remindersOn).map { it.displayName }),
    )
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
        SettingsToggleRow(stringResource(R.string.live_update), checked = state.settings.liveActivityOn, onChange = vm::setLiveActivity)
    }
    SettingsFootnote(AddressDetail.liveActivityText(state.settings))
    state.primary?.let { SettingsFootnote(ReminderSettingsTexts.liveActivityFooter(it.displayName)) }
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
