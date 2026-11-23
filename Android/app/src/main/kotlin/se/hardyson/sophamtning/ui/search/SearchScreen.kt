package se.hardyson.sophamtning.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.createSavedStateHandle
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.kommun.kommunDisplayName
import se.hardyson.sophamtning.core.kommun.localityAndKommun
import se.hardyson.sophamtning.core.search.AreaLookup
import se.hardyson.sophamtning.core.search.SearchState
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.navigation.KommunCheck
import se.hardyson.sophamtning.ui.components.AddressPlaceLine
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.components.FlowSearchField
import se.hardyson.sophamtning.ui.components.IconPlateRow
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SearchingRow
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** "Lägg till adress", som SearchView.swift på iOS. */
@Composable
fun SearchScreen(key: AddAddress, navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SearchViewModel = viewModel { SearchViewModel(dependencies, createSavedStateHandle(), key.source) }
    val query by vm.query.collectAsStateWithLifecycle()
    val ui by vm.ui.collectAsStateWithLifecycle()

    ScreenScaffold(title = "Lägg till adress", onBack = { navigator.back() }) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(padding)
                .padding(horizontal = PageMargin)
                .padding(bottom = 24.dp),
        ) {
            FlowSearchField(query, vm::setQuery, placeholder = "Gata och husnummer", modifier = Modifier.padding(top = 8.dp))
            Column(Modifier.padding(top = 20.dp).alpha(if (ui.updating) 0.4f else 1f)) {
                SearchContent(
                    ui = ui,
                    enabled = !ui.updating,
                    onRetry = vm::retry,
                    onKommun = { navigator.open(KommunCheck) },
                    onAreas = { title, place, hits, sources -> navigator.open(AreaPicker(title, place, hits, sources)) },
                    onChoose = { hit ->
                        if (hit.isArea) {
                            navigator.open(AreaConfirm(hit))
                        } else {
                            vm.save(hit)?.let(navigator::saved)
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun SearchContent(
    ui: SearchViewModel.Ui,
    enabled: Boolean,
    onRetry: () -> Unit,
    onKommun: () -> Unit,
    onAreas: (String, String?, List<SearchHit>, List<AreaSource>) -> Unit,
    onChoose: (SearchHit) -> Unit,
) {
    val failedNames = { failed: List<String> -> failed.joinToString(", ") { sourceName(it, ui.sources) } }
    when (val state = ui.outcome.state) {
        SearchState.Idle -> Guidance(onKommun)
        SearchState.Searching -> SearchingRow("Söker …", Modifier.fillMaxWidth().padding(top = 32.dp))
        is SearchState.Results -> Results(ui, state, enabled, failedNames(state.failed), onAreas, onChoose)
        is SearchState.SourcesFailed -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            MessageCard(
                title = "Kunde inte söka hos alla källor",
                text = "Försök igen. Det betyder inte att adressen saknas.",
                style = MessageStyle.Warning,
                icon = Icons.Filled.Warning,
            )
            PrimaryButton("Försök igen", onRetry)
        }
        is SearchState.NoHits -> NoHits(ui, onRetry, onKommun, onAreas)
        is SearchState.Failed -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (state.error == ApiError.BadRequest) {
                // 400 är inget nätfel, och samma anrop upprepas inte.
                MessageCard(
                    title = "Sökningen gick inte att tolka",
                    text = "Kontrollera texten och försök med gata och husnummer.",
                    style = MessageStyle.Neutral,
                    icon = Icons.Outlined.Info,
                )
            } else {
                MessageCard(
                    title = "Kunde inte söka just nu",
                    text = "Källan svarar inte. Det betyder inte att adressen saknas.",
                    style = MessageStyle.Warning,
                    icon = AppSymbols.ErrorOutline,
                )
                PrimaryButton("Försök igen", onRetry)
            }
        }
    }
}

@Composable
private fun Guidance(onKommun: () -> Unit) {
    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Skriv gata och husnummer, gärna med ort.", style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        KommunLink(onKommun)
    }
}

/** "Finns min kommuns hämtningsschema?" som länk till kommunfrågan. */
@Composable
fun KommunLink(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Place, contentDescription = null, tint = ThemeToken.Primary.color, modifier = Modifier.size(22.dp))
        Text("Finns min kommuns hämtningsschema?", style = uiText(18, Weight.HEAVY), color = ThemeToken.Primary.color)
    }
}

