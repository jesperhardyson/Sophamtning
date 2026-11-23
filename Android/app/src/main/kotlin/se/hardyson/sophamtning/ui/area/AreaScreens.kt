package se.hardyson.sophamtning.ui.area

import androidx.compose.ui.res.stringResource
import se.hardyson.sophamtning.R
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import java.time.LocalDate
import se.hardyson.sophamtning.AppDependencies
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.kommun.kommunDisplayName
import se.hardyson.sophamtning.core.search.AreaFinderState
import se.hardyson.sophamtning.core.search.AreaFinderText
import se.hardyson.sophamtning.core.search.AreaPickerContent
import se.hardyson.sophamtning.core.search.AreaRowContent
import se.hardyson.sophamtning.core.search.AreaSourceNote
import se.hardyson.sophamtning.core.search.AreaWarning
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaFinder
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.components.FlowSearchField
import se.hardyson.sophamtning.ui.components.IconPlateRow
import se.hardyson.sophamtning.ui.components.MessageCard
import se.hardyson.sophamtning.ui.components.MessageStyle
import se.hardyson.sophamtning.ui.components.PageMargin
import se.hardyson.sophamtning.ui.components.PlainButton
import se.hardyson.sophamtning.ui.components.PrimaryButton
import se.hardyson.sophamtning.ui.components.ScreenScaffold
import se.hardyson.sophamtning.ui.components.SearchingRow
import se.hardyson.sophamtning.ui.components.SectionCard
import se.hardyson.sophamtning.ui.components.SectionDivider
import se.hardyson.sophamtning.ui.search.save
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText
import se.hardyson.sophamtning.core.search.AreaFinder as Finder

// MARK: Välj område

/** "Välj område", som AreaPickerView.swift: varningen, sedan listan med Hitta område först och områdena. */
@Composable
fun AreaPickerScreen(key: AreaPicker, navigator: AppNavigator) {
    val held = LocalAppDependencies.current.heldAreas.get(key.held)
    if (held == null) {
        // Appen har dödats och områdena finns inte kvar i minnet. Skärmen före hämtar dem igen.
        LaunchedEffect(key) { navigator.back() }
        return
    }
    var query by rememberSaveable { mutableStateOf("") }
    val content = AreaPickerContent.make(held.hits, query, hasFinder = key.place != null)
    val notice = held.hits.firstNotNullOfOrNull { it.notice }
    val warning = remember(key) { AreaWarning.make(notice, AreaSourceNote.notes(held.sources)) }
    val openFinder = { key.place?.let { navigator.open(AreaFinder(it)) } }
    ScreenScaffold(title = stringResource(R.string.area_picker_title, key.title), onBack = { navigator.back() }) { padding ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(horizontal = PageMargin).padding(bottom = 24.dp)) {
            FlowSearchField(query, { query = it }, placeholder = stringResource(R.string.area_search_placeholder), focus = false, modifier = Modifier.padding(top = 8.dp))
            // Under en sökning visas bara träffarna. Varningen kommer tillbaka när fältet töms.
            if (content.showsWarning) AreaWarningCard(warning, Modifier.padding(top = 16.dp))
            val emptyText = content.emptyText
            if (emptyText != null) {
                Text(emptyText, style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text2.color, modifier = Modifier.padding(top = 20.dp))
                if (content.showsFinderWhenEmpty) SectionCard(Modifier.padding(top = 20.dp)) { FinderRow { openFinder() } }
            } else {
                SectionCard(Modifier.padding(top = 20.dp)) {
                    if (content.showsFinderFirst) {
                        FinderRow { openFinder() }
                        SectionDivider()
                    }
                    content.hits.forEachIndexed { index, hit ->
                        if (index > 0) SectionDivider()
                        Row(
                            Modifier.fillMaxWidth().clickable(role = Role.Button) { navigator.open(AreaConfirm(key.held, hit.id)) }.padding(horizontal = 20.dp, vertical = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            AreaDetails(AreaRowContent.make(hit), Modifier.weight(1f))
                            Chevron()
                        }
                    }
                }
            }
        }
    }
}

/** "Vet du inte vilket område?" Öppnar Hitta område, där senaste tömningen pekar ut området. */
@Composable
private fun FinderRow(onClick: () -> Unit) {
    IconPlateRow(AppSymbols.CalendarMonth, stringResource(R.string.area_finder_row_title), stringResource(R.string.area_finder_row_subtitle), onClick, horizontalPadding = 20, verticalPadding = 16)
}

// MARK: Stämmer området?

