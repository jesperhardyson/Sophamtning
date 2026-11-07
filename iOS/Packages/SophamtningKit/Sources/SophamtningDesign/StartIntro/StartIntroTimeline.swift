import Foundation

/// Tidslinjen för introt direkt efter startskärmen. Allt är rena funktioner av tid, så att vyn kan rita om från klockan.
///
/// Första bilden är exakt startskärmen: logotypen i naturlig storlek (skala 1) utan toning, på appens bakgrundsfärg. Den står
/// still i 0,3 s, eftersom systemet tonar startskärmen över appens första bilder så länge och två logotyper annars syns. Sedan
/// snurrar ringen ett varv, kalendern studsar till, och logotypen krymper och tonas ut medan bakgrunden tonas bort och
/// hemskärmen, som ligger klar under, framträder. Med Reducera rörelse står logotypen still och allt tonas bort.
public enum StartIntroTimeline {
    /// Hela introt, högst 1,2 sekunder.
    static let fullDuration: TimeInterval = 1.2
    /// Stilla i början, medan systemet tonar bort startskärmen.
    static let holdEnd: TimeInterval = 0.3
    /// Ringen snurrar ett varv från `holdEnd`.
    static let ringEnd: TimeInterval = 0.9
    /// Kalendern studsar medan ringen är mitt i varvet.
    public static let bounceStart: TimeInterval = 0.42
    static let bounceEnd: TimeInterval = 1.0
    static let bouncePeak = 1.15
    /// Här börjar logotypen krympa och tonas ut, och bakgrunden tonas bort. Då börjar också hemskärmens kort komma in.
    static let fullExitStart: TimeInterval = 0.8
    static let finalScale = 0.6
    /// Bakgrunden går undan snabbt, så att korten syns medan de glider upp.
    static let backgroundFadeEnd: TimeInterval = 1.05
    /// Logotypen tonas ut lite senare och krymper över hemskärmen, så att krympningen hinner synas. Den är borta vid 1,1 s,
    /// så att den inte står kvar ovanpå hemkortet.
    static let logoFadeStart: TimeInterval = 0.9
    static let logoFadeEnd: TimeInterval = 1.1

    /// Med Reducera rörelse: en kort stund stilla och sedan en enkel toning.
    static let reducedDuration: TimeInterval = 0.5
    static let reducedHold: TimeInterval = 0.1

    /// Det som ritas vid en tidpunkt.
    public struct Frame: Equatable, Sendable {
        /// Hela logotypen. 1 är den naturliga storleken, som på startskärmen.
        public let scale: Double
        public let logoOpacity: Double
        /// Bakgrundsfärgen över hemskärmen.
        public let backgroundOpacity: Double
        /// Kalenderns egen skala, utöver `scale`.
        public let calendarScale: Double
        /// Ringens vridning i grader, medurs.
        public let ringRotation: Double

        public init(scale: Double, logoOpacity: Double, backgroundOpacity: Double, calendarScale: Double = 1, ringRotation: Double = 0) {
            self.scale = scale
            self.logoOpacity = logoOpacity
            self.backgroundOpacity = backgroundOpacity
            self.calendarScale = calendarScale
            self.ringRotation = ringRotation
        }
    }

    /// När introt börjar lämna skärmen. Hemskärmens kort startar då.
    public static func exitStart(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedHold : fullExitStart
    }

    /// Ett tryck tar bort introt så länge det täcker hemskärmen. När det börjar lämna går trycken igenom till hemskärmen.
    public static func capturesTouches(at elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        elapsed < exitStart(reduceMotion: reduceMotion)
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
        let exit = fullExitStart
        let scale = 1 + (finalScale - 1) * CubicBezier.easeInOut.value(at: (t - exit) / (fullDuration - exit))
        let logo = 1 - CubicBezier.easeInOut.value(at: (t - logoFadeStart) / (logoFadeEnd - logoFadeStart))
        let background = 1 - CubicBezier.easeInOut.value(at: (t - exit) / (backgroundFadeEnd - exit))
        // Tydlig fart in och ut, mer än CSS `ease-in-out`.
        let ring = 360 * CubicBezier.ease(0.65, 0, 0.35, 1).value(at: (t - holdEnd) / (ringEnd - holdEnd))
        return Frame(scale: scale, logoOpacity: logo, backgroundOpacity: background, calendarScale: calendarScale(at: t), ringRotation: ring)
    }

    /// En dämpad svängning: upp till toppen, ner under 1 och tillbaka. Exakt 1 utanför studsen.
    private static func calendarScale(at t: TimeInterval) -> Double {
        let u = (t - bounceStart) / (bounceEnd - bounceStart)
        guard u > 0, u < 1 else { return 1 }
        // Kurvans högsta värde, vid u = atan(pi) / (3 pi), så att toppen blir exakt `bouncePeak`.
        let highest = exp(-3 * atan(Double.pi) / (3 * Double.pi)) * sin(atan(Double.pi))
        return 1 + (bouncePeak - 1) * exp(-3 * u) * sin(3 * Double.pi * u) / highest
    }

    /// Introt visas när appen startar från början, aldrig med VoiceOver, aldrig i UI-tester (`skipsIntro`, som appen
    /// bara sätter i Debug) och bara en gång per process.
    public static func shouldPlay(voiceOverRunning: Bool, skipsIntro: Bool, alreadyShown: Bool) -> Bool {
        !voiceOverRunning && !skipsIntro && !alreadyShown
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
