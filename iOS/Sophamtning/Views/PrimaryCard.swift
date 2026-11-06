import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Huvudkortet på hemskärmen: huvudadressens nästa tömning och raden för påminnelse.
struct PrimaryCard: View {
    let entry: HomeContent.Entry
    let onReminder: () -> Void

    private var foreground: Color { Color.Theme.onPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch entry.status {
            case .upcoming(let pickup):
                nextPickup(pickup)
                fractions(pickup)
                if let text = entry.reminderText {
                    reminderRow(text)
                }
            case .noUpcoming, .loading, .failed:
                Text(entry.summary)
                    .font(.ui(20, weight: .heavy, relativeTo: .title3))
                    .foregroundStyle(foreground)
            }
            if entry.refreshFailed {
                Text("Kunde inte uppdatera schemat. Visar det senast hämtade.")
                    .font(.ui(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(foreground.opacity(0.85))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.Theme.primary, Color.Theme.brandText], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "house")
                .font(.system(.body, weight: .semibold))
                .accessibilityHidden(true)
            Text(entry.title)
                .font(.ui(18, weight: .heavy, relativeTo: .headline))
            Text(entry.subtitle)
                .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                .opacity(0.9)
                .lineLimit(2)
        }
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }

    private func nextPickup(_ pickup: HomeContent.Pickup) -> some View {
        HStack(alignment: .center, spacing: 20) {
            CalendarTile(date: pickup.date)
            VStack(alignment: .leading, spacing: 4) {
                Text("NÄSTA TÖMNING")
                    .font(.ui(13, weight: .heavy, relativeTo: .caption))
                    .tracking(1.2)
                    .opacity(0.9)
                Text(pickup.headline)
                    .font(.ui(32, weight: .heavy, relativeTo: .title))
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text(pickup.longDate)
                    .font(.ui(17, weight: .bold, relativeTo: .body))
            }
            .foregroundStyle(foreground)
            .accessibilityElement(children: .combine)
        }
    }

    private func fractions(_ pickup: HomeContent.Pickup) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(pickup.fractions) { fraction in
                FractionChip(id: fraction.id, info: fraction.info)
            }
        }
    }

    private func reminderRow(_ text: String) -> some View {
        Button(action: onReminder) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(.body, weight: .semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.ui(16, weight: .bold, relativeTo: .callout))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardOverlay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Lägger barnen på rader och bryter rad när det inte får plats.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
