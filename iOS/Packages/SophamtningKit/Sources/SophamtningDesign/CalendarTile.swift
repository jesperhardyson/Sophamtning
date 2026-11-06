import SophamtningKit
import SwiftUI

/// Kalenderbricka: månad i versaler överst, dagens nummer och veckodagen helt utskriven.
public struct CalendarTile: View {
    let date: DayDate
    @ScaledMetric(relativeTo: .largeTitle) private var width: CGFloat = 78
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 26

    public init(date: DayDate) {
        self.date = date
    }

    private var ring: some View {
        Capsule()
            .fill(Color.Theme.text2)
            .frame(width: 4.5, height: 11)
            .overlay(Capsule().strokeBorder(Color.Theme.surface, lineWidth: 0.5))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(SwedishFormat.monthUppercased(date))
                .font(.ui(12, weight: .heavy, relativeTo: .caption))
                .foregroundStyle(Color.Theme.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: headerHeight)
                .background(Color.Theme.primary)
            VStack(spacing: 0) {
                Text(SwedishFormat.dayNumber(date))
                    .font(.brand(38, relativeTo: .largeTitle))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(SwedishFormat.weekdayName(date))
                    .font(.ui(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Color.Theme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.Theme.surface)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.Theme.border))
        .overlay(alignment: .top) {
            // Kalenderns två ringar, som i designen.
            HStack(spacing: 0) {
                ring
                Spacer(minLength: 0)
                ring
            }
            .padding(.horizontal, width * 0.28)
            .offset(y: -3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SwedishFormat.longDate(date, capitalized: false))
    }
}

#Preview("Kalenderbricka") {
    HStack(spacing: 16) {
        CalendarTile(date: DayDate("2026-11-09")!)
        CalendarTile(date: DayDate("2026-12-24")!)
    }
    .padding()
    .background(Color.Theme.bg)
}

#Preview("Kalenderbricka mörkt") {
    CalendarTile(date: DayDate("2026-11-09")!)
        .padding()
        .background(Color.Theme.bg)
        .preferredColorScheme(.dark)
}
