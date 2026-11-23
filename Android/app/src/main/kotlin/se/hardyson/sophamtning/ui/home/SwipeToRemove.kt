package se.hardyson.sophamtning.ui.home

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.ui.address.RemoveAddressDialog
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * En adress på hemskärmen som går att svepa bort åt vänster, med en bekräftelse, som svepet på iOS. Avbryts bekräftelsen
 * glider kortet tillbaka. TalkBack når borttagningen med åtgärden Ta bort i adressens snabbmeny ([AddressMenu]).
 */
@Composable
fun SwipeToRemove(onRemove: () -> Unit, cornerRadius: Dp, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    var confirming by rememberSaveable { mutableStateOf(false) }
    SwipeToDismissBox(
        state = state,
        modifier = modifier,
        enableDismissFromStartToEnd = false,
        onDismiss = { confirming = true },
        backgroundContent = {
            // Bara bakgrund under svepet. TalkBack har åtgärden Ta bort.
            Row(
                Modifier.fillMaxSize().clearAndSetSemantics {}.background(ThemeToken.Warn.color, RoundedCornerShape(cornerRadius)).padding(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(AppSymbols.Delete, contentDescription = null, tint = ThemeToken.WarnBg.color)
                Text(stringResource(R.string.action_remove), style = uiText(16, Weight.HEAVY), color = ThemeToken.WarnBg.color)
            }
        },
    ) { content() }
    if (confirming) {
        RemoveAddressDialog(
            onRemove = {
                confirming = false
                onRemove()
                scope.launch { state.snapTo(SwipeToDismissBoxValue.Settled) }
            },
            onDismiss = {
                confirming = false
                scope.launch { state.reset() }
            },
        )
    }
}
