import ActivityKit
import AppIntents
import SophamtningDesign
import SophamtningKit
import SwiftUI
import WidgetKit

/// Mörk grön bakgrund enligt designen. Allt utom fraktionschipsen ritas i mörkt läge, oavsett telefonens läge.
private let activityBackground = Color(red: 0x0F / 255, green: 0x2E / 255, blue: 0x1E / 255)

struct PickupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in
            LockScreenPickup(attributes: context.attributes, content: context.state)
                .activityBackgroundTint(activityBackground)
                .activitySystemActionForegroundColor(.white)
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(...DynamicTypeSize.large)
        } dynamicIsland: { context in
            let content = context.state
            return DynamicIsland {
                // Rubriken ligger bredvid kameran. Den nedre regionen har ungefär 90 pt i höjd. Samma regel som på låsskärmen:
                // fraktionerna och knappen går före varningen, som får en rad och hellre kapas.
                DynamicIslandExpandedRegion(.leading) {
                    Text(content.title)
                        .font(.ui(16, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 6)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(content.shortDate)
                        .font(.ui(14, weight: .heavy, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        // Utställt: vem och när i stället för adressen, när det är känt.
                        Text(content.placedOutDetail ?? content.addressName)
                            .font(.ui(14, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        WarningLine(content: content, lineLimit: 1)
                        HStack(spacing: 8) {
                            FractionChips(content: content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PlacedOutControl(attributes: context.attributes, content: content)
                                .layoutPriority(1)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    // De rundade hörnen klipper annars rubriken och nedersta chipset.
                    .padding(.horizontal, 6)
                    .environment(\.colorScheme, .dark)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }
            } compactLeading: {
                ActivityGlyph(placedOut: content.placedOut)
            } compactTrailing: {
                Text(content.compactDate)
                    .font(.ui(13, weight: .heavy, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            } minimal: {
                ActivityGlyph(placedOut: content.placedOut)
            }
            .keylineTint(ThemeToken.primary.color)
        }
    }
}

/// Låsskärmen. Systemet ger högst 160 pt i höjd. Rubriken, datumet, chipsen och knappen behåller sin höjd, och varningen får det
/// som blir över: två rader med en rad chips, annars en rad, och den kapas hellre än att något annat försvinner.
private struct LockScreenPickup: View {
    let attributes: PickupActivityAttributes
    let content: PickupActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if content.placedOut {
                    // Klart: en fylld bock i appikonens storlek, så att det inte ser ut som något kvar att göra.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(ThemeToken.primary.color)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                } else {
                    ActivityAppIcon()
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.title)
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(.white)
                    Text(content.detailLine)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            WarningLine(content: content, lineLimit: content.warningLineLimit)
                .layoutPriority(-1)
            HStack(spacing: 8) {
                FractionChips(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlacedOutControl(attributes: attributes, content: content)
                    .layoutPriority(1)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

/// Varningen från källan, när den finns.
private struct WarningLine: View {
    let content: PickupActivityContent
    var lineLimit = 2

    var body: some View {
        if let warning = content.warning {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text(warning)
                    .font(.ui(13, weight: .bold, relativeTo: .footnote))
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ThemeToken.warn.color)
        }
    }
}

/// Alla fraktioner med färg, ikon och kort namn, på högst två rader. Det är enda layouten.
private struct FractionChips: View {
    let content: PickupActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: ActivityChipMetrics.spacing) {
            ForEach(Array(content.fractionRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: ActivityChipMetrics.spacing) {
                    ForEach(row, id: \.id) { fraction in
                        FractionChip(id: fraction.id, info: FractionInfo(name: fraction.short, short: fraction.short, color: fraction.color, icon: fraction.icon), compact: true)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        // Chipsen är ljusa enligt designen, på den mörka bakgrunden.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.fractions.map(\.name).joined(separator: ", "))
    }
}

/// Knappen **Klart** med en tom ring, som en bock att kryssa i. När kärlen är utställda finns ingen knapp: rubriken säger det.
private struct PlacedOutControl: View {
    let attributes: PickupActivityAttributes
    let content: PickupActivityContent
    var height: CGFloat = 40

    var body: some View {
        if !content.placedOut {
            Button(intent: MarkPlacedOutIntent(key: attributes.key, pickupDate: attributes.pickupDate)) {
                HStack(spacing: 6) {
                    Image(systemName: "circle")
                        .font(.system(size: 16, weight: .bold))
                        .accessibilityHidden(true)
                    Text(PickupActivityContent.doneButton)
                        .font(.ui(17, weight: .heavy, relativeTo: .headline))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(ThemeToken.onPrimary.color)
                .padding(.horizontal, 14)
                .frame(minHeight: height)
                .background(ThemeToken.primary.color, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PickupActivityContent.placedOutTitle)
        }
    }
}

/// Kärlet i kompakta och minimala Dynamic Island, och en bock när Utställt är tryckt.
private struct ActivityGlyph: View {
    let placedOut: Bool

    var body: some View {
        Group {
            if placedOut {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
            } else {
                BinGlyph()
            }
        }
        .foregroundStyle(ThemeToken.primary.color)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(placedOut ? PickupActivityContent.placedOutTitle : PickupActivityContent.alertTitle)
    }
}

// MARK: Förhandsvisning

/// Sex fraktioner och varning, det största innehållet som finns i dag.
private let sixFractions = PickupActivityContent(
    addressName: "Hemma",
    dateText: "Måndag 9 november",
    shortDateText: "Mån 9 nov",
    fractions: [
        ("rest", "Rest"), ("mat", "Mat"), ("papper", "Papper"), ("plast", "Plast"), ("glas", "Glas"), ("metall", "Metall"),
    ].map { ActivityFraction(id: $0.0, name: $0.1, short: $0.1, color: "#111111", icon: "trash-2") },
    estimated: true,
    warning: "Hämtning på helgdag. Kontrollera datum och tid med kommunen, eftersom tömningen kan flyttas med kort varsel."
)

private func lockPreview(width: CGFloat) -> some View {
    LockScreenPickup(attributes: PickupActivityAttributes(key: AddressKey(source: "a", id: "b"), pickupDate: DayDate("2026-11-09")!, start: Date()), content: sixFractions)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: 160)
        .background(activityBackground)
        .environment(\.colorScheme, .dark)
}

private let placedOutSixFractions = sixFractions.markedPlacedOut(detail: "av Sofie · kl. 19:42")

#Preview("Utställda, 375 pt") {
    LockScreenPickup(attributes: PickupActivityAttributes(key: AddressKey(source: "a", id: "b"), pickupDate: DayDate("2026-11-09")!, start: Date()), content: placedOutSixFractions)
        .frame(width: 345, alignment: .leading)
        .frame(maxHeight: 160)
        .background(activityBackground)
        .environment(\.colorScheme, .dark)
}

// Kortet är telefonens bredd minus 30 pt i marginaler.
#Preview("Sex fraktioner, 375 pt") { lockPreview(width: 345) }
#Preview("Sex fraktioner, 402 pt") { lockPreview(width: 372) }
