import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Raden för Utställt. För en delad adress: **Ställ ut kärlen**, eller bocken "Utställt av …" med **Ångra**, och hushållets
/// läge när något inte fungerar. För andra adresser "Kärlen är utställda" med **Ångra** när nästa tömning är markerad, och
/// **Ställ ut kärlen** när påminnelserna är på.
/// På huvudkortet står raden direkt på kortets gröna yta, utan egen ruta, och i adressvyn på en vanlig yta.
struct HouseholdPlaceOutRow: View {
    let line: HouseholdLine
    /// Sant på det gröna huvudkortet.
    let onCard: Bool
    let onPlaceOut: () -> Void
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Raden visas när kärlen är utställda eller knappen gäller, och för en delad adress också med hushållets läge.
    static func hasContent(_ line: HouseholdLine) -> Bool {
        line.placedOutText != nil || line.showsButton || (line.isShared && line.statusText != nil)
    }

    private var foreground: Color { onCard ? Color.Theme.onPrimary : Color.Theme.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = line.placedOutText {
                placedOutRow(text)
            } else if line.showsButton {
                Button { onPlaceOut() } label: { placeOutLabel }
                    .buttonStyle(.pressable)
            }
            if let status = line.statusText {
                Label {
                    Text(status)
                        .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "icloud.slash")
                        .font(.system(.footnote, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(onCard ? foreground.opacity(0.9) : Color.Theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Raden tar emot sina egna tryck, så att bara knapparna gör något. På kortet öppnar ett tryck på bocken inte adressen.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {}
    }

    /// Bocken som en rad: en bock i en cirkel, **Utställt** och under det vem och när, med **Ångra** till höger. Vid största
    /// text står Ångra under texten i full bredd. VoiceOver läser bocken som en mening, med Ångra som åtgärd.
    @ViewBuilder
    private func placedOutRow(_ text: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                mark(text)
                undoButton(fullWidth: true)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                mark(text)
                Spacer(minLength: 8)
                undoButton(fullWidth: false)
            }
        }
    }

    private func mark(_ text: String) -> some View {
        // Vid största text står bocken vid rubriken i stället för mitt i den höga texten.
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            // Vit cirkel med grön bock på det gröna kortet, och grön cirkel med vit bock på en vanlig yta.
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    onCard ? Color.Theme.primary : Color.Theme.onPrimary,
                    onCard ? Color.Theme.onPrimary : Color.Theme.primary
                )
                .font(.system(.title2, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                title
                if let subtitle = line.placedOutSubtitle {
                    Text(subtitle)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(onCard ? foreground.opacity(0.85) : Color.Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.isPending ? "\(text), \(HouseholdTexts.pendingSubtitle)" : text)
        .accessibilityAction(named: HouseholdTexts.undo) { onUndo() }
    }

    /// "Utställt", med en klocka efter när bocken inte har skickats än. Vid största text står klockan i texten, så att den
    /// bryts med orden i stället för att ta en egen spalt.
    @ViewBuilder
    private var title: some View {
        let inlineClock = line.isPending && typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if inlineClock {
                    Text("\(line.placedOutTitle) \(Image(systemName: "clock"))")
                } else {
                    Text(line.placedOutTitle)
                }
            }
            .font(.ui(17, weight: .heavy, relativeTo: .headline))
            .foregroundStyle(foreground)
            .fixedSize(horizontal: false, vertical: true)
            if line.isPending, !inlineClock {
                Image(systemName: "clock")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(onCard ? foreground.opacity(0.85) : Color.Theme.text2)
            }
        }
    }

    /// En liten kapselknapp, som systemets. På det gröna kortet är den ljus.
    private func undoButton(fullWidth: Bool) -> some View {
        Button { onUndo() } label: {
            Text(HouseholdTexts.undo)
                .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(fullWidth ? .regular : .small)
        .tint(onCard ? Color.Theme.onPrimary : Color.Theme.primary)
        .accessibilityHint(HouseholdTexts.undoHint)
    }

    @ViewBuilder
    private var placeOutLabel: some View {
        if onCard {
            // En ljus knapp på det gröna kortet, så att den syns som en knapp och inte som text.
            Label(HouseholdTexts.placeOut, systemImage: "checkmark.circle")
                .font(.ui(17, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.brandText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 16)
                .background(Color.Theme.surface, in: Capsule())
        } else {
            PrimaryButtonLabel(title: HouseholdTexts.placeOut)
        }
    }
}
