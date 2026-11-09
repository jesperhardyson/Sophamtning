import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Huvudkortet på hemskärmen: huvudadressens nästa tömning, och det man behöver göra. Överst namnet och adressen, sedan
/// nästa tömning och kärlen, en fot med delningen och påminnelsen, och sist Ställ ut kärlen för en delad adress. Kortet
/// öppnar adressvyn vid tryck, i alla lägen. Bara knapparna tar emot sina egna tryck. Hela kortet fjädrar när det trycks ned.
struct PrimaryCard: View {
    let entry: HomeContent.Entry
    /// Kalenderbladets vändning vid start från början.
    var opening: CalendarTile.Opening?
    let onOpen: () -> Void
    /// Öppna Inställningar, när påminnelsen är på men iOS nekar notiser.
    var onOpenSettings: () -> Void = {}
    /// Ställ ut kärlen och Ångra för en delad adress.
    var onPlaceOut: () -> Void = {}
    var onUndoPlaceOut: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Snabbvalen från `AddressQuickActions`, som VoiceOver-åtgärder på kortets element.
    @Environment(\.addressActions) private var addressActions
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

    /// Påminnelsen när kortet visar en kommande tömning. Annars gäller den inget.
    private var reminder: HomeContent.PrimaryReminder? {
        guard case .upcoming = entry.status else { return nil }
        return entry.reminder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onOpen) { content }
                    .buttonStyle(PressReportingButtonStyle(pressed: $pressed))
                if reminder?.showsDeniedNotice == true {
                    DeniedReminderNotice(onOpenSettings: onOpenSettings)
                        .transition(.opacity)
                }
                if entry.refreshFailed {
                    Text("Kunde inte uppdatera schemat. Visar det senast hämtade.")
                        .font(.ui(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(foreground.opacity(0.85))
                        .transition(.opacity)
                }
            }
            // För VoiceOver är kortet en enda knapp, som förut. Påminnelsen läses sist. Hushållets knappar står utanför,
            // så att de går att nå och trycka på.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Öppnar adressen")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .accessibilityActions {
                if reminder?.showsDeniedNotice == true {
                    Button("Öppna Inställningar") { onOpenSettings() }
                }
                ForEach(addressActions) { action in
                    Button(action.name) { action.perform() }
                }
            }
            if let household = entry.household, HouseholdPlaceOutRow.hasContent(household) {
                HouseholdPlaceOutRow(line: household, onCard: true, onPlaceOut: onPlaceOut, onUndo: onUndoPlaceOut)
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
        // Ett tryck utanför knapparna, till exempel i kanten, öppnar också adressen.
        .onTapGesture { onOpen() }
        .pressEffect(pressed: pressed)
        .accessibilityElement(children: .contain)
        // Utanför padding och bakgrund, så att kortets höjd och bakgrund också följer med mjukt.
        .animation(Motion.transition(reduceMotion: reduceMotion), value: phase)
        .animation(Motion.transition(reduceMotion: reduceMotion), value: entry.refreshFailed)
        .animation(Motion.transition(reduceMotion: reduceMotion), value: entry.household)
        .animation(Motion.transition(reduceMotion: reduceMotion), value: entry.reminder)
    }

