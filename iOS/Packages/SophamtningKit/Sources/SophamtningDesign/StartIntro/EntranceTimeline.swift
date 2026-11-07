import Foundation

/// Hur korten och listorna kommer in. Rena värden, så att fördelningen kan testas. Vyerna använder dem i `Motion`.
public enum EntranceTimeline {
    /// Sträckan ett kort på hemskärmen glider.
    public static let cardDistance: Double = 24
    public static let cardDuration: TimeInterval = 0.45
    static let cardStagger: TimeInterval = 0.06

    /// Sträckan en rad i en lista glider.
    public static let rowDistance: Double = 14
    public static let rowDuration: TimeInterval = 0.32
    static let rowStagger: TimeInterval = 0.04
    /// Bara de första raderna kommer in en efter en. Resten står stilla från början, så att långa listor inte väntar.
    public static let rowLimit = 8

    /// UI-testerna startar med `-uitest`, och då är inträdesanimationerna avstängda.
    public static var isEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains(StartIntroTimeline.skipArgument)
    }

    public static func cardDelay(index: Int, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : Double(index) * cardStagger
    }

    public static func rowDelay(index: Int, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : Double(min(index, rowLimit - 1)) * rowStagger
    }

    public static func animatesRow(index: Int) -> Bool {
        index < rowLimit
    }

    /// Med Reducera rörelse glider inget, och allt är en enkel toning.
    public static func offset(_ distance: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : distance
    }

    /// När kalenderbladet ska börja vändas, räknat från att korten startade: när kortet kommit in.
    public static func flipDelay(cardIndex: Int, reduceMotion: Bool) -> TimeInterval {
        cardDelay(index: cardIndex, reduceMotion: reduceMotion) + (reduceMotion ? 0.2 : cardDuration)
    }
}

/// Hemskärmens start: korten väntar på introt, kommer in en gång, och sedan är det klart för resten av processen.
public struct StartEntrance: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case waiting
        case running(Date)
        case finished
    }

    private var phase: Phase

    /// Hemskärmens kort kommer in en gång per process, aldrig i UI-tester.
    public static func shouldPlay(arguments: [String], alreadyPlayed: Bool) -> Bool {
        !arguments.contains(StartIntroTimeline.skipArgument) && !alreadyPlayed
    }

    public init(plays: Bool) {
        phase = plays ? .waiting : .finished
    }

    /// Sant medan korten väntar på att få komma in.
    public var hidesCards: Bool { phase == .waiting }

    /// När korten startade, medan de håller på.
    public var begin: Date? {
        if case .running(let date) = phase { return date }
        return nil
    }

    /// Kalenderbladet får bara vändas som en del av starten.
    public var allowsOpeningFlip: Bool { phase != .finished }

    /// Startar korten. Har de redan startat eller är klara händer inget.
    public mutating func start(at date: Date) {
        if phase == .waiting { phase = .running(date) }
    }

    /// Starten är klar, eller ska inte spelas alls. Går aldrig tillbaka.
    public mutating func finish() {
        phase = .finished
    }
}

/// Minns vilka listor som redan visats i den här processen, så att de inte kommer in på nytt vid retur.
public struct ShownOnce<Key: Hashable & Sendable>: Sendable {
    private var shown: Set<Key> = []

    public init() {}

    public func shouldPlay(_ key: Key) -> Bool {
        !shown.contains(key)
    }

    public mutating func markShown(_ key: Key) {
        shown.insert(key)
    }
}
