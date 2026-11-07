import Foundation
import SophamtningKit

/// Tidslinjen när kalenderbladet bläddras, från ett datum till ett annat. Rena funktioner av tid, så att vyn ritar från klockan
/// och en ny bläddring kan ta över mitt i en gammal.
///
/// Ett blad bläddras per dag, högst 8 blad. Varje blad vänds på samma sätt: första halvan viker det gamla bladet upp till
/// 90 grader, och i andra halvan kommer det nya fram från 90 grader. Ett blad tar 0,6 s. Flera blad går fortare per blad och
/// bromsar in mot slutet, och allt är klart inom 1,2 s. Med Reducera rörelse tonas bladet i stället ut och in, en gång.
public enum CalendarFlipTimeline {
    /// Halva vändningen när bara ett blad vänds.
    public static let half: TimeInterval = 0.3
    /// Ett blad.
    public static let duration: TimeInterval = 0.6
    /// Den längsta bläddringen, med 8 blad eller fler dagar.
    public static let longest: TimeInterval = 1.2
    /// Fler dagar än så bläddras med jämnt fördelade datum.
    public static let maxPages = 8
    /// Hur mycket längre det sista bladet tar än det första.
    static let slowdown = 2.0

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

    /// Hela bläddringen: 0,6 s för ett blad, och för fler blad lite längre, men aldrig mer än 1,2 s.
    public static func duration(pages: Int) -> TimeInterval {
        pages <= 1 ? duration : longest - duration / Double(pages)
    }

    /// Vilket blad som vänds vid en tidpunkt, och hur långt det kommit (0 till 1). `nil` före och efter bläddringen.
    private static func flip(at elapsed: TimeInterval, pages: Int) -> (index: Int, progress: Double)? {
        let pages = max(pages, 1)
        let total = duration(pages: pages)
        guard elapsed > 0, elapsed < total else { return nil }
        // Varje blad tar lite längre tid än det förra, så att bläddringen bromsar in mot tömningsdagen.
        let weights = (0..<pages).map { pages == 1 ? 1 : 1 + (slowdown - 1) * Double($0) / Double(pages - 1) }
        let unit = total / weights.reduce(0, +)
        var start: TimeInterval = 0
        for (index, weight) in weights.enumerated() {
            let length = weight * unit
            if elapsed < start + length || index == pages - 1 {
                return (index, min(1, (elapsed - start) / length))
            }
            start += length
        }
        return nil
    }

    /// Hur många blad som har kommit fram: 0 visar startdatumet och `pages` det sista bladet. Bladet byts mitt i vändningen.
    public static func currentPage(at elapsed: TimeInterval, pages: Int) -> Int {
        if elapsed <= 0 { return 0 }
        guard let flip = flip(at: elapsed, pages: pages) else { return max(pages, 1) }
        return flip.progress < 0.5 ? flip.index : flip.index + 1
    }

    /// Datumet som syns: `from` tills första bladet är halvvägs, sedan bladen i `dates` i tur och ordning.
    public static func shownDate(at elapsed: TimeInterval, from: DayDate, dates: [DayDate]) -> DayDate {
        let page = min(currentPage(at: elapsed, pages: dates.count), dates.count)
        return page == 0 ? from : dates[page - 1]
    }

    /// Vinkel i grader runt bladets övre kant.
    public static func angle(at elapsed: TimeInterval, pages: Int = 1) -> Double {
        guard let flip = flip(at: elapsed, pages: pages) else { return 0 }
        let u = flip.progress
        if u < 0.5 {
            return -90 * CubicBezier.ease(0.42, 0, 1, 1).value(at: u / 0.5)
        }
        return 90 * (1 - CubicBezier.ease(0, 0, 0.58, 1).value(at: (u - 0.5) / 0.5))
    }

    /// Toningen vid Reducera rörelse, som alltid är ett blad: bort i första halvan och in i andra.
    public static func opacity(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < duration else { return 1 }
        let curve = CubicBezier.easeInOut
        if elapsed < half { return 1 - curve.value(at: elapsed / half) }
        return curve.value(at: (elapsed - half) / half)
    }

    public static func isFinished(at elapsed: TimeInterval, pages: Int = 1) -> Bool {
        elapsed >= duration(pages: pages)
    }
}
