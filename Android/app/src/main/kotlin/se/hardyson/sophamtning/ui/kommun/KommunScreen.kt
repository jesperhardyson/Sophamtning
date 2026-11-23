package se.hardyson.sophamtning.ui.kommun

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.kommun.KommunAnswer
import se.hardyson.sophamtning.core.kommun.KommunRow
import se.hardyson.sophamtning.core.kommun.kommunDisplayName
import se.hardyson.sophamtning.core.kommun.shortKommunName
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.FlowSearchField
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.isLargeText
import se.hardyson.sophamtning.ui.components.openWeb
import se.hardyson.sophamtning.ui.search.TIP_LINK
import se.hardyson.sophamtning.ui.search.capitalizedFirst
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.brandText
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/** "Finns min kommuns hämtningsschema?", som KommunCheckView.swift. */
@Composable
fun KommunScreen(navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: KommunViewModel = viewModel { KommunViewModel(dependencies, createSavedStateHandle()) }
    val query by vm.query.collectAsStateWithLifecycle()
    val ui by vm.ui.collectAsStateWithLifecycle()
    // Frågan är för lång för appfältet, så den står först i innehållet.
    ScreenScaffold(title = "", onBack = { navigator.back() }) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(horizontal = PageMargin).padding(bottom = 24.dp),
        ) {
            Text("Finns min kommuns hämtningsschema?", style = brandText(34), color = ThemeToken.Text.color, modifier = Modifier.semantics { heading() })
            Text(
                "Skriv din kommun eller ort. Svaret kommer medan du skriver.",
                style = uiText(18, Weight.SEMIBOLD),
                color = ThemeToken.Text2.color,
                modifier = Modifier.padding(top = 14.dp),
            )
            FlowSearchField(query, vm::setQuery, placeholder = "Kommun eller ort", modifier = Modifier.padding(top = 24.dp))
            Column(Modifier.padding(top = 16.dp).alpha(if (ui.updating) 0.4f else 1f)) {
                Answer(ui.result, vm::setQuery, vm::retry, navigator)
            }
        }
    }
}

