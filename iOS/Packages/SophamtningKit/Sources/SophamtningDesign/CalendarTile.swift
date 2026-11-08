import SophamtningKit
import SwiftUI

/// Kalenderbricka: månad i versaler överst, dagens nummer och veckodagen helt utskriven.
///
/// Byter `date` värde bläddras bladen fram till det nya datumet som i en blockkalender, ett per dag och högst 8
/// (`CalendarFlipTimeline`), men inte när brickan visas första gången. Nästa blad ligger alltid under det som viks upp, så
/// att inget blinkar. Ett datum bakåt ger ett blad. Med Reducera rörelse tonas brickan i stället, en gång, utan vibration.
/// Kortets storlek påverkas inte, eftersom bara bladen vrids. Brickan måste behålla sin identitet i vyn för att kunna se
/// ändringen. I widgetar byts brickan ut med ny post och ingen animation sker.
///
/// Med `opening` visar brickan ett annat datum och bläddras till `date` vid en bestämd tidpunkt. Det används bara i hemkortet
/// vid start från början. Tillgänglighetsetiketten är `date` hela tiden, och månadsraden följer bladet.
public struct CalendarTile: View {
    let date: DayDate
    let opening: Opening?
    @ScaledMetric(relativeTo: .largeTitle) private var width: CGFloat = 78
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flip: Flip?
    /// Räknare som utlöser vibrationerna: en per blad och en när det sista har landat.
    @State private var pageTicks = 0
    @State private var landings = 0

    /// En pågående bläddring: datumet som visades när den började, och när den började.
    private struct Flip: Equatable {
        let from: DayDate
        let start: Date
    }

    /// Bläddringen vid start från början.
    public struct Opening: Equatable, Sendable {
        /// Datumet som syns tills bladet har vikts upp.
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

    /// Bläddringen som pågår: vid start eller efter ett ändrat datum.
    private var active: Flip? {
        if let opening, flip == nil {
            return opening.begin.map { Flip(from: opening.from, start: $0) }
        }
        return flip
    }

    private var ring: some View {
        Capsule()
            .fill(Color.Theme.text2)
            .frame(width: 4.5, height: 11)
            .overlay(Capsule().strokeBorder(Color.Theme.surface, lineWidth: 0.5))
    }

    public var body: some View {
        Group {
            if let active {
                flipping(from: active.from, begin: active.start)
            } else if let opening {
                sheet(opening.from)
            } else {
                sheet(date)
            }
        }
        .frame(width: width)
        .overlay(alignment: .top) {
            // Kalenderns två ringar, som i designen. De ligger över bladen som viks.
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
        .sensoryFeedback(.impact(weight: .light), trigger: pageTicks)
        .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: landings)
        .onChange(of: date) { old, _ in
            // Bläddringen vid start visar alltid det aktuella datumet som mål.
            guard opening == nil else { return }
            // Pågår redan en bläddring tas den över från bladet som ligger överst just nu.
            let now = Date()
            let visible = flip.map {
                CalendarFlipTimeline.shownDate(at: now.timeIntervalSince($0.start), from: $0.from, dates: dates(from: $0.from, to: old))
            } ?? old
            flip = Flip(from: visible, start: now)
        }
        .task(id: active) {
            guard let active else { return }
            let pages = dates(from: active.from, to: date).count
            // Vibrationerna följer bladen. De som redan passerat, om bläddringen tagits över, hoppas över.
            for haptic in CalendarFlipTimeline.haptics(pages: pages, reduceMotion: reduceMotion) {
                let wait = haptic.time - Date().timeIntervalSince(active.start)
                if wait < -0.05 { continue }
                if wait > 0 {
                    guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
                }
                switch haptic.kind {
                case .page: pageTicks += 1
                case .landing: landings += 1
                }
            }
            let rest = CalendarFlipTimeline.duration(pages: pages, reduceMotion: reduceMotion) - Date().timeIntervalSince(active.start)
            if rest > 0 {
                guard (try? await Task.sleep(for: .seconds(rest))) != nil else { return }
            }
            if flip == active { flip = nil }
        }
    }

    private func dates(from: DayDate, to: DayDate) -> [DayDate] {
        CalendarFlipTimeline.dates(from: from, to: to, reduceMotion: reduceMotion)
    }

    /// Bläddrar från `from` till `date`, med start vid `begin`.
    private func flipping(from: DayDate, begin: Date) -> some View {
        let dates = dates(from: from, to: date)
        let to = date
        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(begin)
            if reduceMotion {
                sheet(CalendarFlipTimeline.fadedDate(at: elapsed, from: from, to: to))
                    .opacity(CalendarFlipTimeline.opacity(at: elapsed))
            } else {
                let layers = CalendarFlipTimeline.layers(at: elapsed, pages: dates.count)
                ZStack {
                    // Bladet under ligger stilla, och bladen som viks ligger ovanpå, det äldsta överst.
                    sheet(CalendarFlipTimeline.date(ofSheet: layers.under, from: from, dates: dates))
                        .zIndex(-Double(layers.under))
                    ForEach(layers.folds, id: \.sheet) { fold in
                        sheet(CalendarFlipTimeline.date(ofSheet: fold.sheet, from: from, dates: dates))
                            // Bladet mörknar när det viks upp och vänder bort från ljuset.
                            .overlay(Color.black.opacity(0.25 * fold.progress).clipShape(shape))
                            .rotation3DEffect(
                                .degrees(CalendarFlipTimeline.angle(progress: fold.progress)),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .top,
                                perspective: 0.2
                            )
                            .shadow(color: .black.opacity(0.18 * (1 - fold.progress)), radius: 3, y: 2)
                            .zIndex(-Double(fold.sheet))
                    }
                }
            }
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    /// Ett blad med givet datum. Varje blad har egen form och kant, så att ett blad som viks kan gå utanför brickan.
    private func sheet(_ shown: DayDate) -> some View {
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
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.Theme.border))
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
