package se.hardyson.sophamtning.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Rubriken över en del i Inställningar, som "Notiser" och "Om appen". */
@Composable
internal fun SettingsHeading(title: String) {
    Text(
        title,
        style = uiText(24, Weight.HEAVY),
        color = ThemeToken.Text.color,
        modifier = Modifier.padding(top = 28.dp, bottom = 14.dp).semantics { heading() },
    )
}

/** Texten under ett kort. */
@Composable
internal fun SettingsFootnote(text: String) {
    Text(
        text,
        style = uiText(15, Weight.SEMIBOLD),
        color = ThemeToken.Text2.color,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp),
    )
}

/**
 * En rad i en inställningslista: rubrik, värde och pil, som SettingsRow i SettingsView.swift. Med största text står värdet
 * under rubriken. TalkBack läser raden som en knapp med rubrik och värde. Utan [onClick] är raden bara text, utan pil.
 */
@Composable
internal fun SettingsRow(title: String, value: String, onClick: (() -> Unit)?) {
    val large = isLargeText()
    val clickable = if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(clickable)
            .semantics(mergeDescendants = true) {}
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val titleText: @Composable (Modifier) -> Unit = { modifier ->
            Text(title, style = uiText(20, Weight.HEAVY), color = ThemeToken.Text.color, maxLines = 2, modifier = modifier)
        }
        val valueText: @Composable () -> Unit = {
            if (value.isNotEmpty()) Text(value, style = uiText(19, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        if (large) {
            Column(Modifier.weight(1f).padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                titleText(Modifier)
                valueText()
            }
        } else {
            titleText(Modifier.weight(1f))
            valueText()
        }
        if (onClick != null) Chevron()
    }
}

/** Ett reglage i en lista, med ikon före rubriken. Avstängt reglage går inte att ändra. */
@Composable
internal fun SettingsToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, icon: ImageVector? = null, enabled: Boolean = true) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = ThemeToken.Primary.color, modifier = Modifier.size(24.dp))
        Text(title, style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = ThemeToken.Primary.color, checkedThumbColor = ThemeToken.OnPrimary.color),
        )
    }
}

/** Ett val i en lista med bock, som huvudadressen. */
@Composable
internal fun ChoiceRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = uiText(20, if (selected) Weight.HEAVY else Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = ThemeToken.Primary.color)
    }
}
