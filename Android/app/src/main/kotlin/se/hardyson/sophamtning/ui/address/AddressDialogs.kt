package se.hardyson.sophamtning.ui.address

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

// Bekräftelsen för en adress, samma i adressvyn och på hemskärmen, som i AddressQuickActions.swift.

/** Bekräftelsen före borttagning. */
@Composable
fun RemoveAddressDialog(onRemove: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.remove_title)) },
        text = { Text(stringResource(R.string.remove_text)) },
        confirmButton = { TextButton(onClick = onRemove) { Text(stringResource(R.string.action_remove), color = ThemeToken.Warn.color, style = uiText(16, Weight.HEAVY)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel), style = uiText(16, Weight.HEAVY)) } },
        containerColor = ThemeToken.Surface.color,
    )
}
