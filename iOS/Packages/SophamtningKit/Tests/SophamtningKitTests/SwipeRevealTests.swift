import CoreGraphics
import SwiftUI
import Testing
@testable import SophamtningDesign

/// Svep åt vänster på en adress på hemskärmen, som i Mail och Påminnelser.
@Suite struct SwipeRevealTests {
    private let width: CGFloat = 354
    private let open = SwipeReveal.openWidth

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

    // MARK: Knappen

    @Test func kapselnArSomIPaminnelser() {
        // Uppmätt i Påminnelser i iOS 26: 34 pt hög, 91 pt bred i vila och 10 pt från raden.
        #expect(SwipeReveal.buttonHeight == 34)
        #expect(SwipeReveal.buttonWidth == 91)
        #expect(SwipeReveal.gap == 10)
        #expect(SwipeReveal.openWidth == 101)
        #expect(SwipeReveal.contentPadding == 16)
    }

    @Test func tryckytanArMinst44Punkter() {
        #expect(SwipeReveal.tapHeight >= 44)
        #expect(SwipeReveal.tapHeight >= SwipeReveal.buttonHeight)
    }

    @Test func ikonenOchTextenKrymperTillsammansNarDeInteRyms() {
        // Ytan inuti kapseln i vila är 91 - 2 · 16 = 59 pt.
        #expect(SwipeReveal.labelMaxWidth == 59)
        #expect(SwipeReveal.labelScale(width: 56) == 1)
        #expect(SwipeReveal.labelScale(width: 59) == 1)
        #expect(SwipeReveal.labelScale(width: 118) == 0.5)
        // Innan bredden är uppmätt krymper inget.
        #expect(SwipeReveal.labelScale(width: 0) == 1)
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
        #expect(SwipeReveal.fullSwipeDistance(width: 150) > open)
        #expect(!SwipeReveal.isFullSwipe(offset: -open, width: 150))
    }

    // MARK: När fingret släpper

