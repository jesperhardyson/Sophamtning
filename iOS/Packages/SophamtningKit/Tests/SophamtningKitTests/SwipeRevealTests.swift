import CoreGraphics
import SwiftUI
import Testing
@testable import SophamtningDesign

/// Svep åt vänster på en adress på hemskärmen, som i Mail och Påminnelser.
@Suite struct SwipeRevealTests {
    private let width: CGFloat = 354
    private let open = SwipeReveal.ButtonShape.fullHeight.openWidth

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
        #expect(SwipeReveal.offset(start: -open, translation: -10, width: width) == -open - 10)
    }

    @Test func radenStannarVidNollAtHoger() {
        #expect(SwipeReveal.offset(start: 0, translation: 50, width: width) == 0)
        #expect(SwipeReveal.offset(start: -open, translation: 200, width: width) == 0)
    }

    @Test func radenGarInteLangreAnSinBredd() {
        #expect(SwipeReveal.offset(start: 0, translation: -900, width: width) == -width)
    }

    // MARK: Fullt svep

    @Test func fulltSvepEfterMerAnHalvaRaden() {
        let limit = SwipeReveal.fullSwipeDistance(width: width, shape: .fullHeight)
        #expect(limit == width * 0.6)
        #expect(!SwipeReveal.isFullSwipe(offset: -(limit - 1), width: width, shape: .fullHeight))
        #expect(SwipeReveal.isFullSwipe(offset: -limit, width: width, shape: .fullHeight))
    }

    @Test func fulltSvepAlltidLangreAnKnappen() {
        // På en smal rad ligger gränsen ändå en bit efter den öppna knappen.
        #expect(SwipeReveal.fullSwipeDistance(width: 150, shape: .fullHeight) > open)
        #expect(!SwipeReveal.isFullSwipe(offset: -open, width: 150, shape: .fullHeight))
    }

    // MARK: När fingret släpper

    @Test func fulltSvepTarBort() {
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 0, width: width, shape: .fullHeight) == .delete)
        // Även om fingret vänder i slutet: gränsen är passerad.
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 400, width: width, shape: .fullHeight) == .delete)
    }

    @Test func merAnHalvaKnappenOppnar() {
        #expect(SwipeReveal.outcome(offset: -open * 0.6, velocity: 0, width: width, shape: .fullHeight) == .open)
        #expect(SwipeReveal.outcome(offset: -open * 0.4, velocity: 0, width: width, shape: .fullHeight) == .closed)
    }

    @Test func ettSnabbtSvepOppnarMenTarInteBort() {
        #expect(SwipeReveal.outcome(offset: -20, velocity: -1500, width: width, shape: .fullHeight) == .open)
    }

    @Test func ettSnabbtSvepAtHogerStanger() {
        #expect(SwipeReveal.outcome(offset: -open, velocity: 1500, width: width, shape: .fullHeight) == .closed)
    }

    @Test func stillastaendeVidOppnaKnappenForblirOppen() {
        #expect(SwipeReveal.outcome(offset: -open, velocity: 0, width: width, shape: .fullHeight) == .open)
    }

    // MARK: Rund knapp

    @Test func rundKnappOppnasEfterHalvaSinBredd() {
        let round = SwipeReveal.ButtonShape.round.openWidth
        #expect(round < open)
        #expect(SwipeReveal.outcome(offset: -round * 0.6, velocity: 0, width: width, shape: .round) == .open)
        #expect(SwipeReveal.outcome(offset: -round * 0.4, velocity: 0, width: width, shape: .round) == .closed)
        // Samma läge räcker inte för den höga knappen.
        #expect(SwipeReveal.outcome(offset: -round * 0.6, velocity: 0, width: width, shape: .fullHeight) == .closed)
    }

    @Test func rundKnappFulltSvepLangreAnKnappen() {
        let round = SwipeReveal.ButtonShape.round.openWidth
        #expect(SwipeReveal.fullSwipeDistance(width: 150, shape: .round) > round)
        #expect(!SwipeReveal.isFullSwipe(offset: -round, width: 150, shape: .round))
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 0, width: width, shape: .round) == .delete)
    }

    @Test func rundKnappTonasInMedSvepet() {
        let round = SwipeReveal.ButtonShape.round.openWidth
        #expect(SwipeReveal.revealProgress(offset: 0, shape: .round) == 0)
        #expect(SwipeReveal.revealProgress(offset: -round / 2, shape: .round) == 0.5)
        #expect(SwipeReveal.revealProgress(offset: -round, shape: .round) == 1)
        // Ett längre svep gör den inte större.
        #expect(SwipeReveal.revealProgress(offset: -round * 3, shape: .round) == 1)
    }
}