    private var accessibilityText: String {
        var parts = [entry.accessibilityLabel]
        if let shared = entry.household?.sharedText { parts.append(shared) }
        if let note = entry.dayNote { parts.append(note) }
        if let reminder {
            if reminder.showsDeniedNotice {
                parts.append(HomeContent.RowReminder.denied.text)
            } else if let line = reminder.line {
                parts.append(line)
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Allt utom hushållets knappar: rubriken, nästa tömning, kärlen och foten, eller laddning och fel.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch entry.status {
            case .upcoming(let pickup):
                Group {
                    nextPickup(pickup)
                    fractions(pickup)
                    scheduleEnding
                    footer
                }
                .transition(.opacity)
            case .loading:
                loading
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

    /// Namnet och under det gatan och orten på en rad. Med största text står inget hus och ingen pil, så att texten får
    /// hela bredden: hela kortet är ändå en knapp.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "house")
                    .font(.system(.body, weight: .semibold))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.ui(18, weight: .heavy, relativeTo: .headline))
                    .fixedSize(horizontal: false, vertical: true)
                let address = entry.lines.singleLine
                if !address.isEmpty {
                    // Något svagare än namnet, i stället för `text2`, som inte syns mot grönt.
                    Text(address)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(foreground.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(foreground)
        .multilineTextAlignment(.leading)
    }

    /// En tunn linje och sedan delningen och påminnelsen bredvid varandra, som bryts till två rader när de inte får
    /// plats. Ingen fot när adressen inte delas och påminnelsen är av.
    @ViewBuilder
    private var footer: some View {
        let shared = entry.household?.sharedText
        let line = reminder?.line
        if shared != nil || line != nil {
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(foreground.opacity(0.25))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                FlowLayout(spacing: 16, lineSpacing: 8) {
                    if let shared { footerLabel(shared, icon: "person.2.fill") }
                    if let line { footerLabel(line, icon: "bell.fill") }
                }
            }
        }
    }

    private func footerLabel(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
                .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.system(.footnote, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(foreground.opacity(0.9))
    }

    /// Samma uppställning som när schemat har kommit, så att kortet inte byter höjd och inget under det hoppar. Brickan
    /// och raden om nästa tömning är platshållare, och ett litet kärl står där kärlen sedan står. Kortet läses som en
    /// enhet, och VoiceOver får "Hämtar schema" från kortets etikett.
    private var loading: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdaptiveStack(spacing: 20) {
                CalendarTile(date: StockholmClock.today(now: Date()))
                VStack(alignment: .leading, spacing: 4) {
                    Text("NÄSTA TÖMNING")
                        .font(.ui(13, weight: .heavy, relativeTo: .caption))
                        .tracking(1.2)
                    Text(verbatim: "Om 3 dagar")
                        .font(.ui(32, weight: .heavy, relativeTo: .title))
                        .lineLimit(1)
                    Text(verbatim: "Måndag 9 november")
                        .font(.ui(17, weight: .bold, relativeTo: .body))
                }
                .foregroundStyle(foreground)
            }
            .redacted(reason: .placeholder)
            HStack(spacing: 10) {
                // Kärlet är grönt och står på en ljus platta, så att det syns mot det gröna kortet.
                BinLoaderView(width: 26, showsText: false)
                    .padding(10)
                    .background(Color.Theme.surface, in: Circle())
                Text("Hämtar schema")
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(foreground)
            }
        }
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
                // På tömningsdagen säger kortet vad som gäller, i stället för bara "I dag".
                if let note = entry.dayNote {
                    Text(note)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

/// Rutan när påminnelsen är på men iOS nekar notiser: **Notiser är avstängda i iOS** och **Öppna Inställningar**. Knappen
/// står till höger om texten, och under den när den inte får plats.
private struct DeniedReminderNotice: View {
    let onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var foreground: Color { Color.Theme.onPrimary }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Med största text är knappen en understruken länk och rutan har ingen inre marginal, så att
                // "Inställningar" får plats utan att brytas mitt i ordet.
                VStack(alignment: .leading, spacing: 10) {
                    label
                    Button { onOpenSettings() } label: {
                        Text("Öppna Inställningar")
                            .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        label.fixedSize()
                        Spacer(minLength: 8)
                        button
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        label
                        button
                    }
                }
            }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 16)
        .padding(.vertical, typeSize.isAccessibilitySize ? 0 : 10)
        .background(typeSize.isAccessibilitySize ? Color.clear : Color.Theme.cardOverlay, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Ett tryck i rutan utanför knappen öppnar inte adressen.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {}
    }

    private var label: some View {
        Label {
            Text(HomeContent.RowReminder.denied.text)
                .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "bell.slash")
                .font(.system(.body, weight: .semibold))
                .accessibilityHidden(true)
        }
    }

    private var button: some View {
        Button { onOpenSettings() } label: {
            Text("Öppna Inställningar")
                .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(foreground)
    }
}

/// Lägger barnen på rader och bryter rad när det inte får plats.
struct FlowLayout: Layout {
    var spacing: CGFloat
    /// Avståndet mellan raderna. Samma som `spacing` om inget annat anges.
    var lineSpacing: CGFloat?

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
                y += rowHeight + (lineSpacing ?? spacing)
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