@Composable
private fun Answer(result: KommunViewModel.Result, setQuery: (String) -> Unit, retry: () -> Unit, navigator: AppNavigator) {
    val context = LocalContext.current
    when (val answer = result.answer) {
        KommunAnswer.Empty -> Text(
            "Till exempel Örebro eller Krylbo.",
            style = uiText(16, Weight.SEMIBOLD),
            color = ThemeToken.Text2.color,
            modifier = Modifier.padding(horizontal = 4.dp),
        )
        is KommunAnswer.Covered -> {
            val row = answer.row
            val hasAreas = result.areas.isNotEmpty()
            AnswerCard(ThemeToken.BrandSoft.color) {
                IconAndText(
                    icon = Icons.Filled.CheckCircle,
                    tint = ThemeToken.BrandText.color,
                    title = answer.viaPlace?.let { "Ja, ${capitalizedFirst(it)} ligger i ${kommunDisplayName(row.name)}" } ?: "Ja, ${kommunDisplayName(row.name)} finns",
                    message = if (hasAreas) "Här väljer du tömningsområde i stället för adress, eftersom källan inte publicerar alla adresser." else null,
                    messageColor = ThemeToken.Text.color,
                )
                if (hasAreas) {
                    PrimaryButton("Välj område i ${kommunDisplayName(row.name)}", {
                        navigator.open(AreaPicker(row.name, shortKommunName(row.name), result.areas, result.areaSources))
                    })
                } else {
                    PrimaryButton("Sök din adress", { navigator.open(AddAddress(source = row.sourceId)) })
                }
            }
        }
        is KommunAnswer.NotYet -> AnswerCard(ThemeToken.Surface2.color) {
            IconAndText(
                icon = Icons.Outlined.Info,
                tint = ThemeToken.Text.color,
                title = "Inte än",
                message = "${kommunDisplayName(answer.row.name)} finns inte med ännu. Sopor lägger till fler kommuner efter hand.",
                messageColor = ThemeToken.Text.color,
            )
            Row(
                Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) { context.openWeb(TIP_LINK) },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(AppSymbols.OpenInNew, contentDescription = null, tint = ThemeToken.BrandText.color, modifier = Modifier.size(20.dp))
                Text("Tipsa om din kommun", style = uiText(16, Weight.HEAVY), color = ThemeToken.BrandText.color)
            }
        }
        is KommunAnswer.Multiple -> AnswerCard(ThemeToken.Surface.color, bordered = true) {
            Text(
                "${capitalizedFirst(answer.place)} finns i flera kommuner",
                style = uiText(20, Weight.HEAVY),
                color = ThemeToken.Text.color,
                modifier = Modifier.semantics { heading() },
            )
            for (row in answer.rows) MultipleRow(row) { source -> navigator.open(AddAddress(source = source)) }
        }
        is KommunAnswer.Suggestions -> AnswerCard(ThemeToken.Surface.color, bordered = true) {
            Text("Menar du?", style = uiText(15, Weight.HEAVY), color = ThemeToken.Text2.color)
            for (name in answer.suggestions) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) { setQuery(name) },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(Icons.Filled.Place, contentDescription = null, tint = ThemeToken.BrandText.color)
                    Text(name, style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
                }
            }
        }
        KommunAnswer.Unknown -> AnswerCard(ThemeToken.Surface2.color, merged = true) {
            IconAndText(
                icon = Icons.Outlined.Search,
                tint = ThemeToken.Text.color,
                title = "Vi hittar ingen sådan plats",
                message = "Kontrollera stavningen, eller skriv kommunens namn.",
                messageColor = ThemeToken.Text.color,
            )
        }
        KommunAnswer.Unavailable -> AnswerCard(ThemeToken.WarnBg.color) {
            IconAndText(
                icon = AppSymbols.ErrorOutline,
                tint = ThemeToken.Warn.color,
                title = "Kunde inte kontrollera just nu",
                message = "Försök igen om en stund. Det betyder inte att kommunen saknas.",
                messageColor = ThemeToken.Text.color,
            )
            PrimaryButton("Försök igen", retry)
        }
    }
}

@Composable
private fun MultipleRow(row: KommunRow, onSearch: (String) -> Unit) {
    val name = kommunDisplayName(row.name)
    val source = row.sourceId
    val content: @Composable () -> Unit = {
        Icon(
            if (source == null) Icons.Outlined.Info else Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = if (source == null) ThemeToken.Text2.color else ThemeToken.BrandText.color,
        )
        Text(name, style = uiText(17, Weight.BOLD), color = ThemeToken.Text.color)
    }
    val action: @Composable () -> Unit = {
        if (source != null) {
            Text(
                "Sök adress",
                style = uiText(16, Weight.HEAVY),
                color = ThemeToken.Primary.color,
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .clickable(role = Role.Button) { onSearch(source) }
                    .semantics { contentDescription = "Sök adress i $name" }
                    .padding(vertical = 12.dp),
            )
        } else {
            Text("Inte än", style = uiText(16, Weight.BOLD), color = ThemeToken.Text2.color)
        }
    }
    if (isLargeText()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) { content() }
            action()
        }
    } else {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            content()
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.End) { action() }
        }
    }
}

@Composable
private fun AnswerCard(background: Color, bordered: Boolean = false, merged: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    var modifier = Modifier.fillMaxWidth().background(background, shape)
    if (bordered) modifier = modifier.border(1.dp, ThemeToken.Border.color, shape)
    if (merged) modifier = modifier.semantics(mergeDescendants = true) {}
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

@Composable
private fun IconAndText(icon: ImageVector, tint: Color, title: String, message: String?, messageColor: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = uiText(20, Weight.HEAVY), color = tint)
            if (message != null) Text(message, style = uiText(16, Weight.SEMIBOLD), color = messageColor)
        }
    }
}
