package se.hardyson.sophamtning.ui.address

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import se.hardyson.sophamtning.core.storage.AddressList
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

// Dialogerna för en adress, samma i adressvyn och på hemskärmen, som i AddressQuickActions.swift.

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

/** Dialogen för att byta namn. Spara går bara att trycka på med ett giltigt namn. */
@Composable
fun RenameAddressDialog(current: String, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Byt namn") },
        text = {
            Column {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Namn") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Text("Namnet får vara högst ${AddressList.MAX_NAME_LENGTH} tecken.", style = uiText(14, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(name) }, enabled = AddressList.validName(name) != null) { Text("Spara", style = uiText(16, Weight.HEAVY)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Avbryt", style = uiText(16, Weight.HEAVY)) } },
        containerColor = ThemeToken.Surface.color,
    )
}
