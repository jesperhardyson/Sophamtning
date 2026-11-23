package se.hardyson.sophamtning.ui.address

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
        title = { Text("Ta bort adressen?") },
        text = { Text("Adressen, det sparade schemat och dess påminnelser tas bort från telefonen.") },
        confirmButton = { TextButton(onClick = onRemove) { Text("Ta bort", color = ThemeToken.Warn.color, style = uiText(16, Weight.HEAVY)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Avbryt", style = uiText(16, Weight.HEAVY)) } },
        containerColor = ThemeToken.Surface.color,
    )
}
