package se.hardyson.sophamtning.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.BorderStroke
import se.hardyson.sophamtning.core.placedout.PlacedOutLine
import se.hardyson.sophamtning.core.placedout.PlacedOutTexts
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Raden för Ställ ut kärlen och Utställt, som HouseholdPlaceOutRow.swift för en adress som inte delas: knappen **Ställ ut
 * kärlen**, eller **Utställt** med **av dig · kl. 19:42** och **Ångra**. På huvudkortet står raden direkt på den gröna ytan.
 */
@Composable
fun PlacedOutRow(line: PlacedOutLine, onCard: Boolean, onPlaceOut: () -> Unit, onUndo: () -> Unit, modifier: Modifier = Modifier) {
    val foreground = if (onCard) ThemeToken.OnPrimary.color else ThemeToken.Text.color
    val text = line.placedOutText
    if (text == null) {
        if (!line.showsButton) return
        if (onCard) {
            // En ljus knapp på det gröna kortet, så att den syns som en knapp och inte som text.
            Button(
                onClick = onPlaceOut,
                modifier = modifier.fillMaxWidth().heightIn(min = 48.dp),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = ThemeToken.Surface.color, contentColor = ThemeToken.BrandText.color),
            ) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null, modifier = Modifier.size(20.dp))
                Text(PlacedOutTexts.PLACE_OUT, style = uiText(17, Weight.HEAVY), modifier = Modifier.padding(start = 8.dp))
            }
        } else {
            PrimaryButton(PlacedOutTexts.PLACE_OUT, onPlaceOut, modifier)
        }
        return
    }
    val mark: @Composable () -> Unit = {
        Row(
            Modifier.clearAndSetSemantics {
                contentDescription = listOfNotNull(line.placedOutTitle, line.placedOutSubtitle).joinToString(", ")
                customActions = listOf(CustomAccessibilityAction(PlacedOutTexts.UNDO) { onUndo(); true })
            },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = if (onCard) ThemeToken.OnPrimary.color else ThemeToken.Primary.color,
                modifier = Modifier.size(28.dp),
            )
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(line.placedOutTitle, style = uiText(17, Weight.HEAVY), color = foreground)
                line.placedOutSubtitle?.let {
                    Text(it, style = uiText(15, Weight.SEMIBOLD), color = if (onCard) foreground.copy(alpha = 0.85f) else ThemeToken.Text2.color)
                }
            }
        }
    }
    val undo: @Composable (Modifier) -> Unit = { m ->
        val tint = if (onCard) ThemeToken.OnPrimary.color else ThemeToken.Primary.color
        OutlinedButton(
            onClick = onUndo,
            modifier = m.heightIn(min = 48.dp),
            shape = CircleShape,
            border = BorderStroke(1.dp, tint.copy(alpha = 0.6f)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = tint, containerColor = Color.Transparent),
        ) {
            Text(PlacedOutTexts.UNDO, style = uiText(15, Weight.HEAVY))
        }
    }
    if (isLargeText()) {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            mark()
            undo(Modifier.fillMaxWidth())
        }
    } else {
        Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            mark()
            undo(Modifier)
        }
    }
}