@Composable
private fun Results(
    ui: SearchViewModel.Ui,
    state: SearchState.Results,
    enabled: Boolean,
    failedNames: String,
    onAreas: (String, String?, List<SearchHit>, List<AreaSource>) -> Unit,
    onChoose: (SearchHit) -> Unit,
) {
    Column {
        if (state.failed.isNotEmpty()) {
            MessageCard(
                title = "Alla källor svarade inte",
                text = "$failedNames svarade inte just nu. Saknas din adress kan du försöka igen om en stund.",
                style = MessageStyle.Warning,
                icon = Icons.Filled.Warning,
                modifier = Modifier.padding(bottom = 20.dp),
            )
        }
        if (ui.saveFailed) {
            MessageCard(title = "Något gick fel", text = SAVE_FAILED_MESSAGE, style = MessageStyle.Warning, icon = Icons.Filled.Warning, modifier = Modifier.padding(bottom = 20.dp))
        }
        val areas = ui.outcome.areas
        if (areas is AreaLookup.Found && areas.areas.isNotEmpty()) {
            AreaRow(areas.place, areas.areas, areas.sources, onAreas, Modifier.padding(bottom = 20.dp))
        }
        val rows = AreaLookup.visibleHits(state.hits, areas)
        if (rows.isNotEmpty()) {
            Text(
                if (rows.size == 1) "1 träff" else "${rows.size} träffar",
                style = uiText(17, Weight.HEAVY),
                color = ThemeToken.Text2.color,
                modifier = Modifier.padding(bottom = 12.dp),
            )
            SectionCard {
                rows.forEachIndexed { position, row ->
                    if (position > 0) SectionDivider()
                    HitRow(row.value, enabled) { onChoose(row.value) }
                }
            }
        }
    }
}

/** "Välj område i X", i en egen ruta, så att man ser att adresserna under är något annat. */
@Composable
private fun AreaRow(place: String, areas: List<SearchHit>, sources: List<AreaSource>, onAreas: (String, String?, List<SearchHit>, List<AreaSource>) -> Unit, modifier: Modifier = Modifier) {
    SectionCard(modifier) {
        IconPlateRow(
            icon = AppSymbols.Map,
            title = "Välj område i ${kommunDisplayName(areas[0].kommun)}",
            subtitle = "Här finns schemat per område, inte per adress.",
            onClick = { onAreas(areas[0].kommun, place, areas, sources) },
        )
    }
}

@Composable
private fun HitRow(hit: SearchHit, enabled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            AddressPlaceLine(
                HomeContent.AddressLines(address = hit.street, place = localityAndKommun(hit.locality, hit.kommun)),
                color = ThemeToken.Text.color,
                weight = Weight.HEAVY,
            )
            hit.detail?.let { Text(it, style = uiText(16, Weight.HEAVY), color = ThemeToken.Earth.color) }
        }
        Chevron()
    }
}

@Composable
private fun NoHits(ui: SearchViewModel.Ui, onRetry: () -> Unit, onKommun: () -> Unit, onAreas: (String, String?, List<SearchHit>, List<AreaSource>) -> Unit) {
    val found = (ui.outcome.areas as? AreaLookup.Found)?.takeIf { it.areas.isNotEmpty() }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(AppSymbols.LocationCity, contentDescription = null, tint = ThemeToken.Text2.color, modifier = Modifier.padding(top = 12.dp).size(44.dp))
        Text(
            "Adressen hittades inte",
            style = uiText(24, Weight.HEAVY),
            color = ThemeToken.Text.color,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 16.dp).semantics { heading() },
        )
        when {
            found != null -> {
                Text(
                    "${sourceName(found.areas[0].source, ui.sources)} publicerar inte alla adresser. Där väljer du i stället ditt tömningsområde.",
                    style = uiText(18, Weight.SEMIBOLD),
                    color = ThemeToken.Text2.color,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 10.dp),
                )
                AreaRow(found.place, found.areas, found.sources, onAreas, Modifier.padding(top = 24.dp))
            }
            ui.outcome.areas == AreaLookup.Failed -> {
                MessageCard(
                    title = "Kunde inte hämta områden",
                    text = "Försök igen. Det betyder inte att kommunen saknar områdesval.",
                    style = MessageStyle.Warning,
                    icon = Icons.Filled.Warning,
                    modifier = Modifier.padding(top = 10.dp),
                )
                PrimaryButton("Försök igen", onRetry, Modifier.padding(top = 12.dp))
            }
            else -> Text(
                "Kontrollera stavningen och skriv gata, husnummer och gärna ort. Alla adresser finns inte hos alla källor.",
                style = uiText(18, Weight.SEMIBOLD),
                color = ThemeToken.Text2.color,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 10.dp),
            )
        }
        Text(
            "Skriv gata och husnummer, gärna med ort.",
            style = uiText(16, Weight.SEMIBOLD),
            color = ThemeToken.Text2.color,
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
        )
        KommunLink(onKommun, Modifier.fillMaxWidth().padding(top = 16.dp))
    }
}
