import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Välj område": områdena för en kommun, med API:ts `notice`, källans förklaring och länk till vilka platser som ingår.
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
    @State private var webLink: WebLink?
    @State private var finderOpen = false

    private var notice: String? { hits.lazy.compactMap(\.notice).first }
    private var sourceNotes: [AreaSourceNote] { AreaSourceNote.notes(sources) }
    /// Ingen länk visas när ingen träff har en giltig https-adress.
    private var areasLink: WebLink? { hits.lazy.compactMap(\.areasUrl).compactMap { WebLink(url: $0) }.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let notice {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Du väljer området själv", message: notice)
                        .padding(.top, 8)
                }
                // Som på webben: varför man väljer område, och vart man vänder sig. Saknas källorna visas inget kort.
                if !sourceNotes.isEmpty {
                    AreaSourceNotesView(notes: sourceNotes)
                        .padding(.top, notice == nil ? 8 : 16)
                }
                if place != nil {
                    finderRow
                        .padding(.top, 20)
                }
                if let areasLink {
                    Button { webLink = areasLink } label: {
                        Label("Vilka platser ingår i områdena?", systemImage: "arrow.up.right.square")
                            .font(.ui(17, weight: .heavy, relativeTo: .body))
                            .foregroundStyle(Color.Theme.primary)
                    }
                    .padding(.top, 20)
                }
                ResultList {
                    ForEach(Array(hits.enumerated()), id: \.offset) { offset, hit in
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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.Theme.bg.ignoresSafeArea())
        // "Välj område" och kommunen under, i systemets fält, som de andra sidorna i arket.
        .navigationTitle("Välj område")
        .navigationSubtitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .inAppBrowser(item: $webLink)
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
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.magnifyingglass")
                    .font(.system(.title2))
                    .foregroundStyle(Color.Theme.brandText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vet du inte vilket område?")
                        .font(.ui(18, weight: .heavy, relativeTo: .headline))
                    Text("Hitta det med din senaste tömning")
                        .font(.ui(17, weight: .semibold, relativeTo: .body))
                }
                .foregroundStyle(Color.Theme.brandText)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.Theme.brandText)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vet du inte vilket område? Hitta det med din senaste tömning")
    }
}

/// Källans förklaring i områdesvalet, med webbens rubrik: varför man väljer område, och en hjälprad där telefonnumret
/// går att trycka på. Texterna står som källan skrev dem.
struct AreaSourceNotesView: View {
    let notes: [AreaSourceNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Därför väljer du område i stället för adress")
                .font(.ui(18, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    // Källans namn behövs bara när flera källor svarade.
                    if notes.count > 1 {
                        Text(note.name)
                            .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                            .foregroundStyle(Color.Theme.brandText)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let explanation = note.explanation {
                        Text(explanation)
                            .font(.ui(17, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.Theme.text)
                    }
                    if let help = note.help {
                        Text(help)
                            .font(.ui(16, weight: .semibold, relativeTo: .callout))
                            .foregroundStyle(Color.Theme.text2)
                            .tint(Color.Theme.primary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            ForEach(Array(content.otherDays.enumerated()), id: \.offset) { _, text in
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .accessibilityHidden(true)
                }
                .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 2)
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
