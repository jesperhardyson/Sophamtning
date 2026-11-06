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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("När tömdes ditt kärl senast?")
                    .font(.ui(28, weight: .heavy, relativeTo: .title))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)
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
                    Button {
                        withAnimation(.snappy) { showCalendar = false }
                        finder.find()
                    } label: { PrimaryButtonLabel(title: "Hitta område") }
                        .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.Theme.surface.ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .onDisappear { finder.cancel() }
        .sheet(item: $chosen) { selection in
            let hit = selection.hit
            AreaConfirmSheet(saveFailed: saveFailed, hit: hit, onSave: {
                saveFailed = !save(hit, in: model, onSaved: onSaved)
            }, onOther: { chosen = nil })
        }
    }

    // MARK: Datum

    private var dateText: String {
        finder.date.map(SwedishFormat.longDateWithYear) ?? "Välj datum"
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
        .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 0) {
                matchCard(hit)
                Button { choose(hit) } label: { PrimaryButtonLabel(title: "Välj det här området") }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
            }
        case .multiple(let hits):
            VStack(alignment: .leading, spacing: 16) {
                Text("Flera områden hade hämtning den dagen. Välj ditt område.")
                    .font(.ui(18, weight: .heavy, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if finder.partial { partialText.padding(.top, 0) }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                    Button { choose(hit) } label: { listCard(hit, showKommun: AreaFinderText.showsKommun(hits)) }
                        .buttonStyle(.plain)
                }
            }
        case .noPickup:
            infoCard(title: "Inget område har hämtning den dagen", message: "Prova ett annat datum eller välj område i listan.")
        case .outsideSchedule:
            infoCard(title: "Schemat täcker inte det datumet", message: "Prova ett senare datum eller välj område i listan.")
        case .failed:
            VStack(alignment: .leading, spacing: 0) {
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
                if finder.retryable {
                    Button { finder.retry() } label: { PrimaryButtonLabel(title: "Försök igen") }
                        .buttonStyle(.plain)
                        .padding(.top, 24)
                } else {
                    Button { withAnimation(.snappy) { showCalendar = true } } label: { PrimaryButtonLabel(title: "Välj ett annat datum") }
                        .buttonStyle(.plain)
                        .padding(.top, 24)
                }
            }
        }
    }

    private func matchCard(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Det här bör vara ditt område")
                .font(.ui(16, weight: .heavy, relativeTo: .callout))
                .foregroundStyle(Color.Theme.brandText)
            Text(hit.street)
                .font(.ui(24, weight: .heavy, relativeTo: .title2))
                .foregroundStyle(Color.Theme.text)
                .padding(.top, 8)
            if let detail = hit.detail {
                Text(detail)
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
            }
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
                Text(hit.kommun)
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.brandText)
            }
            Text(hit.street)
                .font(.ui(22, weight: .heavy, relativeTo: .title3))
                .foregroundStyle(Color.Theme.text)
                .multilineTextAlignment(.leading)
            if let detail = hit.detail {
                Text(detail)
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .multilineTextAlignment(.leading)
            }
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
