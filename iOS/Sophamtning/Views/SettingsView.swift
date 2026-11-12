import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Länken till integritetspolicyn på `sopor.hardyson.se`.
let privacyLink = WebLink(url: URL(string: "https://sopor.hardyson.se/integritet")!)!

private enum SettingsRoute: Hashable {
    case time, primary, sources
    case times(ReminderTiming)
    case liveActivityTiming, liveActivityTimes
}

/// Inställningar i ett ark: påminnelsetid, huvudadress, Live Activity och om appen.
struct SettingsView: View {
    let model: AppModel
    let onClose: () -> Void

    @State private var sources: [Source]?
    @State private var sourcesLoading = true
    @State private var link: WebLink?
    @State private var showsHousehold = false

    private var sourceCount: Int? { sources.map { $0.filter { !$0.testData }.count } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = model.lastStorageError {
                            Button { model.clearStorageError() } label: {
                                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                            }
                            .buttonStyle(.pressable)
                            .padding(.top, 8)
                        }
                        reminders
                        household
                        about
                        MessageCard(
                            style: .neutral,
                            icon: "info.circle",
                            title: "Inofficiell app",
                            message: "Sophämtning är inte kopplad till någon kommun eller något avfallsbolag. Vid avvikelser gäller alltid kommunens information."
                        )
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, PageMargin.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Systemets stängknapp i glas, som i iOS 26.
                    Button("Stäng", systemImage: "xmark", role: .close) { onClose() }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .time: ReminderTimeView(model: model)
                case .times(let timing): ReminderTimesView(model: model, timing: timing)
                case .liveActivityTiming: LiveActivityTimingView(model: model)
                case .liveActivityTimes: ReminderTimesView(model: model, timing: model.settings.liveActivityTiming, forLiveActivity: true)
                case .primary: PrimaryAddressView(model: model)
                case .sources: SourcesView(sources: sources, loading: sourcesLoading, onRetry: { await loadSources() })
                }
            }
            .task { await loadSources() }
            .inAppBrowser(item: $link)
            // Efter en accepterad inbjudan öppnas arket Hushåll här, ovanpå Inställningar.
            .onChange(of: model.householdSheetRequested, initial: true) { _, requested in
                guard requested else { return }
                model.householdSheetShown()
                showsHousehold = true
            }
            .sheet(isPresented: $showsHousehold) {
                HouseholdSheet(model: model)
            }
        }
    }

    private func loadSources() async {
        sourcesLoading = true
        sources = await model.sourceList()
        sourcesLoading = false
    }

    // MARK: Delar

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Påminnelser")
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.time) {
                    SettingsRow(title: "Notiser", value: model.settings.settingsValue)
                }
                if let primary = model.addresses.first(where: \.isPrimary) {
                    ResultDivider()
                    NavigationLink(value: SettingsRoute.primary) {
                        SettingsRow(title: "Huvudadress", value: primary.displayName)
                    }
                }
                ResultDivider()
                LiveActivityToggleRow(model: model, text: AddressDetail.liveActivityText(settings: model.settings))
                if model.settings.liveActivityOn {
                    ResultDivider()
                    NavigationLink(value: SettingsRoute.liveActivityTiming) {
                        SettingsRow(title: "Visas från", value: "\(model.settings.liveActivityTiming.title), \(SwedishFormat.clock(minutes: model.settings.liveActivityStartMinutes))")
                    }
                }
            }
            .buttonStyle(.pressable)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
            LiveActivityNotices(model: model, edge: .top)
            if let missed = model.missedReminderText {
                MessageCard(style: .neutral, icon: "clock.badge.exclamationmark", title: "Påminnelsen har passerat", message: missed)
                    .padding(.top, 12)
            }
        }
    }

    /// Raden Hushåll, som öppnar arket. Med hushåll står antalet deltagare som värde.
    private var household: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(HouseholdTexts.sharingHeading)
            VStack(spacing: 0) {
                Button { showsHousehold = true } label: {
                    SettingsRow(title: HouseholdTexts.title, value: householdValue)
                }
            }
            .buttonStyle(.pressable)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        }
    }

    private var householdValue: String {
        let household = model.household
        guard household.role != .none, household.status != .removed else { return "" }
        return HouseholdTexts.participantCount(household.participants.count)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Om appen")
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.sources) {
                    SettingsRow(title: "Datakällor", value: sourceCount.map { String($0) } ?? "")
                }
                ResultDivider()
                Button { link = privacyLink } label: {
                    SettingsRow(title: "Integritet", value: "")
                }
                ResultDivider()
                SettingsRow(title: "Version", value: version, showsChevron: false)
            }
            .buttonStyle(.pressable)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.ui(24, weight: .heavy, relativeTo: .title2))
            .foregroundStyle(Color.Theme.text)
            .padding(.top, 28)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Meddelanden om Live Activity. Valet behålls när iOS stänger av dem, och notisen står kvar.
