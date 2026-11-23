package se.hardyson.sophamtning.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.app.AppState
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.reminders.ReminderSettingsTexts
import se.hardyson.sophamtning.core.reminders.liveActivityTimesFooter
import se.hardyson.sophamtning.core.reminders.sectionFooter
import se.hardyson.sophamtning.core.reminders.timesFooter
import se.hardyson.sophamtning.core.reminders.title
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.ReminderTimeChoice
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

// Sidorna för notisernas och Live Updatens tider, som ReminderTimeView, ReminderTimesView och LiveActivityTimingView i
// SettingsView.swift. Tiderna är listor med kvartarna i ReminderTiming.times, och ingen urtavla.

/** Sidans innehåll med felet överst, som går att stänga med ett tryck. */
@Composable
private fun ReminderPage(title: String, onBack: () -> Unit, state: AppState, onClearError: () -> Unit, content: @Composable () -> Unit) {
    ScreenScaffold(title = title, onBack = onBack, large = true) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            state.lastStorageError?.let { error ->
                MessageCard(
                    title = stringResource(R.string.error_title),
                    text = stringResource(R.string.error_tap_to_close, error),
                    style = MessageStyle.Warning,
                    icon = Icons.Filled.Warning,
                    modifier = Modifier.clickable(role = Role.Button, onClick = onClearError),
                )
            }
            content()
        }
    }
}

@Composable
private fun PageFootnote(text: String) {
    Text(text, style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
}

@Composable
private fun PageHeading(text: String) {
    SettingsHeading(text)
}

/**
 * Notiserna: ett reglage per adress, i hemskärmens ordning, och kvällen före och samma morgon, var och en med ett eget
 * reglage och en egen tid. Minst ett val är alltid på, så det enda påslagna reglaget går inte att stänga av.
 */
@Composable
fun ReminderTimesScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(dependencies) }
    val state by vm.state.collectAsStateWithLifecycle()
    ReminderPage(stringResource(R.string.settings_notifications), { navigator.back() }, state, vm::clearStorageError) {
        // Adresserna överst, så att notiserna också går att stänga av helt här.
        if (state.addresses.isNotEmpty()) {
            PageHeading(stringResource(R.string.settings_addresses))
            SectionCard {
                ReminderSettingsTexts.homeOrder(state.addresses).forEachIndexed { index, address ->
                    if (index > 0) SectionDivider()
                    SettingsToggleRow(address.displayName, checked = state.remindersOn(address), onChange = { vm.setNotifications(address.key, it) })
                }
            }
            PageFootnote(ReminderSettingsTexts.ADDRESSES_FOOTER)
        }
        for (timing in ReminderTiming.entries) {
            val settings = state.settings
            val on = timing in settings.enabledTimings
            val minutes = settings.minutes(timing)
            PageHeading(timing.title)
            SectionCard {
                SettingsToggleRow(
                    stringResource(R.string.settings_remind_me),
                    checked = on,
                    onChange = { vm.setReminder(timing, it) },
                    enabled = !(on && settings.enabledTimings.size == 1),
                )
                SectionDivider()
                // Tiden går att ställa in även när valet är av, så att den är rätt när valet slås på.
                SettingsRow(stringResource(R.string.settings_time), SwedishFormat.clock(minutes)) {
                    navigator.open(ReminderTimeChoice(timing, liveUpdate = false))
                }
            }
            PageFootnote(timing.sectionFooter(minutes))
        }
    }
}

/** Klockslagen för ett val i steg om 15 minuter, för notisen eller för Live Updatens egen tid. */
@Composable
fun ReminderTimeChoiceScreen(timing: ReminderTiming, liveUpdate: Boolean, navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(dependencies) }
    val state by vm.state.collectAsStateWithLifecycle()
    val selected = if (liveUpdate) state.settings.liveActivityStartMinutes else state.settings.minutes(timing)
    val footer = if (liveUpdate) "${timing.timesFooter} ${ReminderTiming.liveActivityTimesFooter}" else timing.timesFooter
    ReminderPage(stringResource(R.string.settings_time), { navigator.back() }, state, vm::clearStorageError) {
        SectionCard {
            timing.times.forEachIndexed { index, minutes ->
                if (index > 0) SectionDivider()
                ChoiceRow(SwedishFormat.clock(minutes), selected = minutes == selected) {
                    if (liveUpdate) vm.setLiveActivityMinutes(minutes) else vm.setReminderMinutes(minutes, timing)
                }
            }
        }
        PageFootnote(footer)
    }
}

/** När Live Update visas: kvällen före eller samma morgon, och en egen tid. Båda är skilda från notisernas. */
@Composable
fun LiveUpdateTimingScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(dependencies) }
    val state by vm.state.collectAsStateWithLifecycle()
    ReminderPage(stringResource(R.string.settings_live_update_from), { navigator.back() }, state, vm::clearStorageError) {
        SectionCard {
            ReminderTiming.entries.forEachIndexed { index, timing ->
                if (index > 0) SectionDivider()
                ChoiceRow(timing.title, selected = timing == state.settings.liveActivityTiming) { vm.setLiveActivityTiming(timing) }
            }
        }
        SectionCard {
            SettingsRow(stringResource(R.string.settings_time), SwedishFormat.clock(state.settings.liveActivityStartMinutes)) {
                navigator.open(ReminderTimeChoice(state.settings.liveActivityTiming, liveUpdate = true))
            }
        }
        PageFootnote(AddressDetail.liveActivityText(state.settings))
    }
}
