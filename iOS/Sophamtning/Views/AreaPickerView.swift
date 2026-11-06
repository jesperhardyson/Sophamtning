import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Välj område": områdena för en kommun, med API:ts `notice` och länk till vilka platser som ingår.
struct AreaPickerView: View {
    let model: AppModel
    let title: String
    let hits: [SearchHit]
    let onSaved: () -> Void

    @State private var chosen: HitSelection?

    private var notice: String? { hits.lazy.compactMap(\.notice).first }
    private var areasURL: URL? { hits.lazy.compactMap(\.areasUrl).first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Välj område")
                    .font(.brand(40, relativeTo: .largeTitle))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let notice {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Du väljer området själv", message: notice)
                        .padding(.top, 20)
                }
                if let areasURL {
                    Link(destination: areasURL) {
                        Label("Vilka platser ingår i områdena?", systemImage: "arrow.up.right.square")
                            .font(.ui(17, weight: .heavy, relativeTo: .body))
                            .foregroundStyle(Color.Theme.primary)
                    }
                    .padding(.top, 20)
                }
                ResultList {
                    ForEach(Array(hits.enumerated()), id: \.offset) { offset, hit in
                        if offset > 0 { ResultDivider() }
                        Button { chosen = HitSelection(hit: hit) } label: {
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.Theme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        
        .sheet(item: $chosen) { selection in
            let hit = selection.hit
            AreaConfirmSheet(model: model, hit: hit, onSave: {
                _ = save(hit, in: model, onSaved: onSaved)
            }, onOther: { chosen = nil })
        }
    }
}
