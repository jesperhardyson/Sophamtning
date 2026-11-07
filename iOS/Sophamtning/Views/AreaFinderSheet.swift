import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "När tömdes ditt kärl senast?" Datumet pekar ut området, och valet går vidare till samma bekräftelse som listan.
struct AreaFinderSheet: View {
    let model: AppModel
    let onSaved: () -> Void
    /// "Välj område själv": stänger arket så att områdeslistan syns.
    let onOther: () -> Void

    @State private var finder: AreaFinder
    /// Öppen från början, eftersom användaren ska ange datumet själv.
    @State private var showCalendar = true
    /// Arket står i stort läge medan kalendern är utfälld, så att den och knappen får plats.
    @State private var detent: PresentationDetent = AreaFinderSheet.expanded
    /// Om arket gick till stort läge för kalenderns skull. Drar användaren själv, lämnas läget i fred.
    @State private var expandedForCalendar = true
    /// Läget som appen själv satte senast. Ett annat läge betyder att användaren dragit.
    @State private var expectedDetent: PresentationDetent = AreaFinderSheet.expanded
    @State private var chosen: HitSelection?
    @State private var saveFailed = false

    init(model: AppModel, place: String, onSaved: @escaping () -> Void, onOther: @escaping () -> Void) {
        self.model = model
        self.onSaved = onSaved
        self.onOther = onOther
        _finder = State(initialValue: AreaFinder(api: model.api, place: place))
    }

