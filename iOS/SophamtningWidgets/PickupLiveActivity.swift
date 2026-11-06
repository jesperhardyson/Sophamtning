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
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    Text(PickupActivityContent.alertTitle)
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(content.shortDate)
                        .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(content.fractionsLine)
                            .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                        WarningLine(content: content)
                        PlacedOutButton(attributes: context.attributes, fullWidth: true)
                    }
                    .padding(.horizontal, 6)
                    .environment(\.colorScheme, .dark)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }
            } compactLeading: {
                BinGlyph()
                    .foregroundStyle(ThemeToken.primary.color)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(PickupActivityContent.alertTitle)
            } compactTrailing: {
                Text(content.compactDate)
                    .font(.ui(13, weight: .heavy, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            } minimal: {
                BinGlyph()
                    .foregroundStyle(ThemeToken.primary.color)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(PickupActivityContent.alertTitle)
            }
            .keylineTint(ThemeToken.primary.color)
        }
    }
}

/// Låsskärmen. Systemet ger högst 160 pt i höjd, så varningen får två rader och chipsen en.
private struct LockScreenPickup: View {
    let attributes: PickupActivityAttributes
    let content: PickupActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ActivityAppIcon()
                VStack(alignment: .leading, spacing: 1) {
                    Text(PickupActivityContent.alertTitle)
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(.white)
                    Text(content.subtitle)
                        .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            WarningLine(content: content)
            HStack(spacing: 8) {
                FractionChips(fractions: content.fractions)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlacedOutButton(attributes: attributes, fullWidth: false)
                    .layoutPriority(1)
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}

/// Varningen från källan, när den finns.
private struct WarningLine: View {
    let content: PickupActivityContent

    var body: some View {
        if let warning = content.warning {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text(warning)
                    .font(.ui(13, weight: .bold, relativeTo: .footnote))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ThemeToken.warn.color)
        }
    }
}

/// Fraktionerna med färg, ikon och text. Får hela namnen inte plats används korta namn, och sedan så många som ryms.
private struct FractionChips: View {
    let fractions: [ActivityFraction]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(fractions, short: false, hidden: 0)
            row(fractions, short: true, hidden: 0)
            if fractions.count > 2 {
                row(Array(fractions.prefix(2)), short: true, hidden: fractions.count - 2)
            }
            row(Array(fractions.prefix(1)), short: true, hidden: fractions.count - 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fractions.map(\.name).joined(separator: ", "))
    }

    private func row(_ shown: [ActivityFraction], short: Bool, hidden: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(shown, id: \.id) { fraction in
                FractionChip(id: fraction.id, info: FractionInfo(name: short ? fraction.short : fraction.name, short: fraction.short, color: fraction.color, icon: fraction.icon))
                    .fixedSize()
                    // Chipsen är ljusa enligt designen, på den mörka bakgrunden.
                    .environment(\.colorScheme, .light)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.ui(14, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
    }
}

private struct PlacedOutButton: View {
    let attributes: PickupActivityAttributes
    let fullWidth: Bool

    var body: some View {
        Button(intent: MarkPlacedOutIntent(key: attributes.key, pickupDate: attributes.pickupDate)) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text("Utställt")
                    .font(.ui(17, weight: .heavy, relativeTo: .headline))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(ThemeToken.onPrimary.color)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
            .background(ThemeToken.primary.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