/// Utan meddelanden tar vyn ingen plats, och `edge` får då inget avstånd.
struct LiveActivityNotices: View {
    let model: AppModel
    let edge: Edge.Set
    /// Hemkortet visar felet själv.
    var showsError = true

    private var systemOff: Bool { model.settings.liveActivityOn && !model.liveActivitiesEnabled }

    private var error: String? { showsError ? model.liveActivityError : nil }

    var body: some View {
        if systemOff || error != nil {
            VStack(alignment: .leading, spacing: 12) {
                if systemOff {
                    MessageCard(style: .warning, icon: "bell.slash", title: "Live Activities är avstängda", message: "Du har stängt av dem för Sophämtning i iOS.")
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        Task { await UIApplication.shared.open(url) }
                    } label: {
                        Text("Öppna Inställningar")
                            .font(.ui(17, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.primary)
                    }
                    .buttonStyle(.pressable)
                }
                if let error {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Live Activity saknas", message: error)
                }
            }
            .padding(edge, 12)
        }
    }
}

/// En rad i en inställningslista: rubrik, värde och pil.
private struct SettingsRow: View {
    let title: String
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            AdaptiveStack(spacing: 8, verticalSpacing: 2) {
                Text(title)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(.ui(19, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.Theme.text2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Ett val i en lista med bock, som tid och huvudadress.
private struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.ui(20, weight: selected ? .heavy : .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Color.Theme.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Kvällen före och samma morgon, var och en med ett eget reglage och en egen tid. Minst ett är alltid på, så det enda
/// påslagna reglaget är avstängt. Går sparandet fel visas felet och valet är kvar som förut.
private struct ReminderTimeView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.pressable)
                    }
                    ForEach(ReminderTiming.allCases, id: \.self) { timing in
                        timingSection(timing)
                    }
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Notiser")
        .navigationBarTitleDisplayMode(.large)
    }

    private func timingSection(_ timing: ReminderTiming) -> some View {
        let settings = model.settings
        let isOn = settings.isEnabled(timing)
        return VStack(spacing: 12) {
            Text(timing.title)
                .font(.ui(20, weight: .heavy, relativeTo: .title3))
                .foregroundStyle(Color.Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            ResultList {
                Toggle(isOn: Binding(
                    get: { model.settings.isEnabled(timing) },
                    set: { model.clearStorageError(); model.setReminder(timing, on: $0) }
                )) {
                    Text("Påminn mig")
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.text)
                }
                .toggleStyle(.switch)
                .tint(Color.Theme.primary)
                .disabled(isOn && settings.enabledTimings.count == 1)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .padding(.vertical, 6)
                .accessibilityLabel("Påminn mig \(timing.title.lowercased())")
                // Tiden går att ställa in även när valet är av, så att den är rätt när valet slås på.
                ResultDivider()
                NavigationLink(value: SettingsRoute.times(timing)) {
                    SettingsRow(title: "Tid", value: SwedishFormat.clock(minutes: settings.minutes(for: timing)))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Tid \(timing.title.lowercased())")
                .accessibilityValue(SwedishFormat.clock(minutes: settings.minutes(for: timing)))
            }
            Text(timing.sectionFooter(minutes: settings.minutes(for: timing)))
                .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.Theme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Klockslagen för ett val i steg om 15 minuter, för notiserna eller för Live Activityns egen tid.
private struct ReminderTimesView: View {
    let model: AppModel
    let timing: ReminderTiming
    var forLiveActivity = false

    private var selected: Int {
        forLiveActivity ? model.settings.liveActivityStartMinutes : model.settings.minutes(for: timing)
    }

    private var footer: String {
        forLiveActivity ? "\(timing.timesFooter) \(ReminderTiming.liveActivityTimesFooter)" : timing.timesFooter
    }

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.pressable)
                    }
                    ResultList {
                        ForEach(Array(timing.times.enumerated()), id: \.element) { index, minutes in
                            if index > 0 { ResultDivider() }
                            ChoiceRow(title: SwedishFormat.clock(minutes: minutes), selected: minutes == selected) {
                                model.clearStorageError()
                                if forLiveActivity {
                                    model.setLiveActivityMinutes(minutes)
                                } else {
                                    model.setReminderMinutes(minutes, for: timing)
                                }
                            }
                        }
                    }
                    Text(footer)
                        .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Tid")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// När Live Activity visas: kvällen före eller samma morgon, och en egen tid. Båda är skilda från notisernas.
private struct LiveActivityTimingView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.pressable)
                    }
                    ResultList {
                        ForEach(Array(ReminderTiming.allCases.enumerated()), id: \.element) { index, timing in
                            if index > 0 { ResultDivider() }
                            ChoiceRow(title: timing.title, selected: timing == model.settings.liveActivityTiming) {
                                model.clearStorageError()
                                model.setLiveActivityTiming(timing)
                            }
                        }
                    }
                    ResultList {
                        NavigationLink(value: SettingsRoute.liveActivityTimes) {
                            SettingsRow(title: "Tid", value: SwedishFormat.clock(minutes: model.settings.liveActivityStartMinutes))
                        }
                        .buttonStyle(.pressable)
                    }
                    Text(AddressDetail.liveActivityText(settings: model.settings))
                        .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Visas från")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct PrimaryAddressView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.pressable)
                    }
                    ResultList {
                        ForEach(Array(model.addresses.enumerated()), id: \.element.key) { index, address in
                            if index > 0 { ResultDivider() }
                            ChoiceRow(title: address.displayName, selected: address.isPrimary) {
                                model.clearStorageError()
                                model.setPrimary(address.key)
                            }
                        }
                    }
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Huvudadress")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Källorna från `/kallor` i en vanlig iOS-lista: namnet, kommunerna källan täcker och länkarna till webbplatsen och
/// kontakten. Testdata visas inte. Sist står Wikidata för ortlistan.
private struct SourcesView: View {
    let sources: [Source]?
    let loading: Bool
    let onRetry: () async -> Void