    /// Kalendern ändrar bara utkastet. Datumväljaren och dagen läses i Europe/Stockholm.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { finder.draft.pickerDate(in: StockholmClock.timeZone) },
            set: { finder.setDraft(DayDate.from(picked: $0, in: StockholmClock.timeZone)) }
        )
    }

    private var selectableRange: PartialRangeThrough<Date> {
        ...StockholmClock.date(on: finder.latestSelectable, minutes: 23 * 60 + 59)
    }

    private static let compact = PresentationDetent.fraction(0.8)
    private static let expanded = PresentationDetent.large

    var body: some View {
        // Systemets fält med systemets stängknapp. Frågan står som rubrik i innehållet, eftersom den är för lång för
        // fältet.
        NavigationStack {
            content
                .navigationTitle("Hitta område")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Stäng", systemImage: "xmark", role: .close) { onOther() }
                    }
                }
        }
        .presentationDetents([AreaFinderSheet.compact, AreaFinderSheet.expanded], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("När tömdes ditt kärl senast?")
                    .font(.ui(28, weight: .heavy, relativeTo: .title))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                Text("Varje hämtdag hör till ett område, så datumet visar vilket som gäller.")
                    .font(.ui(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .padding(.top, 14)
                Text("Senaste tömning")
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
                    .padding(.top, 20)
                dateField
                    .padding(.top, 8)
                if showCalendar {
                    DatePicker("Senaste tömning", selection: dateBinding, in: selectableRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Color.Theme.primary)
                        .environment(\.timeZone, StockholmClock.timeZone)
                        .environment(\.locale, Locale(identifier: "sv_SE"))
                        .padding(.top, 8)
                }
                result
                    .padding(.top, 16)
                Button(action: onOther) {
                    Text("Välj område själv")
                        .font(.ui(18, weight: .heavy, relativeTo: .body))
                        .foregroundStyle(Color.Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Den primära knappen står fast längst ned, ovanför hemindikatorn, och innehållet scrollar ovanför.
        .safeAreaBar(edge: .bottom) { primaryBar }
        .background(Color.Theme.surface.ignoresSafeArea())
        .onChange(of: showCalendar) { _, shown in calendarChanged(shown) }
        .onChange(of: detent) { _, new in
            // Ett läge som appen inte satte kommer från användaren.
            if new != expectedDetent {
                expandedForCalendar = false
                expectedDetent = new
            }
        }
        .onDisappear { finder.cancel() }
        // Lätt vibration när områden hittats. Inget vid fel eller noll träffar.
        .sensoryFeedback(.impact(weight: .light), trigger: finder.state) { _, state in state.foundAreas }
        .sheet(item: $chosen) { selection in
            let hit = selection.hit
            AreaConfirmSheet(saveFailed: saveFailed, hit: hit, onSave: {
                let saved = save(hit, in: model, onSaved: onSaved)
                saveFailed = !saved
            }, onOther: { chosen = nil })
        }
    }

    // MARK: Knappen längst ned

    /// Den primära knappen för läget, eller ingen. Den står fast längst ned i arket.
    @ViewBuilder
    private var primaryBar: some View {
        if let action = primaryAction {
            Button { action.run() } label: { PrimaryButtonLabel(title: action.title) }
                .buttonStyle(.pressable)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        }
    }

    private struct PrimaryAction {
        let title: String
        let run: () -> Void
    }

    private var primaryAction: PrimaryAction? {
        if showCalendar {
            return PrimaryAction(title: "Hitta område") {
                withAnimation(.snappy) { showCalendar = false }
                finder.find()
            }
        }
        switch finder.state {
        case .match(let hit):
            return PrimaryAction(title: "Välj det här området") { choose(hit) }
        case .failed where finder.retryable:
            return PrimaryAction(title: "Försök igen") { finder.retry() }
        case .failed:
            return PrimaryAction(title: "Välj ett annat datum") { withAnimation(.snappy) { showCalendar = true } }
        default:
            return nil
        }
    }

    /// Kalendern fälls ut: stort läge. Den fälls ihop: tillbaka, om arket gick upp för kalenderns skull.
    private func calendarChanged(_ shown: Bool) {
        if shown {
            guard detent != AreaFinderSheet.expanded else { return }
            expandedForCalendar = true
            setDetent(AreaFinderSheet.expanded)
        } else if expandedForCalendar {
            expandedForCalendar = false
            setDetent(AreaFinderSheet.compact)
        }
    }

    private func setDetent(_ new: PresentationDetent) {
        expectedDetent = new
        detent = new
    }

    // MARK: Datum

    private var dateText: String {
        finder.date.map { SwedishFormat.longDateWithYear($0) } ?? "Välj datum"
    }

    private var dateField: some View {
        Button { withAnimation(.snappy) { showCalendar.toggle() } } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(.title3))
                    .foregroundStyle(Color.Theme.primary)
                    .accessibilityHidden(true)
                Text(dateText)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(finder.date == nil ? Color.Theme.text2 : Color.Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(Color.Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.Theme.primary, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Senaste tömning, \(dateText)")
        .accessibilityHint("Ändrar datum")
    }

    // MARK: Svar

    @ViewBuilder
    private var result: some View {
        switch finder.state {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 12) {
                ProgressView()
                Text("Söker områden")
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        case .match(let hit):
            matchCard(hit)
        case .multiple(let hits):
            VStack(alignment: .leading, spacing: 16) {
                Text("Flera områden hade hämtning den dagen. Välj ditt område.")
                    .font(.ui(18, weight: .heavy, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if finder.partial { partialText.padding(.top, 0) }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                    Button { choose(hit) } label: { listCard(hit, showKommun: AreaFinderText.showsKommun(hits)) }
                        .buttonStyle(.pressable)
                }
            }
        case .noPickup:
            infoCard(title: "Inget område har hämtning den dagen", message: "Prova ett annat datum eller välj område i listan.")
        case .outsideSchedule:
            infoCard(title: "Schemat täcker inte det datumet", message: "Prova ett senare datum eller välj område i listan.")
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text(finder.retryable ? "Kunde inte kontrollera just nu" : "Kunde inte kontrollera det datumet")
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.warn)
                Text(finder.retryable ? "Det säger inget om ditt område. Försök igen om en stund."
                                      : "Det säger inget om ditt område. Välj ett annat datum eller välj område själv.")
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Theme.warnBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func matchCard(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Det här bör vara ditt område")
                .font(.ui(16, weight: .heavy, relativeTo: .callout))
                .foregroundStyle(Color.Theme.brandText)
            AreaDetailsView(content: AreaRowContent.make(hit), titleSize: 24, titleStyle: .title2, labelBackground: Color.Theme.surface)
                .padding(.top, 8)
            Text(AreaFinderText.check(hit.pickups, today: finder.latestSelectable))
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if finder.partial { partialText }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var partialText: some View {
        Text(AreaFinderText.partialNotice)
            .font(.ui(16, weight: .heavy, relativeTo: .callout))
            .foregroundStyle(Color.Theme.warn)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    private func listCard(_ hit: SearchHit, showKommun: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showKommun {
                Text(kommunDisplayName(hit.kommun))
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.brandText)
            }
            AreaDetailsView(content: AreaRowContent.make(hit), titleSize: 22, titleStyle: .title3, labelBackground: Color.Theme.surface)
            if let summary = AreaFinderText.summary(hit.pickups, today: finder.latestSelectable) {
                Text(summary)
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func infoCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ui(20, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.text)
            Text(message)
                .font(.ui(17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.earthSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func choose(_ hit: SearchHit) {
        saveFailed = false
        chosen = HitSelection(hit: hit)
    }
}
