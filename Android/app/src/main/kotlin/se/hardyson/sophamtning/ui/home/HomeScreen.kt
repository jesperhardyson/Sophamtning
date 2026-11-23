package se.hardyson.sophamtning.ui.home

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.KommunCheck
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.start.StartContent
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** Hemskärmen: startvyn utan adresser, annars huvudkortet och övriga adresser, som HomeView.swift. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: HomeViewModel = viewModel { HomeViewModel(dependencies) }
    val ui by vm.ui.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

    // Hämtar när appen kommer i förgrunden och när man kommer tillbaka till hemskärmen.
    LifecycleResumeEffect(Unit) {
        vm.onShown()
        onPauseOrDispose {}
    }
    // Räknar om dagen vid varje minutbyte medan skärmen syns, till exempel vid midnatt.
    LaunchedEffect(Unit) {
        while (true) {
            val now = dependencies.clock()
            delay(60_000L - now.toEpochMilli() % 60_000L)
            vm.tick()
        }
    }

    val content = ui.content
    val primary = content.primary
    val filled = primary != null && ui.state.storageProblem == null
    ScreenScaffold(
        title = if (filled) "Sophämtning" else "",
        onBack = null,
        large = filled,
        actions = {
            if (filled) {
                IconButton(onClick = { navigator.open(AddAddress()) }) { Icon(Icons.Filled.Add, contentDescription = "Lägg till") }
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    vm.refresh()
                    refreshing = false
                }
            },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 24.dp)) {
                if (primary != null) {
                    PrimaryCard(primary, onOpen = { navigator.open(Address(primary.key)) })
                    if (content.others.isNotEmpty()) {
                        OthersTitle()
                        for (entry in content.others) {
                            AddressRow(entry, onOpen = { navigator.open(Address(entry.key)) }, modifier = Modifier.padding(bottom = 12.dp))
                        }
                    }
                } else {
                    StartContent(onSearch = { navigator.open(AddAddress()) }, onKommun = { navigator.open(KommunCheck) })
                }
                Text(
                    "Inofficiell app, inte kopplad till någon kommun. Vid avvikelser gäller kommunens information.",
                    style = uiText(15, Weight.SEMIBOLD),
                    color = ThemeToken.Text2.color,
                    modifier = Modifier.padding(top = 32.dp),
                )
            }
        }
    }
}
