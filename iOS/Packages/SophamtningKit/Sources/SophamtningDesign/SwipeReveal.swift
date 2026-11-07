import CoreGraphics
import SwiftUI

/// Svep åt vänster på en rad, som i Mail och Påminnelser: en röd knapp kommer fram till höger, och ett fullt svep
/// gör åtgärden direkt. Allt räknas i punkter, med negativ förskjutning åt vänster.
public enum SwipeReveal {
    /// Knappens bredd när raden står öppen.
    public static let buttonWidth: CGFloat = 88
    /// Avståndet mellan raden och knappen.
    public static let gap: CGFloat = 8
    /// Hur långt raden står åt vänster när den är öppen.
    public static var openWidth: CGFloat { buttonWidth + gap }

    /// Rörelsen måste vara så här mycket mer vågrät än lodrät. Annars är det scrollning.
    static let horizontalRatio: CGFloat = 1.5
    /// Andelen av radens bredd där svepet blir fullt.
    static let fullSwipeFraction: CGFloat = 0.6
    /// Ett fullt svep ligger alltid minst så här långt efter den öppna knappen, också på en smal rad.
    static let fullSwipeMargin: CGFloat = 48
    /// Hur långt rörelsen förväntas fortsätta efter släppet, i sekunder av hastigheten.
    static let projection: CGFloat = 0.1

    /// Om en rörelse ska bli ett svep. Bara en tydligt vågrät rörelse räknas, och åt höger bara när raden redan är öppen.
    public static func begins(movement: CGSize, isOpen: Bool) -> Bool {
        guard abs(movement.width) > abs(movement.height) * horizontalRatio else { return false }
        return isOpen || movement.width < 0
    }

    /// Radens förskjutning medan fingret dras. Åt höger stannar raden vid noll, och åt vänster vid sin egen bredd.
    public static func offset(start: CGFloat, translation: CGFloat, width: CGFloat) -> CGFloat {
        min(0, max(-width, start + translation))
    }

    /// Där svepet blir fullt.
    public static func fullSwipeDistance(width: CGFloat) -> CGFloat {
        max(width * fullSwipeFraction, openWidth + fullSwipeMargin)
    }

    public static func isFullSwipe(offset: CGFloat, width: CGFloat) -> Bool {
        -offset >= fullSwipeDistance(width: width)
    }

    public enum Outcome: Equatable, Sendable {
        case closed, open, delete
    }

    /// Vad som händer när fingret släpper. Ett fullt svep gör åtgärden. Annars öppnas raden om den, med fart, når förbi
    /// halva knappen. Ett snabbt svep öppnar alltså men tar aldrig bort.
    public static func outcome(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Outcome {
        if isFullSwipe(offset: offset, width: width) { return .delete }
        let projected = offset + velocity * projection
        return -projected > openWidth / 2 ? .open : .closed
    }

    /// Raden på väg till sitt läge. Med Reducera rörelse utan fjädring.
    public static func settle(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.2)
    }
}
