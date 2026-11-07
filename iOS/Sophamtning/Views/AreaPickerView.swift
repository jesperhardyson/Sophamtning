import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Välj område": områdena för en kommun, med API:ts `notice` och länk till vilka platser som ingår.
struct AreaPickerView: View {
    let model: AppModel
    let title: String
    /// Platsen områdena hämtades för. Utan plats visas inte raden för senaste tömning.
    let place: String?
    let hits: [SearchHit]
    let onSaved: () -> Void

    @State private var chosen: HitSelection?
    @State private var saveFailed = false
    @State private var webLink: WebLink?
    @State private var finderOpen = false

    private var notice: String? { hits.lazy.compactMap(\.notice).first }
    /// Ingen länk visas när ingen träff har en giltig https-adress.
    private var areasLink: WebLink? { hits.lazy.compactMap(\.areasUrl).compactMap { WebLink(url: $0) }.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let notice {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Du väljer området själv", message: notice)
                        .padding(.top, 8)
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hit.street)
                                            .font(.ui(20, weight: .heavy, relativeTo: .headline))
                                            .foregroundStyle(Color.Theme.text)
                                            .multilineTextAlignment(.leading)
                                        if let detail = hit.detail {
                                            Text(detail)
                                                .font(.ui(16, weight: .semibold, relativeTo: .callout))
                                                .foregroundStyle(Color.Theme.text2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer(minLength: 0)
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
