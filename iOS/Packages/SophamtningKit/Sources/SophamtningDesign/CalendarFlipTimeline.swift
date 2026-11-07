import Foundation
import SophamtningKit

/// Tidslinjen när kalenderbladet bläddras som en blockkalender, från ett datum till ett annat. Rena funktioner av tid, så att
/// vyn ritar från klockan och en ny bläddring kan ta över mitt i en gammal.
///
/// Bladen ligger i en bunt. Blad 0 är startdatumet och ligger överst, blad `n` är tömningsdagen och ligger underst. Bladen
/// 0 till `n - 1` viks upp kring överkanten, ett i taget men överlappande: ett nytt blad börjar cirka var 60:e ms, och
/// avståndet växer mot slutet, så att bläddringen bromsar in mot tömningsdagen. Nästa blad ligger alltid redan under det
/// som viks, så att inget blinkar. Ett blad tar 0,25 s och allt är klart inom 0,6 s. Med Reducera rörelse tonas brickan
/// i stället, en gång.
public enum CalendarFlipTimeline {
    /// Tiden ett blad tar att vikas upp.
    public static let foldDuration: TimeInterval = 0.25
    /// Tiden mellan de första bladen.
    public static let firstGap: TimeInterval = 0.06
    /// Hur mycket längre det sista mellanrummet är än det första.
    static let slowdown = 1.5
    /// Den längsta bläddringen, med 8 blad.
    public static let longest: TimeInterval = 0.6
    /// Fler dagar än så bläddras med jämnt fördelade datum.
    public static let maxPages = 8
    /// Toningen med Reducera rörelse: ut och sedan in.
    public static let fadeDuration: TimeInterval = 0.4

    /// Datumet bladet vänds från vid start från början: dagens datum, eller `nil` om tömningen är i dag och inget ska vändas.
    public static func openingDate(today: DayDate, pickup: DayDate) -> DayDate? {
        today == pickup ? nil : today
    }

    /// Bladen som bläddras fram, i ordning. Det sista är alltid `to`. Ett blad per dag, och vid fler än 8 dagar 8 jämnt
    /// fördelade datum. Ett datum bakåt, samma datum och Reducera rörelse ger ett enda blad.
    public static func dates(from: DayDate, to: DayDate, reduceMotion: Bool) -> [DayDate] {
        let days = from.days(until: to)
        guard !reduceMotion, days > 1 else { return [to] }
        if days <= maxPages { return (1...days).map { from.adding(days: $0) } }
        return (1...maxPages).map { from.adding(days: ($0 * days + maxPages / 2) / maxPages) }
    }

    /// När varje blad börjar vikas upp, räknat från bläddringens start. Det första börjar direkt.
    public static func starts(pages: Int) -> [TimeInterval] {
        let pages = max(pages, 1)
        guard pages > 1 else { return [0] }
        // Mellanrummen växer jämnt från det första till det sista, så att farten bromsar in.
        let weights = (0..<(pages - 1)).map { pages == 2 ? 1 : 1 + (slowdown - 1) * Double($0) / Double(pages - 2) }
        let gap = min(firstGap, (longest - foldDuration) / weights.reduce(0, +))
        var starts: [TimeInterval] = [0]
        for weight in weights { starts.append(starts.last! + weight * gap) }
        return starts
    }

    /// Hela bläddringen: tills det sista bladet har vikts upp och tömningsdagen ligger kvar. Med Reducera rörelse toningen.
    public static func duration(pages: Int, reduceMotion: Bool = false) -> TimeInterval {
        reduceMotion ? fadeDuration : starts(pages: pages).last! + foldDuration
    }

    public static func isFinished(at elapsed: TimeInterval, pages: Int, reduceMotion: Bool = false) -> Bool {
        elapsed >= duration(pages: pages, reduceMotion: reduceMotion)
    }

    /// Ett blad som håller på att vikas upp, och hur långt det kommit (0 till 1).
    public struct Fold: Equatable, Sendable {
        public let sheet: Int
        public let progress: Double
    }

    /// Bladen som syns vid en tidpunkt: bladet som ligger stilla under, och bladen ovanpå som viks upp.
    public struct Layers: Equatable, Sendable {
        /// Det översta bladet som inte har börjat vikas. Det ligger under alla som viks.
        public let under: Int
        /// Bladen som viks, överst först.
        public let folds: [Fold]

        /// Bladet som ligger överst i bunten.
        public var top: Int { folds.first?.sheet ?? under }
    }

    /// Vilka blad som syns vid en tidpunkt. Före starten ligger blad 0 ensamt, efter slutet blad `pages`.
    public static func layers(at elapsed: TimeInterval, pages: Int) -> Layers {
        let pages = max(pages, 1)
        let starts = starts(pages: pages)
        var folds: [Fold] = []
        var under = pages
        for (sheet, start) in starts.enumerated() {
            guard elapsed > start else {
                under = sheet
                break
            }
            if elapsed < start + foldDuration {
                folds.append(Fold(sheet: sheet, progress: (elapsed - start) / foldDuration))
            }
        }
        return Layers(under: under, folds: folds)
    }

    /// Datumet på ett blad: startdatumet för blad 0, och sedan bladen i `dates`.
    public static func date(ofSheet sheet: Int, from: DayDate, dates: [DayDate]) -> DayDate {
        sheet == 0 ? from : dates[min(sheet, dates.count) - 1]
    }

    /// Datumet på det översta bladet.
    public static func shownDate(at elapsed: TimeInterval, from: DayDate, dates: [DayDate]) -> DayDate {
        date(ofSheet: layers(at: elapsed, pages: dates.count).top, from: from, dates: dates)
    }

    /// Vinkeln i grader kring bladets överkant medan det viks upp: från 0 till 90, där det står på kanten och inte syns.
    /// Positiv vinkel för underkanten mot betraktaren, som när man lyfter ett blad i en blockkalender.
    public static func angle(progress: Double) -> Double {
        let u = min(max(progress, 0), 1)
        return 90 * CubicBezier.ease(0.45, 0, 0.75, 1).value(at: u)
    }

    /// Toningen vid Reducera rörelse: bort i första halvan och in i andra.
    public static func opacity(at elapsed: TimeInterval) -> Double {
        let half = fadeDuration / 2
        guard elapsed > 0, elapsed < fadeDuration else { return 1 }
        let curve = CubicBezier.easeInOut
        if elapsed < half { return 1 - curve.value(at: elapsed / half) }
        return curve.value(at: (elapsed - half) / half)
    }

    /// Datumet som syns vid Reducera rörelse: startdatumet tills brickan har tonats bort.
    public static func fadedDate(at elapsed: TimeInterval, from: DayDate, to: DayDate) -> DayDate {
        elapsed < fadeDuration / 2 ? from : to
    }

    /// En vibration under bläddringen.
    public struct Haptic: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Lätt, när ett blad börjar vikas.
            case page
            /// Tydligare, när det sista bladet har landat.
            case landing
        }

        public let time: TimeInterval
        public let kind: Kind
    }

    /// En lätt vibration per blad och en tydligare när tömningsdagen ligger kvar. Ingen med Reducera rörelse.
    public static func haptics(pages: Int, reduceMotion: Bool) -> [Haptic] {
        guard !reduceMotion else { return [] }
        return starts(pages: pages).map { Haptic(time: $0, kind: .page) } + [Haptic(time: duration(pages: pages), kind: .landing)]
    }
}
