package se.hardyson.sophamtning.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.about.Changelog
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Nyheter, från raden Version i Inställningar, som ChangelogSheet.swift. Innehållet kommer från `Android/CHANGELOG.md`,
 * som följer med appen. Innan Android har släppts finns ingen fil, och sidan visar en vänlig tom text.
 */
@Composable
fun ChangelogScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val versions = remember { dependencies.changelog()?.let(Changelog::parse) ?: emptyList() }
    ScreenScaffold(title = stringResource(R.string.changelog_title), onBack = { navigator.back() }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 32.dp)) {
            if (versions.isEmpty()) {
                MessageCard(
                    stringResource(R.string.changelog_empty_title),
                    stringResource(R.string.changelog_empty_text),
                    MessageStyle.Neutral,
                    Icons.Filled.Info,
                    Modifier.padding(top = 16.dp),
                )
            }
            for (version in versions) VersionView(version)
        }
    }
}

@Composable
private fun VersionView(version: Changelog.Version) {
    Text(
        version.title,
        style = uiText(24, Weight.HEAVY),
        color = ThemeToken.Text.color,
        modifier = Modifier.padding(top = 28.dp, bottom = 14.dp).semantics { heading() },
    )
    SectionCard {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            for (section in version.sections) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(section.title, style = uiText(16, Weight.HEAVY), color = ThemeToken.Text2.color, modifier = Modifier.semantics { heading() })
                    for (item in section.items) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text("•", style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.clearAndSetSemantics {})
                            Text(item, style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}
