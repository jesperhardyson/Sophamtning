import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Stämmer området?" Området sparas först när användaren trycker Spara området.
struct AreaConfirmSheet: View {
    let model: AppModel
    let hit: SearchHit
    let onSave: () -> Void
    let onOther: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stämmer området?")
                .font(.ui(28, weight: .heavy, relativeTo: .title))
                .foregroundStyle(Color.Theme.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
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
            if let error = model.lastStorageError {
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: error)
                    .padding(.top, 12)
            }
            Button(action: onSave) { PrimaryButtonLabel(title: "Spara området") }
                .buttonStyle(.plain)
                .padding(.top, 24)
            Button(action: onOther) {
                Text("Välj ett annat område")
                    .font(.ui(18, weight: .heavy, relativeTo: .body))
                    .foregroundStyle(Color.Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(Color.Theme.surface.ignoresSafeArea())
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
    }
}
