package se.hardyson.sophamtning.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.api.kommunerText
import se.hardyson.sophamtning.core.kommun.SourceLink
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.ui.address.SourceLinkRow
import se.hardyson.sophamtning.ui.components.AppSymbols
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

/**
 * Källorna från `/kallor`: namnet, kommunerna källan täcker och länkarna till webbplatsen och kontakten, som SourcesView
 * i SettingsView.swift. Testdata visas inte. Sist står Wikidata för ortlistan.
 */
@Composable
fun DataSourcesScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: SourcesViewModel = viewModel { SourcesViewModel(dependencies) }
    val ui by vm.ui.collectAsStateWithLifecycle()
    ScreenScaffold(title = stringResource(R.string.settings_sources), onBack = { navigator.back() }, large = true) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val shown = ui.shown
            when {
                shown != null -> {
                    Text(stringResource(R.string.sources_count, shown.size), style = uiText(16, Weight.SEMIBOLD), color = ThemeToken.Text2.color, modifier = Modifier.padding(horizontal = 20.dp))
                    SectionCard {
                        shown.forEachIndexed { index, source ->
                            if (index > 0) SectionDivider()
                            SourceRow(source)
                        }
                    }
                    SectionCard {
                        Column(Modifier.semantics(mergeDescendants = true) {}.padding(horizontal = 20.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(stringResource(R.string.sources_wikidata), style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
                            Text(stringResource(R.string.sources_wikidata_text), style = uiText(15, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
                        }
                    }
                }
                // Medan listan hämtas visas ingen felruta.
                ui.loading -> SearchingRow(
                    stringResource(R.string.sources_loading),
                    Modifier.fillMaxWidth().background(ThemeToken.Surface2.color, RoundedCornerShape(16.dp)).padding(14.dp),
                )
                else -> {
                    MessageCard(stringResource(R.string.sources_failed_title), stringResource(R.string.sources_failed_text), MessageStyle.Warning, AppSymbols.ErrorOutline)
                    PrimaryButton(stringResource(R.string.action_retry), vm::load)
                }
            }
        }
    }
}

/** En källa: namnet och kommunerna, och under dem länkarna. Varje länk tar emot sitt eget tryck. */
@Composable
private fun SourceRow(source: Source) {
    Column(Modifier.padding(vertical = 6.dp)) {
        Column(Modifier.semantics(mergeDescendants = true) {}.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(source.name, style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
            Text(source.kommunerText, style = uiText(15, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        // Källans namn i beskrivningen, så att TalkBack säger vilken källa länken hör till.
        for (link in SourceLink.links(source, kommunInfo = null)) SourceLinkRow(link, source = source.name)
    }
}
