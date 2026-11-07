import CoreGraphics
import SwiftUI
import Testing
@testable import SophamtningDesign

/// Svep åt vänster på en adress på hemskärmen, som i Mail och Påminnelser.
@Suite struct SwipeRevealTests {
    private let width: CGFloat = 354

    // MARK: Riktning

    @Test func vertikalRorelseBlirScrollning() {
        #expect(!SwipeReveal.begins(movement: CGSize(width: -4, height: 30), isOpen: false))
        #expect(!SwipeReveal.begins(movement: CGSize(width: -20, height: 20), isOpen: false))
        // Snett men mest vertikalt: fortfarande scrollning.
        #expect(!SwipeReveal.begins(movement: CGSize(width: -24, height: 18), isOpen: false))
    }

    @Test func tydligRorelseAtVansterBorjarSvepet() {
        #expect(SwipeReveal.begins(movement: CGSize(width: -30, height: 4), isOpen: false))
        #expect(SwipeReveal.begins(movement: CGSize(width: -30, height: -12), isOpen: false))
    }

    @Test func atHogerBorjarBaraNarRadenArOppen() {
        #expect(!SwipeReveal.begins(movement: CGSize(width: 30, height: 0), isOpen: false))
        #expect(SwipeReveal.begins(movement: CGSize(width: 30, height: 0), isOpen: true))
    }

    @Test func ingenRorelseBorjarInget() {
        #expect(!SwipeReveal.begins(movement: .zero, isOpen: false))
        #expect(!SwipeReveal.begins(movement: .zero, isOpen: true))
    }

    // MARK: Förskjutning

    @Test func radenFoljerFingretAtVanster() {
        #expect(SwipeReveal.offset(start: 0, translation: -40, width: width) == -40)
        #expect(SwipeReveal.offset(start: -SwipeReveal.openWidth, translation: -10, width: width) == -SwipeReveal.openWidth - 10)
    }

    @Test func radenStannarVidNollAtHoger() {
        #expect(SwipeReveal.offset(start: 0, translation: 50, width: width) == 0)
        #expect(SwipeReveal.offset(start: -SwipeReveal.openWidth, translation: 200, width: width) == 0)
    }

    @Test func radenGarInteLangreAnSinBredd() {
        #expect(SwipeReveal.offset(start: 0, translation: -900, width: width) == -width)
    }

    // MARK: Fullt svep

    @Test func fulltSvepEfterMerAnHalvaRaden() {
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        #expect(limit == width * 0.6)
        #expect(!SwipeReveal.isFullSwipe(offset: -(limit - 1), width: width))
        #expect(SwipeReveal.isFullSwipe(offset: -limit, width: width))
    }

    @Test func fulltSvepAlltidLangreAnKnappen() {
        // På en smal rad ligger gränsen ändå en bit efter den öppna knappen.
        #expect(SwipeReveal.fullSwipeDistance(width: 150) > SwipeReveal.openWidth)
        #expect(!SwipeReveal.isFullSwipe(offset: -SwipeReveal.openWidth, width: 150))
    }

    // MARK: När fingret släpper

    @Test func fulltSvepTarBort() {
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 0, width: width) == .delete)
        // Även om fingret vänder i slutet: gränsen är passerad.
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 400, width: width) == .delete)
    }

    @Test func merAnHalvaKnappenOppnar() {
        #expect(SwipeReveal.outcome(offset: -SwipeReveal.openWidth * 0.6, velocity: 0, width: width) == .open)
        #expect(SwipeReveal.outcome(offset: -SwipeReveal.openWidth * 0.4, velocity: 0, width: width) == .closed)
    }

    @Test func ettSnabbtSvepOppnarMenTarInteBort() {
        #expect(SwipeReveal.outcome(offset: -20, velocity: -1500, width: width) == .open)
    }

    @Test func ettSnabbtSvepAtHogerStanger() {
        #expect(SwipeReveal.outcome(offset: -SwipeReveal.openWidth, velocity: 1500, width: width) == .closed)
    }

    @Test func stillastaendeVidOppnaKnappenForblirOppen() {
        #expect(SwipeReveal.outcome(offset: -SwipeReveal.openWidth, velocity: 0, width: width) == .open)
    }

    // MARK: Rörelse

    @Test func knappensMatt() {
        #expect(SwipeReveal.buttonWidth == 88)
        #expect(SwipeReveal.gap == 8)
        #expect(SwipeReveal.openWidth == 96)
    }

    @Test func reduceraRorelseUtanFjadring() {
        #expect(SwipeReveal.settle(reduceMotion: true) == .easeOut(duration: 0.2))
        #expect(SwipeReveal.settle(reduceMotion: false) == .spring(duration: 0.35, bounce: 0.2))
    }
}