/** "Stämmer området?", som AreaConfirmSheet.swift. Området sparas först när användaren trycker Spara området. */
@Composable
fun AreaConfirmScreen(key: AreaConfirm, navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    var saveFailed by rememberSaveable { mutableStateOf(false) }
    var allPlaces by rememberSaveable { mutableStateOf(false) }
    val hit = dependencies.heldAreas.get(key.held)?.hits?.firstOrNull { it.id == key.hitId }
    if (hit == null) {
        // Appen har dödats och området finns inte kvar i minnet. Skärmen före hämtar det igen.
        LaunchedEffect(key) { navigator.back() }
        return
    }
    ScreenScaffold(title = "", onBack = { navigator.back() }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 24.dp)) {
                Text(stringResource(R.string.area_confirm_title), style = uiText(28, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.semantics { heading() })
                val content = AreaRowContent.make(hit)
                Column(
                    Modifier.padding(top = 20.dp).fillMaxWidth().background(ThemeToken.Surface2.color, RoundedCornerShape(20.dp)).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AreaDetails(content, showsAllPlaces = allPlaces, labelBackground = ThemeToken.Surface.color)
                    if (content.hidesPlaces) {
                        Text(
                            content.placesToggleText(allPlaces),
                            style = uiText(16, Weight.HEAVY),
                            color = ThemeToken.Primary.color,
                            modifier = Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) { allPlaces = !allPlaces }.padding(vertical = 12.dp),
                        )
                    }
                }
                hit.notice?.let { Text(it, style = uiText(18, Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 16.dp)) }
                if (saveFailed) {
                    MessageCard(stringResource(R.string.error_title), stringResource(R.string.save_failed), MessageStyle.Warning, Icons.Filled.Warning, Modifier.padding(top = 12.dp))
                }
                PlainButton(stringResource(R.string.area_choose_other), { navigator.back() }, Modifier.padding(top = 16.dp))
            }
            // Spara området står fast längst ned, så att knappen alltid syns, också med största textstorlek.
            PrimaryButton(
                stringResource(R.string.area_save),
                {
                    val saved = dependencies.model.save(hit)
                    saveFailed = saved == null
                    saved?.let(navigator::saved)
                },
                Modifier.padding(horizontal = PageMargin, vertical = 8.dp),
            )
        }
    }
}

// MARK: Hitta område

class AreaFinderViewModel(dependencies: AppDependencies, place: String) : ViewModel() {
    val finder = Finder(dependencies.api, place, viewModelScope, dependencies.clock)

    override fun onCleared() = finder.cancel()
}

private fun DayDate.utcMillis(): Long = LocalDate.of(year, month, day).toEpochDay() * 86_400_000L

private fun dayFromUtcMillis(millis: Long): DayDate = LocalDate.ofEpochDay(Math.floorDiv(millis, 86_400_000L)).let { DayDate(it.year, it.monthValue, it.dayOfMonth) }