    @Test func fulltSvepTarBort() {
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 0, width: width) == .delete)
        // Även om fingret vänder i slutet: gränsen är passerad.
        #expect(SwipeReveal.outcome(offset: -width * 0.7, velocity: 400, width: width) == .delete)
    }

    @Test func merAnHalvaKnappenOppnar() {
        #expect(SwipeReveal.outcome(offset: -open * 0.6, velocity: 0, width: width) == .open)
        #expect(SwipeReveal.outcome(offset: -open * 0.4, velocity: 0, width: width) == .closed)
    }

    @Test func ettSnabbtSvepOppnarMenTarInteBort() {
        #expect(SwipeReveal.outcome(offset: -20, velocity: -1500, width: width) == .open)
    }

    @Test func ettSnabbtSvepAtHogerStanger() {
        #expect(SwipeReveal.outcome(offset: -open, velocity: 1500, width: width) == .closed)
    }

    @Test func stillastaendeVidOppnaKnappenForblirOppen() {
        #expect(SwipeReveal.outcome(offset: -open, velocity: 0, width: width) == .open)
    }

    // MARK: Knappen kommer fram

    @Test func knappenTonasInMedSvepet() {
        #expect(SwipeReveal.revealProgress(offset: 0) == 0)
        #expect(SwipeReveal.revealProgress(offset: -open / 2) == 0.5)
        #expect(SwipeReveal.revealProgress(offset: -open) == 1)
        // Ett längre svep gör den inte större.
        #expect(SwipeReveal.revealProgress(offset: -open * 3) == 1)
    }

    @Test func knappenArEnKapselIVila() {
        // Smalare yta än knappen: kapseln har sin vilobredd, med ikonen och texten i mitten.
        #expect(SwipeReveal.buttonLayout(offset: -20, width: width) == .init(width: 91, content: .center))
        #expect(SwipeReveal.buttonLayout(offset: -open, width: width) == .init(width: 91, content: .center))
    }

    @Test func kapselnVaxerMedFingret() {
        // Bredare yta: kapseln fyller ytan, 10 pt från raden, och ikonen och texten står kvar i mitten.
        let wide = SwipeReveal.buttonLayout(offset: -180, width: width)
        #expect(wide.width == 170)
        #expect(wide.content == .center)
    }

    // MARK: Språnget vid fullt svep

    @Test func radenFoljerFingretForeGransen() {
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        #expect(SwipeReveal.trackedOffset(-(limit - 1), width: width) == -(limit - 1))
        #expect(SwipeReveal.displayedOffset(-(limit - 1), width: width) == -(limit - 1))
        #expect(SwipeReveal.displayedOffset(-open, width: width) == -open)
    }

    @Test func forbiGransenDampasRorelsenSomEttGummiband() {
        // Som i Påminnelser: förbi gränsen följer raden fingret trögt, med en tredjedel av rörelsen.
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        #expect(SwipeReveal.overshootDamping == 0.3)
        #expect(abs(SwipeReveal.trackedOffset(-limit - 10, width: width) - (-limit - 3)) < 0.001)
        #expect(SwipeReveal.trackedOffset(-limit, width: width) == -limit)
    }

    @Test func sprangetArSomIPaminnelser() {
        #expect(SwipeReveal.fullSwipeJump == 72)
        #expect(SwipeReveal.jumpOffset(isFullSwipe: false, width: width) == 0)
        #expect(SwipeReveal.jumpOffset(isFullSwipe: true, width: width) == -72)
    }

    @Test func forbiGransenHopparKnappenTillFullBredd() {
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        let before = SwipeReveal.buttonLayout(offset: SwipeReveal.displayedOffset(-(limit - 1), width: width), width: width)
        let after = SwipeReveal.buttonLayout(offset: SwipeReveal.displayedOffset(-limit, width: width), width: width)
        #expect(SwipeReveal.displayedOffset(-limit, width: width) == -limit - SwipeReveal.fullSwipeJump)
        #expect(abs(after.width - before.width - (SwipeReveal.fullSwipeJump + 1)) < 0.001)
    }

    @Test func forbiGransenStarIkonenVidRadensKant() {
        // Som i Påminnelser: ikonen och texten flyttar från mitten till kanten mot raden, och tillbaka under gränsen.
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        let before = SwipeReveal.buttonLayout(offset: SwipeReveal.displayedOffset(-(limit - 1), width: width), width: width)
        let after = SwipeReveal.buttonLayout(offset: SwipeReveal.displayedOffset(-limit, width: width), width: width)
        #expect(before.content == .center)
        #expect(after.content == .leading)
        #expect(SwipeReveal.buttonLayout(offset: SwipeReveal.displayedOffset(-width, width: width), width: width).content == .leading)
    }

    @Test func tillbakaUnderGransenKrymperKnappen() {
        let limit = SwipeReveal.fullSwipeDistance(width: width)
        #expect(SwipeReveal.displayedOffset(-limit, width: width) < -limit)
        #expect(SwipeReveal.displayedOffset(-limit + 2, width: width) == -limit + 2)
    }

    @Test func sprangetGarInteForbiRaden() {
        // Med fingret längst bort, och på en smal rad där språnget inte får plats helt.
        for rowWidth in [width, 220, SwipeReveal.fullSwipeDistance(width: 0)] {
            let shown = SwipeReveal.displayedOffset(-rowWidth, width: rowWidth)
            #expect(shown >= -rowWidth)
            #expect(SwipeReveal.jumpOffset(isFullSwipe: true, width: rowWidth) <= 0)
        }
    }

    @Test func sprangetFjadrarUtomMedReduceraRorelse() {
        #expect(SwipeReveal.jump(reduceMotion: false) != nil)
        #expect(SwipeReveal.jump(reduceMotion: true) == nil)
    }
}
