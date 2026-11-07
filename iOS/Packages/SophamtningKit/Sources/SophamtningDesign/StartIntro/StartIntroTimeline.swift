import Foundation

/// Tidslinjen för introt direkt efter startskärmen. Allt är rena funktioner av tid, så att vyn kan rita om från klockan.
///
/// Första bilden är exakt startskärmen: logotypen i naturlig storlek (skala 1) utan toning, på appens bakgrundsfärg. Sedan
/// växer logotypen något, och glider därefter ihop och tonas ut medan bakgrunden tonas bort och hemskärmen, som ligger klar
/// under, framträder. Med Reducera rörelse står logotypen still och allt tonas bort.
public enum StartIntroTimeline {
    /// Argumentet som UI-testerna startar appen med. Då visas inget intro.
    public static let skipArgument = "-uitest"

    /// Hela introt, högst 0,8 sekunder.
    static let fullDuration: TimeInterval = 0.8
    /// Växandet i början.
    static let growEnd: TimeInterval = 0.2
    static let grownScale = 1.12
    static let finalScale = 0.85
    /// Logotypen är borta före bakgrunden, så att den inte hänger kvar på hemskärmen.
    static let logoFadeEnd: TimeInterval = 0.65

    /// Med Reducera rörelse: en kort stund stilla och sedan en enkel toning.
    static let reducedDuration: TimeInterval = 0.5
    static let reducedHold: TimeInterval = 0.1

    /// Det som ritas vid en tidpunkt.
    public struct Frame: Equatable, Sendable {
        /// 1 är logotypens naturliga storlek, som på startskärmen.
        public let scale: Double
        public let logoOpacity: Double
        /// Bakgrundsfärgen över hemskärmen.
        public let backgroundOpacity: Double

        public init(scale: Double, logoOpacity: Double, backgroundOpacity: Double) {
            self.scale = scale
            self.logoOpacity = logoOpacity
            self.backgroundOpacity = backgroundOpacity
        }
    }

    public static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedDuration : fullDuration
    }

    public static func isFinished(at elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        elapsed >= duration(reduceMotion: reduceMotion)
    }

    public static func frame(at elapsed: TimeInterval, reduceMotion: Bool) -> Frame {
        let t = max(0, elapsed)
        if reduceMotion {
            let fade = 1 - CubicBezier.easeInOut.value(at: (t - reducedHold) / (reducedDuration - reducedHold))
            return Frame(scale: 1, logoOpacity: fade, backgroundOpacity: fade)
        }
        let scale: Double
        if t < growEnd {
            scale = 1 + (grownScale - 1) * CubicBezier.ease(0, 0, 0.58, 1).value(at: t / growEnd)
        } else {
            scale = grownScale + (finalScale - grownScale) * CubicBezier.easeInOut.value(at: (t - growEnd) / (fullDuration - growEnd))
        }
        let logo = 1 - CubicBezier.easeInOut.value(at: (t - growEnd) / (logoFadeEnd - growEnd))
        let background = 1 - CubicBezier.easeInOut.value(at: (t - growEnd) / (fullDuration - growEnd))
        return Frame(scale: scale, logoOpacity: logo, backgroundOpacity: background)
    }

    /// Introt visas när appen startar från början, aldrig med VoiceOver, aldrig i UI-tester och bara en gång per process.
    public static func shouldPlay(voiceOverRunning: Bool, arguments: [String], alreadyShown: Bool) -> Bool {
        !voiceOverRunning && !arguments.contains(skipArgument) && !alreadyShown
    }
}
