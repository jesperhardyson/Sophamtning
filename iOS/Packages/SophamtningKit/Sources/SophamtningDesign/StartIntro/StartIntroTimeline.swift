import Foundation

/// Tidslinjen för introt direkt efter startskärmen. Allt är rena funktioner av tid, så att vyn kan rita om från klockan.
///
/// Första bilden är exakt startskärmen: logotypen i naturlig storlek (skala 1) utan toning, på appens bakgrundsfärg. Den står
/// still i 0,3 s, eftersom systemet tonar startskärmen över appens första bilder så länge och två logotyper annars syns. Sedan
/// glider den ihop och tonas ut medan bakgrunden tonas bort och hemskärmen, som ligger klar under, framträder. Med Reducera rörelse står logotypen still och allt tonas bort.
public enum StartIntroTimeline {
    /// Argumentet som UI-testerna startar appen med. Då visas inget intro.
    public static let skipArgument = "-uitest"

    /// Hela introt, högst 0,8 sekunder.
    static let fullDuration: TimeInterval = 0.8
    /// Stilla i början, medan systemet tonar bort startskärmen.
    static let holdEnd: TimeInterval = 0.3
    static let finalScale = 0.85
    /// Logotypen är borta före bakgrunden, så att den inte hänger kvar på hemskärmen.
    static let logoFadeEnd: TimeInterval = 0.7

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
        let scale = 1 + (finalScale - 1) * CubicBezier.easeInOut.value(at: (t - holdEnd) / (fullDuration - holdEnd))
        let logo = 1 - CubicBezier.easeInOut.value(at: (t - holdEnd) / (logoFadeEnd - holdEnd))
        let background = 1 - CubicBezier.easeInOut.value(at: (t - holdEnd) / (fullDuration - holdEnd))
        return Frame(scale: scale, logoOpacity: logo, backgroundOpacity: background)
    }

    /// Introt visas när appen startar från början, aldrig med VoiceOver, aldrig i UI-tester och bara en gång per process.
    public static func shouldPlay(voiceOverRunning: Bool, arguments: [String], alreadyShown: Bool) -> Bool {
        !voiceOverRunning && !arguments.contains(skipArgument) && !alreadyShown
    }

    /// Hur länge efter processens start första bilden får komma för att räknas som en start från början.
    static let freshLaunchLimit: TimeInterval = 5

    /// Startade processen i bakgrunden, till exempel för en bakgrundsuppdatering, och användaren öppnar appen först senare, har
    /// det gått lång tid sedan processen startade. Då är det ingen start från början, och inget intro visas. Läget går inte att
    /// läsa av säkert när appen startar (`applicationState` är `.background` även vid en vanlig start), därför tiden.
    public static func isFreshLaunch(secondsSinceProcessStart: TimeInterval) -> Bool {
        secondsSinceProcessStart <= freshLaunchLimit
    }
}
