import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Stämmer området?" Området sparas först när användaren trycker Spara området.
struct AreaConfirmSheet: View {
    let saveFailed: Bool
    let hit: SearchHit
    /// Sparar området. Den som äger arket håller reda på om det gick.
    let onSave: () -> Void
    let onOther: () -> Void

    var body: some View {
        // Systemets fält med systemets stängknapp, som stänger arket utan att spara. Frågan står som rubrik i
        // innehållet, eftersom systemets stora rubrik kapas med största text i stället för att brytas.
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Stäng", systemImage: "xmark", role: .close) { onOther() }
                    }
                }
        }
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        // Rullbart, och Spara området står fast längst ned, så att knappen alltid syns, också i halv höjd och med
        // största textstorlek.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stämmer området?")
                    .font(.ui(28, weight: .heavy, relativeTo: .title))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.street)
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.text)
                    if let detail = hit.detail {
                        Text(detail)
                            .font(.ui(17, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.Theme.text2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 20)
                if let notice = hit.notice {
                    Text(notice)
                        .font(.ui(18, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
                if saveFailed {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: saveFailedMessage)
                        .padding(.top, 12)
                }
                Button(action: onOther) {
                    Text("Välj ett annat område")
                        .font(.ui(18, weight: .heavy, relativeTo: .body))
                        .foregroundStyle(Color.Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.pressable)
                .padding(.top, 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            // Vibrationen spelas av hemskärmen, som finns kvar när arket stängs.
            Button { onSave() } label: { PrimaryButtonLabel(title: "Spara området") }
                .buttonStyle(.pressable)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
        }
        .background(Color.Theme.surface.ignoresSafeArea())
    }
}
