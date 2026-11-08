import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Huvudkortet på hemskärmen: huvudadressens nästa tömning och reglaget för påminnelsen.
/// Kortet öppnar adressvyn vid tryck, i alla lägen. Bara reglaget tar emot sina egna tryck. Hela kortet fjädrar när
/// knappen trycks ned.
struct PrimaryCard: View {
    let entry: HomeContent.Entry
    /// Kalenderbladets vändning vid start från början.
    var opening: CalendarTile.Opening?
    /// Ökar när påminnelsen faktiskt har slagits på, för ikonens studs och vibrationen.
    var reminderPulse = 0
    let onOpen: () -> Void
    /// Reglaget slås på eller av. Samma flöde som i adressvyn.
    var onReminderChange: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pressed = false

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
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onOpen) { content }
                .buttonStyle(PressReportingButtonStyle(pressed: $pressed))
            if case .upcoming = entry.status, let reminder = entry.reminder {
                PrimaryReminderRow(reminder: reminder, pulse: reminderPulse, onChange: { onReminderChange($0) }, onOpenSettings: { onOpenSettings() })
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
        // Ett tryck utanför knappen och reglaget, till exempel i kanten, öppnar också adressen.
        .onTapGesture { onOpen() }
        .pressEffect(pressed: pressed)
        // För VoiceOver är kortet en enda knapp, som förut. Påminnelsen läses sist, och slås på och av med kortets
        // åtgärder, som snabbmenyn.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Öppnar adressen")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityActions {
            if entry.reminder?.isDenied == true {
                Button("Öppna Inställningar") { onOpenSettings() }
            }
        }
        // Utanför padding och bakgrund, så att kortets höjd och bakgrund också följer med mjukt.
        .animation(Motion.transition(reduceMotion: reduceMotion), value: phase)
        .animation(Motion.transition(reduceMotion: reduceMotion), value: entry.refreshFailed)
    }

    private var accessibilityText: String {
        var parts = [entry.accessibilityLabel]
        if case .upcoming = entry.status, let reminder = entry.reminder {
            parts.append(reminder.isDenied ? reminder.title : "\(reminder.title): \(reminder.isOn ? "på" : "av")")
            if let detail = reminder.detail { parts.append(detail) }
        }
        return parts.joined(separator: ", ")
    }

    /// Allt utom reglaget: rubriken, nästa tömning och kärlen, eller laddning och fel.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch entry.status {
            case .upcoming(let pickup):
                Group {
                    nextPickup(pickup)
                    fractions(pickup)
                    scheduleEnding
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                    placeLines
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(.body, weight: .semibold))
                        .accessibilityHidden(true)
                    // Platsen under namnet, så att den får hela bredden. Den bryts i stället för att kapas.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.ui(18, weight: .heavy, relativeTo: .headline))
                        placeLines
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

    /// Adressen och platsen. På det gröna kortet är platsen något svagare än adressen i stället för `text2`, som inte
    /// syns mot grönt.
    private var placeLines: some View {
        AddressLinesView(lines: entry.lines, size: 15, addressStyle: .subheadline, addressColor: foreground.opacity(0.9), placeColor: foreground.opacity(0.8))
    }

    private func nextPickup(_ pickup: HomeContent.Pickup) -> some View {
        AdaptiveStack(spacing: 20) {
            CalendarTile(date: pickup.date, opening: opening)
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

    /// "Schemat slutar 10 jan" under kärlen, när schemat tar slut inom 14 dagar. Raden bryts hellre än att tränga undan
    /// något, och VoiceOver läser den som en del av kortet.
    @ViewBuilder
    private var scheduleEnding: some View {
        if let ending = entry.scheduleEnding {
            Label {
                Text(ending.shortText)
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
            } icon: {
                Image(systemName: "calendar.badge.clock")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(foreground.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fractions(_ pickup: HomeContent.Pickup) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(pickup.fractions) { fraction in
                FractionChip(id: fraction.id, info: fraction.info)
            }
        }
    }

}

/// Reglaget för påminnelsen på huvudkortet, som ett vanligt reglage i iOS: av, eller på med tiden under. Nekar iOS
/// notiser är reglaget av och går inte att slå på, och en knapp öppnar Inställningar, som i adressvyn.
private struct PrimaryReminderRow: View {
    let reminder: HomeContent.PrimaryReminder
    let pulse: Int
    let onChange: (Bool) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var foreground: Color { Color.Theme.onPrimary }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Med stor text står ikonen och reglaget överst, och texten får hela bredden under dem.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        symbol
                        Spacer(minLength: 0)
                        toggle
                    }
                    texts
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    symbol
                    texts
                    Spacer(minLength: 0)
                    toggle
                }
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.Theme.cardOverlay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: pulse)
    }

    private var symbol: some View {
        ReminderSymbol(symbol: reminder.isDenied ? "bell.slash" : "bell.badge", pulse: pulse, color: foreground)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reminder.title)
                .font(.ui(16, weight: .bold, relativeTo: .callout))
            if reminder.isDenied {
                Button { onOpenSettings() } label: {
                    Text("Öppna Inställningar")
                        .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                        .underline()
                }
                .buttonStyle(.plain)
            } else if let detail = reminder.detail {
                Text(detail)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .opacity(0.9)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var toggle: some View {
        Toggle(reminder.title, isOn: Binding(get: { reminder.isOn }, set: { onChange($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            // En mörk bana i både ljust och mörkt läge, så att påslaget syns tydligt mot det gröna kortet och den vita
            // knoppen.
            .tint(Color.Theme.toggleOn)
            .disabled(reminder.isDenied)
            // Det avstängda reglaget öppnar Inställningar, i stället för att trycket går vidare och öppnar adressen.
            .overlay {
                if reminder.isDenied {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenSettings() }
                }
            }
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
