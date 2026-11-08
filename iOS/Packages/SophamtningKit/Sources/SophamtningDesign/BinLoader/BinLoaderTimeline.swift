import Foundation

/// Tidslinjen för kärlets laddningsanimation. Allt är rena funktioner av tid, kopierade från CSS:en
/// `karl-gung`, `karl-lock`, `karl-bak`, `karl-fram`, `karl-fall` och `karl-text` i Sopors `index.html`.
/// Vyn ritar om från klockan, så ingen animationstillstånd behöver bevaras mellan bildrutor.
public enum BinLoaderTimeline {
    /// En slinga (`--p: 1.8s`).
    public static let period: TimeInterval = 1.8
    /// Fraktionerna cyklar över tre varv (`calc(var(--p) * 3)`).
    static let fractionCycle: TimeInterval = period * 3
    /// Texten står i 3,6 sekunder (`karl-text 3.6s`), med 15 % toning in och ut, alltså 0,54 s.
    public static let textPeriod: TimeInterval = 3.6
    /// Fördröjningen innan allt tonar in, och hur länge toningen tar (`karl-in .25s ease-out .3s`).
    public static let appearDelay: TimeInterval = 0.3
    public static let appearDuration: TimeInterval = 0.25

    /// Hur långt in i slingan (0 till under 1) en tidpunkt är.
    public static func progress(at elapsed: TimeInterval) -> Double {
        let value = elapsed.truncatingRemainder(dividingBy: period) / period
        return value < 0 ? value + 1 : value
    }

    // MARK: Lock och kropp

    /// Lockets vinkel i grader runt gångjärnet (`karl-lock`). `progress` är 0 till 1 genom slingan.
    public static func lidAngle(at progress: Double) -> Double {
        let p = clamp(progress)
        let slow = CubicBezier.ease(0.2, 0.8, 0.3, 1)
        let inOut = CubicBezier.easeInOut
        let close = CubicBezier.ease(0.6, 0, 1, 0.6)
        switch p {
        case ..<0.14: return 0
        case ..<0.30: return interpolate(0, 38, p, 0.14, 0.30, slow)
        case ..<0.38: return interpolate(38, 33, p, 0.30, 0.38, inOut)
        case ..<0.58: return 33
        case ..<0.67: return interpolate(33, 0, p, 0.58, 0.67, close)
        default: return 0
        }
    }

    /// Locket ligger bakom kroppen när det är öppet och framför när det är stängt (`karl-bak` och `karl-fram`,
    /// båda `step-end`): bakom från 16 % till 66 %.
    public static func lidIsBehindBody(at progress: Double) -> Bool {
        let p = clamp(progress)
        return p >= 0.16 && p < 0.66
    }

    /// Kroppens gungning i grader runt hjulens mitt (`karl-gung`, `ease-in-out` i varje steg).
    public static func bodySway(at progress: Double) -> Double {
        let p = clamp(progress)
        let e = CubicBezier.easeInOut
        switch p {
        case ..<0.14: return 0
        case ..<0.30: return interpolate(0, -3, p, 0.14, 0.30, e)
        case ..<0.62: return -3
        case ..<0.72: return interpolate(-3, 3, p, 0.62, 0.72, e)
        case ..<0.82: return interpolate(3, -1.5, p, 0.72, 0.82, e)
        case ..<0.91: return interpolate(-1.5, 0.5, p, 0.82, 0.91, e)
        default: return interpolate(0.5, 0, p, 0.91, 1, e)
        }
    }

    // MARK: Fraktionen

    /// En fraktions läge: `x` och `y` är förskjutningen i SVG:ns enheter, `rotation` i grader runt SVG:ns origo.
    public struct FractionState: Equatable, Sendable {
        /// 0, 1, 2: rest, papper och plast följer ordningen mat, papper, plast som på webben.
        public let index: Int
        public let opacity: Double
        public let x: Double
        public let y: Double
        public let rotation: Double
    }

    /// Fraktionen som hör till tidpunkten (`karl-fall`). Varje fraktion har en cykel på tre varv och startar ett
    /// varv efter den förra, så varje varv visas en ny. `elapsed` är sekunder sedan animationen startade.
    public static func fractionState(at elapsed: TimeInterval) -> FractionState {
        let loop = max(0, Int((elapsed / period).rounded(.down)))
        let index = loop % 3
        // Fraktionens egen tid i cykeln: den startade vid början av sitt varv.
        let local = elapsed - Double(loop) * period
        let u = max(0, local) / fractionCycle
        let start = (x: 172.0, y: -96.0, r: -8.0)
        let end = (x: 172.0, y: 140.0, r: 6.0)
        func make(_ opacity: Double, _ x: Double, _ y: Double, _ r: Double) -> FractionState {
            FractionState(index: index, opacity: opacity, x: x, y: y, rotation: r)
        }
        switch u {
        case ..<0.09:
            return make(0, start.x, start.y, start.r)
        case ..<0.11:
            // Linjär toning in (animation-timing-function: linear).
            return make(interpolate(0, 1, u, 0.09, 0.11, CubicBezier.linear), start.x, start.y, start.r)
        case ..<0.13:
            return make(1, start.x, start.y, start.r)
        case ..<0.20:
            let t = CubicBezier.ease(0.5, 0, 1, 0.7).value(at: (u - 0.13) / 0.07)
            return make(1, start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t, start.r + (end.r - start.r) * t)
        case ..<0.205:
            return make(interpolate(1, 0, u, 0.20, 0.205, CubicBezier.linear), end.x, end.y, end.r)
        default:
            return make(0, end.x, end.y, end.r)
        }
    }

