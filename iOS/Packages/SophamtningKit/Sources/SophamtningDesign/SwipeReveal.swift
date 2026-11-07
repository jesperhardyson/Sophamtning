import CoreGraphics
import SwiftUI

/// Svep åt vänster på en rad, som i Mail och Påminnelser: en röd knapp kommer fram till höger, och ett fullt svep
/// gör åtgärden direkt. Allt räknas i punkter, med negativ förskjutning åt vänster.
public enum SwipeReveal {
    /// Avståndet mellan raden och knappen.
    public static let gap: CGFloat = 8

    /// Knappen bakom raden. Huvudkortet har en rund knapp mitt för kortet, och raderna en knapp lika hög som raden.
    public enum ButtonShape: Sendable {
        case fullHeight, round

        /// Knappens bredd när raden står öppen. Den runda knappen är 56 pt.
        public var buttonWidth: CGFloat {
            switch self {
            case .fullHeight: 88
            case .round: 56
            }
        }

        /// Hur långt raden står åt vänster när den är öppen.
        public var openWidth: CGFloat { buttonWidth + SwipeReveal.gap }
    }

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
    public static func fullSwipeDistance(width: CGFloat, shape: ButtonShape) -> CGFloat {
        max(width * fullSwipeFraction, shape.openWidth + fullSwipeMargin)
    }

    public static func isFullSwipe(offset: CGFloat, width: CGFloat, shape: ButtonShape) -> Bool {
        -offset >= fullSwipeDistance(width: width, shape: shape)
    }

    public enum Outcome: Equatable, Sendable {
        case closed, open, delete
    }

    /// Vad som händer när fingret släpper. Ett fullt svep gör åtgärden. Annars öppnas raden om den, med fart, når förbi
    /// halva knappen. Ett snabbt svep öppnar alltså men tar aldrig bort.
    public static func outcome(offset: CGFloat, velocity: CGFloat, width: CGFloat, shape: ButtonShape) -> Outcome {
        if isFullSwipe(offset: offset, width: width, shape: shape) { return .delete }
        let projected = offset + velocity * projection
        return -projected > shape.openWidth / 2 ? .open : .closed
    }

    /// Hur långt knappen har kommit fram, från 0 till 1 när raden står öppen. Den runda knappen tonas och skalas in med den.
    public static func revealProgress(offset: CGFloat, shape: ButtonShape) -> CGFloat {
        min(1, max(0, -offset / shape.openWidth))
    }

    /// Hur mycket längre raden hoppar när svepet blir fullt, så att knappen växer till full bredd.
    public static let fullSwipeJump: CGFloat = 48

    /// Radens förskjutning som den visas. Förbi gränsen för fullt svep hoppar raden ett stycke längre än fingret, och
    /// tillbaka när fingret drar under gränsen. Raden går aldrig längre än sin egen bredd.
    public static func displayedOffset(_ offset: CGFloat, width: CGFloat, shape: ButtonShape) -> CGFloat {
        guard isFullSwipe(offset: offset, width: width, shape: shape) else { return offset }
        return max(-width, offset - fullSwipeJump)
    }

    /// Knappens bredd och var ikonen ligger, räknat från knappens vänsterkant.
    public struct ButtonLayout: Equatable, Sendable {
        public let width: CGFloat
        /// Var ikonen (och texten) börjar. Noll när ikonen ligger vid radens kant, och negativ när knappen är smalare än
        /// sin vilobredd och ikonen ligger mot skärmkanten, delvis under raden.
        public let contentOffset: CGFloat

        public init(width: CGFloat, contentOffset: CGFloat) {
            self.width = width
            self.contentOffset = contentOffset
        }
    }

    /// Knappen fyller den frilagda ytan, med `gap` till raden, och ikonen följer radens kant. Den runda knappen är rund
    /// tills ytan blir bredare än den, och växer sedan till en kapsel. Den höga knappen kommer fram under raden.
    public static func buttonLayout(offset: CGFloat, shape: ButtonShape) -> ButtonLayout {
        let revealed = max(0, -offset - gap)
        switch shape {
        case .round:
            return ButtonLayout(width: max(shape.buttonWidth, revealed), contentOffset: 0)
        case .fullHeight:
            return ButtonLayout(width: revealed, contentOffset: min(0, revealed - shape.buttonWidth))
        }
    }

    /// Språnget till full bredd och tillbaka. Med Reducera rörelse ändras bara bredden, utan fjädring.
    public static func jump(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.35)
    }

    /// Raden på väg till sitt läge. Med Reducera rörelse utan fjädring.
    public static func settle(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.2)
    }
}
