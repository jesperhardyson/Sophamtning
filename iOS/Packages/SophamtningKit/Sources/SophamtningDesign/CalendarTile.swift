import SophamtningKit
import SwiftUI

/// Kalenderbricka: månad i versaler överst, dagens nummer och veckodagen helt utskriven.
///
/// Byter `date` värde bläddras bladen fram till det nya datumet, ett per dag och högst 8 (`CalendarFlipTimeline`), men inte
/// när brickan visas första gången. Ett datum bakåt ger ett blad. Med Reducera rörelse tonas bladet i stället, en gång.
/// Kortets storlek påverkas inte, eftersom bara innehållet vrids. Brickan måste behålla sin identitet
/// i vyn för att kunna se ändringen. I widgetar byts brickan ut med ny post och ingen animation sker.
///
/// Med `opening` visar brickan ett annat datum och bläddras till `date` vid en bestämd tidpunkt. Det används bara i hemkortet
/// vid start från början. Tillgänglighetsetiketten är `date` hela tiden, och månadsraden följer bladet som syns.
public struct CalendarTile: View {
    let date: DayDate
    let opening: Opening?
    @ScaledMetric(relativeTo: .largeTitle) private var width: CGFloat = 78
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flip: Flip?

    /// En pågående bläddring: datumet som visades när den började, och när den började.
    private struct Flip: Equatable {
        let from: DayDate
        let start: Date
    }

    /// Bläddringen vid start från början.
    public struct Opening: Equatable, Sendable {
        /// Datumet som syns tills första bladet är halvvägs.
        public let from: DayDate
        /// När bläddringen börjar, eller `nil` om det inte är bestämt än.
        public let begin: Date?

        public init(from: DayDate, begin: Date?) {
            self.from = from
            self.begin = begin
        }
    }

    public init(date: DayDate, opening: Opening? = nil) {
        self.date = date
        self.opening = opening
    }

    private var ring: some View {
        Capsule()
            .fill(Color.Theme.text2)
            .frame(width: 4.5, height: 11)
            .overlay(Capsule().strokeBorder(Color.Theme.surface, lineWidth: 0.5))
    }

    public var body: some View {
        Group {
            if let opening, flip == nil {
                if let begin = opening.begin {
                    flipping(from: opening.from, begin: begin)
                } else {
                    page(showing: opening.from, elapsed: nil, pages: 1)
                }
            } else if let flip {
                flipping(from: flip.from, begin: flip.start)
            } else {
                page(showing: date, elapsed: nil, pages: 1)
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
            // Bläddringen vid start visar alltid det aktuella datumet som mål.
            guard opening == nil else { return }
            // Pågår redan en bläddring tas den över från det datum som syns just nu.
            let now = Date()
            let visible = flip.map {
                CalendarFlipTimeline.shownDate(at: now.timeIntervalSince($0.start), from: $0.from, dates: dates(from: $0.from, to: old))
            } ?? old
            flip = Flip(from: visible, start: now)
        }
        .task(id: flip) {
            guard let flip else { return }
            let pages = dates(from: flip.from, to: date).count
            try? await Task.sleep(for: .seconds(CalendarFlipTimeline.duration(pages: pages)))
            if !Task.isCancelled { self.flip = nil }
        }
    }

    private func dates(from: DayDate, to: DayDate) -> [DayDate] {
        CalendarFlipTimeline.dates(from: from, to: to, reduceMotion: reduceMotion)
    }

    /// Bläddrar från `from` till `date`, med start vid `begin`.
    private func flipping(from: DayDate, begin: Date) -> some View {
        let dates = dates(from: from, to: date)
        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(begin)
            page(showing: CalendarFlipTimeline.shownDate(at: elapsed, from: from, dates: dates), elapsed: elapsed, pages: dates.count)
        }
    }

    /// Bladet med givet datum. `elapsed` är tiden i bläddringen, eller `nil` när inget bläddras.
    private func page(showing shown: DayDate, elapsed: TimeInterval?, pages: Int) -> some View {
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
        .rotation3DEffect(.degrees(reduceMotion ? 0 : elapsed.map { CalendarFlipTimeline.angle(at: $0, pages: pages) } ?? 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
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