    // MARK: Hela kärlet i en bild

    /// Kärlets läge i en bild: locket, om det ligger bakom kroppen, gungningen och fraktionen.
    public struct Pose: Equatable, Sendable {
        public let lidAngle: Double
        public let lidIsBehindBody: Bool
        public let bodySway: Double
        public let fraction: FractionState

        /// Stilla med stängt lock och utan fraktion.
        public static let resting = Pose(
            lidAngle: 0,
            lidIsBehindBody: false,
            bodySway: 0,
            fraction: FractionState(index: 0, opacity: 0, x: 0, y: 0, rotation: 0)
        )
    }

    /// Slingans läge, `elapsed` sekunder efter att den startade.
    public static func loopPose(at elapsed: TimeInterval) -> Pose {
        let p = progress(at: elapsed)
        return Pose(lidAngle: lidAngle(at: p), lidIsBehindBody: lidIsBehindBody(at: p), bodySway: bodySway(at: p), fraction: fractionState(at: elapsed))
    }

    // MARK: Ett varv i tomt läge

    /// Ett varv i tomt läge är lika långt som ett varv i slingan.
    public static let roundDuration: TimeInterval = period

    /// Sant medan ett varv pågår, `elapsed` sekunder efter att det startade. Med Reducera rörelse spelas inget varv.
    public static func isPlayingRound(elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        !reduceMotion && elapsed >= 0 && elapsed < roundDuration
    }

    /// Kärlets läge under ett varv. `round` räknar varven och ger fraktionen, så att varje varv visar nästa.
    /// Före och efter varvet, och med Reducera rörelse, står kärlet stilla med stängt lock.
    public static func roundPose(round: Int, elapsed: TimeInterval, reduceMotion: Bool) -> Pose {
        guard isPlayingRound(elapsed: elapsed, reduceMotion: reduceMotion) else { return .resting }
        // Samma bild som slingans varv nummer `round`, så att fraktionen byts likadant.
        return loopPose(at: Double(max(round, 0)) * period + elapsed)
    }

    // MARK: Text och inträde

    /// Textens opacitet (`karl-text`: 0 till 1 vid 15 %, 1 till 0 från 85 %, `ease-in-out`).
    public static func textOpacity(at elapsed: TimeInterval) -> Double {
        let u = elapsed.truncatingRemainder(dividingBy: textPeriod) / textPeriod
        let e = CubicBezier.easeInOut
        switch u {
        case ..<0.15: return interpolate(0, 1, u, 0, 0.15, e)
        case ..<0.85: return 1
        default: return interpolate(1, 0, u, 0.85, 1, e)
        }
    }

    /// Vilken text som gäller: byts varje gång textens cykel börjar om (som `animationiteration` på webben).
    public static func textCycle(at elapsed: TimeInterval) -> Int {
        max(0, Int((elapsed / textPeriod).rounded(.down)))
    }

    /// Hela animationens opacitet: osynlig i 300 ms och sedan 0,25 s `ease-out`, så att snabba svar inte blinkar.
    public static func appearOpacity(at elapsed: TimeInterval) -> Double {
        let t = (elapsed - appearDelay) / appearDuration
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return CubicBezier.ease(0, 0, 0.58, 1).value(at: t)
    }

    // MARK: Hjälpmedel

    private static func clamp(_ p: Double) -> Double { min(max(p, 0), 1) }

    private static func interpolate(_ from: Double, _ to: Double, _ p: Double, _ p0: Double, _ p1: Double, _ curve: CubicBezier) -> Double {
        let t = curve.value(at: (p - p0) / (p1 - p0))
        // Exakta ändpunkter, utan avrundningsfel från kurvan.
        if t <= 0 { return from }
        if t >= 1 { return to }
        return from + (to - from) * t
    }
}

/// CSS `cubic-bezier(x1, y1, x2, y2)`: ger framsteget för en andel av tiden.
struct CubicBezier: Sendable {
    let x1, y1, x2, y2: Double

    static let linear = CubicBezier(x1: 0, y1: 0, x2: 1, y2: 1)
    /// CSS `ease-in-out`.
    static let easeInOut = CubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    static func ease(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> CubicBezier {
        CubicBezier(x1: x1, y1: y1, x2: x2, y2: y2)
    }

    func value(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return x }
        // Hitta parametern t där bezierns x är `x` (Newton, med halvering som reserv), och ge y.
        var t = x
        for _ in 0..<8 {
            let error = sample(t, x1, x2) - x
            if abs(error) < 1e-7 { return sample(t, y1, y2) }
            let slope = derivative(t, x1, x2)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<40 {
            let current = sample(t, x1, x2)
            if abs(current - x) < 1e-7 { break }
            if current < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, y1, y2)
    }

    private func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let s = 1 - t
        return 3 * s * s * t * a + 3 * s * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let s = 1 - t
        return 3 * s * s * a + 6 * s * t * (b - a) + 3 * t * t * (1 - b)
    }
}
