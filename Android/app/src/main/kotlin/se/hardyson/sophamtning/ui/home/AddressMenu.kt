package se.hardyson.sophamtning.ui.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.home.AddressAction
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.ui.address.RemoveAddressDialog
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.color

/** Det snabbmenyn behöver veta om adressen och vad valen gör. Allt går via `AppModel`, med samma regler som i adressvyn. */
class AddressMenuChoices(
    val isPrimary: Boolean,
    /** Påminn mig och Live Update visas bara när påminnelserna finns. */
    val remindersAvailable: Boolean,
    val remindersOn: Boolean,
    val liveUpdateOn: Boolean,
    val onRename: () -> Unit,
    val onMakePrimary: () -> Unit,
    /** Slår på eller av påminnelsen. Den andra parametern körs när systemet nekar notiser. */
    val onNotifications: (Boolean, () -> Unit) -> Unit,
    val onLiveUpdate: (Boolean) -> Unit,
    val onRemove: () -> Unit,
) {
    /** Valen i ordning, samma som i adressvyn. Live Update gäller bara huvudadressen. */
    val choices: List<AddressAction> = AddressAction.choices(isPrimary).filter {
        remindersAvailable || (it != AddressAction.Notifications && it != AddressAction.LiveActivity)
    }
}

/**
 * Snabbmenyn för en adress på hemskärmen, som AddressQuickActions.swift utan hushållet: ett långt tryck på huvudkortet
 * eller en rad under Fler adresser öppnar menyn, med samma val som menyn i adressvyn, plus påminnelserna. Ta bort frågar
 * först, med samma bekräftelse som svepet och adressvyn. TalkBack får samma val som anpassade åtgärder.
 *
 * [content] får det som öppnar menyn och åtgärderna för TalkBack, och lägger dem på sitt eget element.
 */
@Composable
fun AddressMenu(
    choices: AddressMenuChoices,
    modifier: Modifier = Modifier,
    content: @Composable (onLongPress: () -> Unit, actions: List<CustomAccessibilityAction>) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    var confirmingRemoval by rememberSaveable { mutableStateOf(false) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current

    val rename = stringResource(R.string.action_rename)
    val makePrimary = stringResource(R.string.action_make_primary)
    val remove = stringResource(R.string.action_remove)
    val liveUpdate = stringResource(if (choices.liveUpdateOn) R.string.live_update_turn_off else R.string.live_update_turn_on)

    fun perform(choice: AddressAction) {
        open = false
        when (choice) {
            AddressAction.Rename -> choices.onRename()
            AddressAction.MakePrimary -> choices.onMakePrimary()
            AddressAction.Notifications -> choices.onNotifications(!choices.remindersOn) { denied = true }
            AddressAction.LiveActivity -> choices.onLiveUpdate(!choices.liveUpdateOn)
            AddressAction.Remove -> confirmingRemoval = true
        }
    }

    // Reglagen blir åtgärder som säger vad de gör.
    val actions = choices.choices.map { choice ->
        val label = when (choice) {
            AddressAction.Rename -> rename
            AddressAction.MakePrimary -> makePrimary
            AddressAction.Notifications -> HomeContent.reminderActionTitle(choices.remindersOn)
            AddressAction.LiveActivity -> liveUpdate
            AddressAction.Remove -> remove
        }
        CustomAccessibilityAction(label) { perform(choice); true }
    }

    Box(modifier) {
        content({ open = true }, actions)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = ThemeToken.Surface.color) {
            for (choice in choices.choices) {
                when (choice) {
                    AddressAction.Rename -> DropdownMenuItem(
                        text = { Text(rename) },
                        leadingIcon = { Icon(Icons.Filled.Edit, null) },
                        onClick = { perform(choice) },
                    )
                    AddressAction.MakePrimary -> DropdownMenuItem(
                        text = { Text(makePrimary) },
                        leadingIcon = { Icon(Icons.Filled.Home, null) },
                        onClick = { perform(choice) },
                    )
                    AddressAction.Notifications -> DropdownMenuItem(
                        text = { Text(HomeContent.reminderTitle()) },
                        leadingIcon = { Icon(Icons.Filled.Notifications, null) },
                        trailingIcon = { MenuSwitch(choices.remindersOn) },
                        onClick = { perform(choice) },
                        modifier = Modifier.semantics { toggleableState = ToggleableState(choices.remindersOn) },
                    )
                    AddressAction.LiveActivity -> DropdownMenuItem(
                        text = {
                            Column {
                                Text(stringResource(R.string.live_update))
                                Text(stringResource(R.string.live_update_menu_text), color = ThemeToken.Text2.color)
                            }
                        },
                        leadingIcon = { Icon(AppSymbols.NotificationsActive, null) },
                        trailingIcon = { MenuSwitch(choices.liveUpdateOn) },
                        onClick = { perform(choice) },
                        modifier = Modifier.semantics { toggleableState = ToggleableState(choices.liveUpdateOn) },
                    )
                    AddressAction.Remove -> DropdownMenuItem(
                        text = { Text(remove, color = ThemeToken.Warn.color) },
                        leadingIcon = { Icon(Icons.Filled.Delete, null, tint = ThemeToken.Warn.color) },
                        onClick = { perform(choice) },
                    )
                }
            }
        }
    }
    if (confirmingRemoval) {
        RemoveAddressDialog(
            onRemove = {
                confirmingRemoval = false
                choices.onRemove()
            },
            onDismiss = { confirmingRemoval = false },
        )
    }
    // Menyn stängs när ett val görs, så nekade notiser visas här i stället.
    if (denied) {
        AlertDialog(
            onDismissRequest = { denied = false },
            title = { Text(stringResource(R.string.notifications_denied_title)) },
            text = { Text(stringResource(R.string.notifications_denied_text)) },
            confirmButton = {
                TextButton(onClick = {
                    denied = false
                    context.openNotificationSettings()
                }) { Text(stringResource(R.string.action_open_settings)) }
            },
            dismissButton = { TextButton(onClick = { denied = false }) { Text(stringResource(R.string.action_ok)) } },
            containerColor = ThemeToken.Surface.color,
        )
    }
}

/** Reglagets läge i menyn. Hela raden är valet och har läget, så reglaget läses inte för sig. */
@Composable
private fun MenuSwitch(checked: Boolean) {
    Switch(
        checked = checked,
        onCheckedChange = null,
        modifier = Modifier.clearAndSetSemantics {},
        colors = SwitchDefaults.colors(checkedTrackColor = ThemeToken.Primary.color, checkedThumbColor = ThemeToken.OnPrimary.color),
    )
}
