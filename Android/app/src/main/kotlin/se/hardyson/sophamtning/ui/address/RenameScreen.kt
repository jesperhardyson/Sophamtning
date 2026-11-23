package se.hardyson.sophamtning.ui.address

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.AddressList
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * "Byt namn", som en helskärmsdialog med fältet och **Spara** i appfältet. På iOS är det en dialog. Ett textfält i en egen
 * dialog blir aldrig stilla i UI-testerna, och Material anvisar helskärm för inmatning. Spara går bara att trycka på med ett
 * giltigt namn, högst 60 tecken.
 */
@Composable
fun RenameScreen(key: AddressKey, navigator: AppNavigator) {
    val model = LocalAppDependencies.current.model
    val current = remember(key) { model.state.value.address(key)?.displayName.orEmpty() }
    var name by rememberSaveable { mutableStateOf(current) }
    val valid = AddressList.validName(name) != null
    val save = {
        model.clearStorageError()
        model.rename(key, name)
        navigator.back()
    }
    val requester = remember { FocusRequester() }
    ScreenScaffold(
        title = "Byt namn",
        onBack = { navigator.back() },
        actions = { TextButton(onClick = save, enabled = valid) { Text("Spara", style = uiText(16, Weight.HEAVY)) } },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = PageMargin, vertical = 16.dp)) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Namn") },
                singleLine = true,
                textStyle = uiText(18, Weight.SEMIBOLD).copy(color = ThemeToken.Text.color),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (valid) save() }),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = ThemeToken.Surface.color,
                    unfocusedContainerColor = ThemeToken.Surface.color,
                    focusedBorderColor = ThemeToken.Primary.color,
                    cursorColor = ThemeToken.Primary.color,
                ),
                modifier = Modifier.fillMaxWidth().focusRequester(requester),
            )
            Text(
                "Namnet får vara högst ${AddressList.MAX_NAME_LENGTH} tecken.",
                style = uiText(14, Weight.SEMIBOLD),
                color = ThemeToken.Text2.color,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
    LaunchedEffect(Unit) { runCatching { requester.requestFocus() } }
}
