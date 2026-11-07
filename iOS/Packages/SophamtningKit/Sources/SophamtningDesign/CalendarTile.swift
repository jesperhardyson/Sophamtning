import SophamtningKit
import SwiftUI

/// Kalenderbricka: månad i versaler överst, dagens nummer och veckodagen helt utskriven.
///
/// Byter `date` värde vänds bladet (`CalendarFlipTimeline`), men inte när brickan visas första gången. Med Reducera rörelse
/// tonas bladet i stället. Kortets storlek påverkas inte, eftersom bara innehållet vrids. Brickan måste behålla sin identitet
/// i vyn för att kunna se ändringen. I widgetar byts brickan ut med ny post och ingen animation sker.
public struct CalendarTile: View {
    let date: DayDate
    @ScaledMetric(relativeTo: .largeTitle) private var width: CGFloat = 78
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flip: Flip?

    /// En pågående vändning: datumet som visades när den började, och när den började.
    private struct Flip: Equatable {
        let from: DayDate
        let start: Date
    }

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
        Group {
            if let flip {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(flip.start)
                    page(showing: CalendarFlipTimeline.showsNewDate(at: elapsed) ? date : flip.from, elapsed: elapsed)
                }
            } else {
                page(showing: date, elapsed: nil)
            }
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
        .onChange(of: date) { old, _ in
            // Visas redan en vändning tas den över från det datum som syns just nu.
            let visible = flip.map { CalendarFlipTimeline.showsNewDate(at: Date().timeIntervalSince($0.start)) ? old : $0.from } ?? old
            flip = Flip(from: visible, start: Date())
        }
        .task(id: flip) {
            guard flip != nil else { return }
            try? await Task.sleep(for: .seconds(CalendarFlipTimeline.duration))
            if !Task.isCancelled { flip = nil }
        }
    }

    /// Bladet med givet datum. `elapsed` är tiden i vändningen, eller `nil` när inget vänds.
    private func page(showing shown: DayDate, elapsed: TimeInterval?) -> some View {
        VStack(spacing: 0) {
            Text(SwedishFormat.monthUppercased(shown))
                .font(.ui(12, weight: .heavy, relativeTo: .caption))
                .foregroundStyle(Color.Theme.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: headerHeight)
                .background(Color.Theme.primary)
            VStack(spacing: 0) {
                Text(SwedishFormat.dayNumber(shown))
                    .font(.brand(38, relativeTo: .largeTitle))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(SwedishFormat.weekdayName(shown))
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
        .rotation3DEffect(.degrees(reduceMotion ? 0 : elapsed.map(CalendarFlipTimeline.angle(at:)) ?? 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        .opacity(reduceMotion ? elapsed.map(CalendarFlipTimeline.opacity(at:)) ?? 1 : 1)
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
