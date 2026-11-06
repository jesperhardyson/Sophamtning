import SophamtningKit
import SwiftUI

/// Kalenderbricka: månad i versaler överst, dagens nummer och veckodagen helt utskriven.
public struct CalendarTile: View {
    let date: DayDate

    public init(date: DayDate) {
        self.date = date
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(SwedishFormat.monthUppercased(date))
                .font(.ui(12, weight: .heavy, relativeTo: .caption))
                .foregroundStyle(Color.Theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Color.Theme.primary)
            VStack(spacing: 0) {
                Text(SwedishFormat.dayNumber(date))
                    .font(.brand(38, relativeTo: .largeTitle))
                    .foregroundStyle(Color.Theme.text)
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
        .frame(width: 78)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.Theme.border))
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
