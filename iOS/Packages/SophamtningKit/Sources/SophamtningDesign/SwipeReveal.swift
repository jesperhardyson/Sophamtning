import CoreGraphics
import SwiftUI

/// Svep åt vänster på en rad, som i Påminnelser i iOS 26: en röd kapsel med papperskorg och text kommer fram till
/// höger, och ett fullt svep gör åtgärden direkt. Allt räknas i punkter, med negativ förskjutning åt vänster. Måtten är
/// uppmätta i Påminnelser.
public enum SwipeReveal {
    /// Avståndet mellan raden och kapseln.
    public static let gap: CGFloat = 10
    /// Kapselns bredd i vila, när raden står öppen.
    public static let buttonWidth: CGFloat = 91
    /// Kapselns höjd. Den står mitt för raden, på huvudkortet och på raderna.
    public static let buttonHeight: CGFloat = 34
    /// Höjden som tar emot tryck, större än kapseln.
    public static let tapHeight: CGFloat = 44
    /// Avståndet från kapselns kant till ikonen och texten när de står vid kanten.
    public static let contentPadding: CGFloat = 16
    /// Hur långt raden står åt vänster när den är öppen.
    public static var openWidth: CGFloat { buttonWidth + gap }
    /// Ytan för ikonen och texten inuti kapseln i vila.
    public static var labelMaxWidth: CGFloat { buttonWidth - 2 * contentPadding }

    /// Hur mycket ikonen och texten krymps, tillsammans, för att rymmas i kapseln med stor text. `width` är deras bredd
    /// i full storlek.
    public static func labelScale(width: CGFloat) -> CGFloat {
        width > labelMaxWidth ? labelMaxWidth / width : 1
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

    /// Hur långt kapseln har kommit fram, från 0 till 1 när raden står öppen. Kapseln tonas och skalas in med den.
    public static func revealProgress(offset: CGFloat) -> CGFloat {
        min(1, max(0, -offset / openWidth))
    }

    /// Hur mycket längre raden hoppar när svepet blir fullt, så att kapseln växer till full bredd. Påminnelser hoppar
    /// också förbi fingret.
    public static let fullSwipeJump: CGFloat = 48

    /// Radens förskjutning som den visas. Förbi gränsen för fullt svep hoppar raden ett stycke längre än fingret, och
    /// tillbaka när fingret drar under gränsen. Raden går aldrig längre än sin egen bredd.
    public static func displayedOffset(_ offset: CGFloat, width: CGFloat) -> CGFloat {
        guard isFullSwipe(offset: offset, width: width) else { return offset }
        return max(-width, offset - fullSwipeJump)
    }

    /// Var ikonen och texten står i kapseln.
    public enum ContentPosition: Equatable, Sendable {
        /// I mitten, före gränsen för fullt svep.
        case center
        /// Vid kanten mot raden, förbi gränsen.
        case leading
    }

    /// Kapselns bredd och var ikonen och texten står.
    public struct ButtonLayout: Equatable, Sendable {
        public let width: CGFloat
        public let content: ContentPosition

        public init(width: CGFloat, content: ContentPosition) {
            self.width = width
            self.content = content
        }
    }

    /// Kapseln fyller den frilagda ytan, med `gap` till raden, men är aldrig smalare än i vila. Ikonen och texten står i
    /// mitten, och vid kanten mot raden förbi gränsen för fullt svep. `offset` är förskjutningen som den visas.
    public static func buttonLayout(offset: CGFloat, width: CGFloat) -> ButtonLayout {
        let revealed = max(0, -offset - gap)
        return ButtonLayout(
            width: max(buttonWidth, revealed),
            content: isFullSwipe(offset: offset, width: width) ? .leading : .center
        )
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