    @State private var webLink: WebLink?

    var body: some View {
        Group {
            if let sources {
                let shown = sources.filter { !$0.testData }
                List {
                    Section {
                        ForEach(shown, id: \.id) { source in
                            sourceRow(source)
                        }
                    } header: {
                        Text("Schemat hämtas från \(shown.count) källor.")
                            .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.Theme.text2)
                            .textCase(nil)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wikidata (CC0)")
                                .font(.ui(18, weight: .heavy, relativeTo: .headline))
                                .foregroundStyle(Color.Theme.text)
                            Text("Ortlistan för kommunfrågan")
                                .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(Color.Theme.text2)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Color.Theme.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if loading {
                            // Medan listan hämtas visas ingen felruta.
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Hämtar källor…")
                                    .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                                    .foregroundStyle(Color.Theme.text2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            MessageCard(style: .warning, icon: "icloud.slash", title: "Kunde inte hämta källistan", message: "Försök igen om en stund.")
                            Button { Task { await onRetry() } } label: { PrimaryButtonLabel(title: "Försök igen") }
                                .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, PageMargin.horizontal)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color.Theme.bg.ignoresSafeArea())
        .inAppBrowser(item: $webLink)
        .navigationTitle("Datakällor")
        .navigationBarTitleDisplayMode(.large)
    }

    /// En källa: namnet och kommunerna, och under dem länkarna. Varje länk tar emot sitt eget tryck.
    private func sourceRow(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.ui(18, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                Text(source.kommunerText)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
            .accessibilityElement(children: .combine)
            ForEach(SourceLink.links(for: source, kommunInfo: nil)) { link in
                // Källans namn i etiketten, så att VoiceOver säger vilken källa länken hör till.
                SourceLinkButton(link: link, webLink: $webLink, source: source.name)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.Theme.surface)
    }
}