/** "När tömdes ditt kärl senast?", som AreaFinderSheet.swift. Datumet pekar ut området, och valet går till bekräftelsen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AreaFinderScreen(key: AreaFinder, navigator: AppNavigator) {
    val dependencies = LocalAppDependencies.current
    val vm: AreaFinderViewModel = viewModel { AreaFinderViewModel(dependencies, key.place) }
    val finder = vm.finder
    val snapshot by finder.snapshot.collectAsStateWithLifecycle()
    // Öppen från början, eftersom användaren ska ange datumet själv.
    var showCalendar by rememberSaveable { mutableStateOf(true) }
    val latest = finder.latestSelectable.utcMillis()
    val pickerState = rememberDatePickerState(
        initialSelectedDateMillis = snapshot.draft.utcMillis(),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= latest
        },
    )
    LaunchedEffect(pickerState.selectedDateMillis) {
        pickerState.selectedDateMillis?.let { finder.setDraft(dayFromUtcMillis(it)) }
    }
    val choose = { hit: SearchHit -> navigator.open(AreaConfirm(dependencies.heldAreas.put(listOf(hit)), hit.id)) }
    ScreenScaffold(title = stringResource(R.string.area_finder_title), onBack = { navigator.back() }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PageMargin).padding(bottom = 24.dp)) {
                Text(stringResource(R.string.area_finder_question), style = uiText(28, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
                Text(
                    stringResource(R.string.area_finder_text),
                    style = uiText(18, Weight.SEMIBOLD),
                    color = ThemeToken.Text2.color,
                    modifier = Modifier.padding(top = 14.dp),
                )
                Text(stringResource(R.string.area_finder_last), style = uiText(15, Weight.HEAVY), color = ThemeToken.Text2.color, modifier = Modifier.padding(top = 20.dp))
                val dateText = snapshot.date?.let(SwedishFormat::longDateWithYear) ?: stringResource(R.string.area_finder_choose_date)
                val dateLabel = stringResource(R.string.area_finder_date_label, dateText)
                val changesDate = stringResource(R.string.area_finder_changes_date)
                Row(
                    Modifier
                        .padding(top = 8.dp)
                        .fillMaxWidth()
                        .heightIn(min = 52.dp)
                        .background(ThemeToken.Surface.color, CircleShape)
                        .border(2.dp, ThemeToken.Primary.color, CircleShape)
                        .clickable(role = Role.Button) { showCalendar = !showCalendar }
                        .semantics(mergeDescendants = true) {
                            contentDescription = dateLabel
                            stateDescription = changesDate
                        }
                        .padding(horizontal = 18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Filled.DateRange, contentDescription = null, tint = ThemeToken.Primary.color)
                    Text(dateText, style = uiText(20, Weight.HEAVY), color = if (snapshot.date == null) ThemeToken.Text2.color else ThemeToken.Text.color)
                }
                if (showCalendar) {
                    DatePicker(
                        state = pickerState,
                        title = null,
                        headline = null,
                        showModeToggle = false,
                        colors = DatePickerDefaults.colors(
                            containerColor = ThemeToken.Surface.color,
                            selectedDayContainerColor = ThemeToken.Primary.color,
                            selectedDayContentColor = ThemeToken.OnPrimary.color,
                            todayDateBorderColor = ThemeToken.Primary.color,
                            todayContentColor = ThemeToken.Primary.color,
                        ),
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                Column(Modifier.padding(top = 16.dp)) { FinderResult(finder, snapshot, choose) }
                PlainButton(stringResource(R.string.area_finder_choose_self), { navigator.back() }, Modifier.padding(top = 8.dp))
            }
            // Den primära knappen för läget står fast längst ned.
            val primary: Pair<String, () -> Unit>? = when {
                showCalendar -> stringResource(R.string.area_finder_title) to {
                    showCalendar = false
                    finder.find()
                }
                snapshot.state is AreaFinderState.Match -> stringResource(R.string.area_finder_choose_this) to { choose((snapshot.state as AreaFinderState.Match).hit) }
                snapshot.state == AreaFinderState.Failed && snapshot.retryable -> stringResource(R.string.action_retry) to { finder.retry() }
                snapshot.state == AreaFinderState.Failed -> stringResource(R.string.area_finder_other_date) to { showCalendar = true }
                else -> null
            }
            primary?.let { (title, action) -> PrimaryButton(title, action, Modifier.padding(horizontal = PageMargin, vertical = 8.dp).navigationBarsPadding()) }
        }
    }
}

@Composable
private fun FinderResult(finder: Finder, snapshot: Finder.Snapshot, choose: (SearchHit) -> Unit) {
    val today = finder.latestSelectable
    when (val state = snapshot.state) {
        AreaFinderState.Idle -> {}
        AreaFinderState.Searching -> SearchingRow(stringResource(R.string.area_finder_searching), Modifier.heightIn(min = 52.dp).padding(horizontal = 4.dp))
        is AreaFinderState.Match -> Column(
            Modifier.fillMaxWidth().background(ThemeToken.BrandSoft.color, RoundedCornerShape(20.dp)).padding(20.dp).semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(stringResource(R.string.area_finder_match), style = uiText(16, Weight.HEAVY), color = ThemeToken.BrandText.color)
            AreaDetails(AreaRowContent.make(state.hit), Modifier.padding(top = 8.dp), titleSize = 24, labelBackground = ThemeToken.Surface.color)
            Text(AreaFinderText.check(state.hit.pickups, today), style = uiText(18, Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 8.dp))
            if (snapshot.partial) PartialText()
        }
        is AreaFinderState.Multiple -> Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(R.string.area_finder_multiple), style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color)
            if (snapshot.partial) PartialText()
            val showKommun = AreaFinderText.showsKommun(state.hits)
            for (hit in state.hits) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(ThemeToken.BrandSoft.color, RoundedCornerShape(20.dp))
                        .clickable(role = Role.Button) { choose(hit) }
                        .padding(20.dp)
                        .semantics(mergeDescendants = true) {},
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (showKommun) Text(kommunDisplayName(hit.kommun), style = uiText(15, Weight.HEAVY), color = ThemeToken.BrandText.color)
                    AreaDetails(AreaRowContent.make(hit), titleSize = 22, labelBackground = ThemeToken.Surface.color)
                    AreaFinderText.summary(hit.pickups, today)?.let {
                        Text(it, style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
        AreaFinderState.NoPickup -> InfoCard(stringResource(R.string.area_finder_no_pickup_title), stringResource(R.string.area_finder_no_pickup_text))
        AreaFinderState.OutsideSchedule -> InfoCard(stringResource(R.string.area_finder_outside_title), stringResource(R.string.area_finder_outside_text))
        AreaFinderState.Failed -> Column(
            Modifier.fillMaxWidth().background(ThemeToken.WarnBg.color, RoundedCornerShape(20.dp)).padding(16.dp).semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                if (snapshot.retryable) stringResource(R.string.area_finder_failed_title) else stringResource(R.string.area_finder_failed_date_title),
                style = uiText(20, Weight.HEAVY),
                color = ThemeToken.Warn.color,
            )
            Text(
                if (snapshot.retryable) stringResource(R.string.area_finder_failed_text)
                else stringResource(R.string.area_finder_failed_date_text),
                style = uiText(17, Weight.SEMIBOLD),
                color = ThemeToken.Text.color,
            )
        }
    }
}

@Composable
private fun PartialText() {
    Text(AreaFinderText.partialNotice, style = uiText(16, Weight.HEAVY), color = ThemeToken.Warn.color, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun InfoCard(title: String, message: String) {
    Column(
        Modifier.fillMaxWidth().background(ThemeToken.EarthSoft.color, RoundedCornerShape(20.dp)).padding(16.dp).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, style = uiText(20, Weight.HEAVY), color = ThemeToken.Text.color)
        Text(message, style = uiText(17, Weight.SEMIBOLD), color = ThemeToken.Text.color)
    }
}
