import Foundation

/// Tidslinjen för pratbubblan som kommer från kärlet vid ett tryck. Rena funktioner av tid, som `BinLoaderTimeline`.
/// Bubblan tonas in, svävar uppåt och tonas bort, cirka 2 sekunder i allt. Med Reducera rörelse tonas den bara in och
/// ut på plats.
public enum BinBubbleTimeline {
    /// Hur länge bubblan syns.
    public static let duration: TimeInterval = 2
    /// Toningen in, och samtidigt växer den till full storlek.
    public static let fadeIn: TimeInterval = 0.2
    /// Toningen bort, sist.
    public static let fadeOut: TimeInterval = 0.5
    /// Hur långt bubblan svävar uppåt, i punkter, under hela tiden.
    public static let riseDistance: Double = 28
    /// Storleken när bubblan börjar tonas in.
    static let startScale: Double = 0.85

    /// Sant medan bubblan syns, `elapsed` sekunder efter trycket.
    public static func isShowing(elapsed: TimeInterval) -> Bool {
        elapsed >= 0 && elapsed < duration
    }

    public static func opacity(at elapsed: TimeInterval) -> Double {
        guard isShowing(elapsed: elapsed) else { return 0 }
        if elapsed < fadeIn { return CubicBezier.ease(0, 0, 0.58, 1).value(at: elapsed / fadeIn) }
        let left = duration - elapsed
        if left < fadeOut { return CubicBezier.easeInOut.value(at: left / fadeOut) }
        return 1
    }

    /// Hur långt upp bubblan har svävat, i punkter. Snabbast i början och mjukt mot slutet.
    public static func rise(at elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let t = min(max(elapsed / duration, 0), 1)
        return riseDistance * CubicBezier.ease(0.2, 0.6, 0.4, 1).value(at: t)
    }

    public static func scale(at elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let t = min(max(elapsed / fadeIn, 0), 1)
        return startScale + (1 - startScale) * CubicBezier.ease(0, 0, 0.58, 1).value(at: t)
    }

    /// Var bubblan står i förhållande till kärlet.
    public enum Placement: Sendable {
        /// Spetsen strax ovanför locket, i den tomma ytan där fraktionen faller. För det stora kärlet i tomt läge.
        case overLid
        /// Spetsen ovanför kärlets hela ram. För det lilla kärlet bredvid rubriken, där texten når högre än locket.
        case aboveBin
    }

    /// Luften mellan spetsen och det den pekar på, i punkter.
    static let tipGap: Double = 4

    /// Var spetsen står, i punkter från kärlets överkant (negativt är ovanför). Bubblan växer uppåt därifrån, så att
    /// den aldrig täcker kärlet, hur många rader den än har. Locket börjar vid y 150 i kärlets 360 × 560 (y 40 i
    /// SVG:ns viewBox, som börjar vid y -110).
    public static func tipY(binWidth: Double, placement: Placement) -> Double {
        switch placement {
        case .overLid: binWidth * 150 / 360 - tipGap
        case .aboveBin: -tipGap
        }
    }

    /// Om ett tryck på kärlet tas emot. Under ett varv gör trycket inget, och det finns bara en bubbla åt gången.
    /// Med Reducera rörelse spelas inget varv, så bara bubblan räknas.
    /// - Parameters:
    ///   - roundElapsed: Sekunder sedan det senaste varvet startade, eller `nil` om inget har spelats.
    ///   - bubbleElapsed: Sekunder sedan den senaste bubblan visades, eller `nil`.
    public static func acceptsTap(roundElapsed: TimeInterval?, bubbleElapsed: TimeInterval?, reduceMotion: Bool) -> Bool {
        if let roundElapsed, BinLoaderTimeline.isPlayingRound(elapsed: roundElapsed, reduceMotion: reduceMotion) { return false }
        if let bubbleElapsed, isShowing(elapsed: bubbleElapsed) { return false }
        return true
    }
}
