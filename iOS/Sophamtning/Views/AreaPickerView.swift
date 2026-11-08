import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Välj område": ett varningskort med källans förklaring, sedan listan med Hitta område som första rad och områdena.
struct AreaPickerView: View {
    let model: AppModel
    let title: String
    /// Platsen områdena hämtades för. Utan plats visas inte raden för senaste tömning.
    let place: String?
    let hits: [SearchHit]
    /// Källorna som svarade i `/omraden`, med förklaringen och hjälpraden.
    let sources: [AreaSource]
    let onSaved: () -> Void

    @State private var chosen: HitSelection?
    @State private var saveFailed = false
    @State private var finderOpen = false
    @State private var query = ""

    /// Områdena som matchar sökfältet, i listans ordning. Ett tomt fält visar alla.
    private var visibleHits: [SearchHit] { AreaFilter.filter(hits, query: query) }
    /// Samma gräns som filtret: med ett enda tecken visas hela listan, och då står varningen och förklaringen kvar.
    private var isSearching: Bool { trimmedQuery.count >= AreaFilter.minimumLength }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var notice: String? { hits.lazy.compactMap(\.notice).first }
    /// Kortet överst: källans förklaring, eller `notice` när förklaringen saknas. `notice` står oförändrad i bekräftelsearket.
    private var warning: AreaWarning? { AreaWarning.make(notice: notice, notes: AreaSourceNote.notes(sources)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Under en sökning visas bara träffarna, som i systemets egna sökningar. Varningen visas igen när fältet töms
                // och `notice` står i bekräftelsearket, så den går inte förlorad.
                if !isSearching, let warning {
                    AreaWarningCard(warning: warning)
                        .padding(.top, 8)
                }
                let visible = visibleHits
                if visible.isEmpty {
                    // Ett filter utan träffar säger inget om att något saknas hos källan: listan är bara filtrerad.
                    Text("Inga områden matchar ”\(trimmedQuery)”.")
                        .font(.ui(17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isStaticText)
                    // Vägen vidare när sökningen inte ger något.
                    if place != nil {
                        ResultList { finderRow }
                            .padding(.top, 20)
                    }
                } else {
                    ResultList {
                        // Hitta område är listans första rad, i samma stil som områdena. Under en sökning visas bara träffarna.
                        if !isSearching, place != nil {
                            finderRow
                            ResultDivider()
                        }
                        // Områdets id är unikt i listan, så raden behåller sin identitet när filtret ändras.
                        ForEach(Array(visible.enumerated()), id: \.element.id) { offset, hit in
                            // Avgränsaren följer sin rad, så att den inte syns i en tom ruta.
                            VStack(spacing: 0) {
                                if offset > 0 { ResultDivider() }
                                Button { saveFailed = false; chosen = HitSelection(hit: hit) } label: {
                                    HStack(spacing: 12) {
                                        AreaDetailsView(content: AreaRowContent.make(hit))
                                        Image(systemName: "chevron.right").foregroundStyle(Color.Theme.text2).accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.pressable)
                            }
                            .rowEntranceOnAppear(index: offset)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.Theme.bg.ignoresSafeArea())
        // "Välj område" och kommunen under, i systemets fält, som de andra sidorna i arket.
        .navigationTitle("Välj område")
        .navigationSubtitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Systemets sökfält under rubriken. Områdena filtreras medan man skriver.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sök område, ort eller gata")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .sheet(isPresented: $finderOpen) {
            if let place {
                AreaFinderSheet(model: model, place: place, onSaved: onSaved, onOther: { finderOpen = false })
            }
        }
        .sheet(item: $chosen) { selection in
            let hit = selection.hit
            AreaConfirmSheet(saveFailed: saveFailed, hit: hit, onSave: {
                let saved = save(hit, in: model, onSaved: onSaved)
                saveFailed = !saved
            }, onOther: { chosen = nil })
        }
    }
}

private extension AreaPickerView {
    /// "Vet du inte vilket område?" Öppnar arket där senaste tömningen pekar ut området.
    var finderRow: some View {
        Button { finderOpen = true } label: {
            IconPlateRowLabel(icon: "calendar.badge.magnifyingglass", title: "Vet du inte vilket område?",
                              subtitle: "Hitta det med din senaste tömning")
        }
        .buttonStyle(.pressable)
    }
}

/// Ett kort i varningsstilen överst i områdesvalet: källans förklaring (eller `notice` när den saknas), att fel område kan
/// ge en missad tömning och källans hjälprad, där telefonnumret går att trycka på. Texterna står som källan skrev dem.
struct AreaWarningCard: View {
    let warning: AreaWarning
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.Theme.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(AreaWarning.title)
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.warn)
                    .accessibilityAddTraits(.isHeader)
                ForEach(warning.explanations) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        // Källans namn behövs bara när flera källor svarade.
                        if let name = entry.name {
                            Text(name)
                                .font(.ui(14, weight: .heavy, relativeTo: .footnote))
                                .foregroundStyle(Color.Theme.text)
                        }
                        Text(entry.text)
                    }
                }
                Text(AreaWarning.consequence)
                    .fontWeight(.heavy)
                ForEach(warning.helps) { help in
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = help.name {
                            Text(name)
                                .font(.ui(14, weight: .heavy, relativeTo: .footnote))
                        }
                        Text(help.text).tint(Color.Theme.primary)
                    }
                }
            }
            .font(.ui(14, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(Color.Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.warnBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Ett område som på webbens områdessida: namnet med en liten etikett, dagen, platserna på en kort rad och platser med
/// andra dagar. VoiceOver läser alla platser. Utan detaljer visas namnet och `detail` som förut.
struct AreaDetailsView: View {
    let content: AreaRowContent
    var titleSize: CGFloat = 20
    var titleStyle: Font.TextStyle = .headline
    /// Bekräftelsen visar alla platser, listan bara den korta raden.
    var showsAllPlaces = false
    /// Etikettens bakgrund, så att den syns mot kortet den står på.
    var labelBackground: Color = Color.Theme.brandSoft
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow
            if let day = content.day {
                Text(day)
                    .font(content.detailed ? .ui(16, weight: .heavy, relativeTo: .callout) : .ui(16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(content.detailed ? Color.Theme.brandText : Color.Theme.text2)
            }
            if let places = showsAllPlaces ? content.allPlaces : content.places {
                Text(places)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
            if !content.otherDays.isEmpty {
                // Rubriken som på webben, så att raderna under har ett sammanhang.
                Text(AreaRowContent.otherDaysHeading)
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
                    .padding(.top, 6)
            }
            ForEach(Array(content.otherDays.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        // Hela bredden, så att raderna inte bryts tidigare än de behöver.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    /// Namnet med etiketten till höger, som på webben. Med största text står etiketten under, så att inget trängs.
    @ViewBuilder
    private var titleRow: some View {
        let title = Text(content.title)
            .font(.ui(titleSize, weight: .heavy, relativeTo: titleStyle))
            .foregroundStyle(Color.Theme.text)
            .layoutPriority(1)
        if let label = content.label {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    title
                    labelBadge(label)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    labelBadge(label)
                }
            }
        } else {
            title
        }
    }

    private func labelBadge(_ label: String) -> some View {
        Text(label)
            .font(.ui(13, weight: .heavy, relativeTo: .caption))
            .foregroundStyle(Color.Theme.brandText)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(labelBackground, in: Capsule())
            .fixedSize()
    }
}
