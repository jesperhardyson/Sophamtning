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
                // Rubriken ligger bredvid kameran. Den nedre regionen har ungefär 90 pt i höjd, så knappen och fraktionerna
                // går före varningen, som alltid syns i sin helhet på låsskärmen.
                DynamicIslandExpandedRegion(.leading) {
                    Text(PickupActivityContent.alertTitle)
                        .font(.ui(16, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(content.shortDate)
                        .font(.ui(14, weight: .heavy, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(content.fractionsLine)
                            .font(.ui(14, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        WarningLine(content: content, lineLimit: 1)
                        PlacedOutButton(attributes: context.attributes, fullWidth: true, height: 34)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                FractionChips(content: content)
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

/// Alla fraktioner syns alltid med namn. Får de inte plats som chips på en rad visas de som text, inom systemets höjdgräns.
private struct FractionChips: View {
    let content: PickupActivityContent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(content.fractions, id: \.id) { fraction in
                    FractionChip(id: fraction.id, info: FractionInfo(name: fraction.name, short: fraction.short, color: fraction.color, icon: fraction.icon))
                        .fixedSize()
                        // Chipsen är ljusa enligt designen, på den mörka bakgrunden.
                        .environment(\.colorScheme, .light)
                }
            }
            Text(content.fractionNames)
                .font(.ui(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.fractions.map(\.name).joined(separator: ", "))
    }
}

private struct PlacedOutButton: View {
    let attributes: PickupActivityAttributes
    let fullWidth: Bool
    var height: CGFloat = 40

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
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(ThemeToken.primary.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
