import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Huvudkortet på hemskärmen: huvudadressens nästa tömning och raden för påminnelse.
/// Hela kortet är en knapp som öppnar adressvyn, i alla lägen.
struct PrimaryCard: View {
    let entry: HomeContent.Entry
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var foreground: Color { Color.Theme.onPrimary }

    /// Vilket läge kortet visar. Ett byte tonas mjukt, men ändrade uppgifter i samma läge gör ingen övergång.
    private var phase: Int {
        switch entry.status {
        case .upcoming: 0
        case .loading: 1
        case .noUpcoming: 2
        case .failed: 3
        }
    }

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Öppnar adressen")
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [entry.accessibilityLabel]
        if let text = entry.reminderText { parts.append(text) }
        return parts.joined(separator: ", ")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch entry.status {
            case .upcoming(let pickup):
                Group {
                    nextPickup(pickup)
                    fractions(pickup)
                    if let text = entry.reminderText {
                        reminderRow(text)
                    }
                }
                .transition(.opacity)
            case .loading:
                // Kärlet är grönt och står på en ljus platta, så att det syns mot det gröna kortet.
                // Texten under är dekoration, och VoiceOver läser "Hämtar schema".
                BinLoaderView(textColor: Color.Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            case .noUpcoming, .failed:
                Text(entry.summary)
                    .font(.ui(20, weight: .heavy, relativeTo: .title3))
                    .foregroundStyle(foreground)
                    .transition(.opacity)
            }
            if entry.refreshFailed {
                Text("Kunde inte uppdatera schemat. Visar det senast hämtade.")
                    .font(.ui(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(foreground.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.Theme.primary, Color.Theme.brandText], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        // Utanför padding och bakgrund, så att kortets höjd och bakgrund också följer med mjukt.
        .animation(Motion.transition(reduceMotion: reduceMotion), value: phase)
        .animation(Motion.transition(reduceMotion: reduceMotion), value: entry.refreshFailed)
    }

    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Under varandra, och utan pil: hela kortet är ändå en knapp. Då får texten hela bredden.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "house")
                            .font(.system(.body, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(entry.title)
                            .font(.ui(18, weight: .heavy, relativeTo: .headline))
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                    }
                    Text(entry.subtitle)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .opacity(0.9)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(.body, weight: .semibold))
                        .accessibilityHidden(true)
                    AdaptiveStack(spacing: 8, verticalSpacing: 2) {
                        Text(entry.title)
                            .font(.ui(18, weight: .heavy, relativeTo: .headline))
                        Text(entry.subtitle)
                            .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                            .opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }

    private func nextPickup(_ pickup: HomeContent.Pickup) -> some View {
        AdaptiveStack(spacing: 20) {
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
                    .rollingNumbers(value: pickup.headline, reduceMotion: reduceMotion)
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
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(.body, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.ui(16, weight: .bold, relativeTo: .callout))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.Theme.cardOverlay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            // Barnen får högst radens bredd, så att långa namn bryts i stället för att klippas.
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
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
