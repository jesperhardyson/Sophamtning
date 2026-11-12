import Foundation
import Testing
@testable import SophamtningDesign

/// Pratbubblan från kärlet bredvid rubriken och i tomt läge.
@Suite struct BinBubbleTests {
    @Test func bubblanStarCirkaTvaSekunder() {
        #expect(BinBubbleTimeline.duration == 2)
        #expect(BinBubbleTimeline.isShowing(elapsed: 0))
        #expect(BinBubbleTimeline.isShowing(elapsed: 1.99))
        #expect(!BinBubbleTimeline.isShowing(elapsed: 2))
        #expect(!BinBubbleTimeline.isShowing(elapsed: -0.1))
    }

    @Test func bubblanTonasInOchBort() {
        #expect(BinBubbleTimeline.opacity(at: 0) == 0)
        #expect(BinBubbleTimeline.opacity(at: BinBubbleTimeline.fadeIn) == 1)
        #expect(BinBubbleTimeline.opacity(at: 1) == 1)
        let fading = BinBubbleTimeline.opacity(at: 1.8)
        #expect(fading > 0 && fading < 1)
        #expect(BinBubbleTimeline.opacity(at: 2) == 0)
        #expect(BinBubbleTimeline.opacity(at: 5) == 0)
        // Stiger hela vägen in och sjunker hela vägen ut.
        let fadeIn = stride(from: 0.0, through: BinBubbleTimeline.fadeIn, by: 0.02).map { BinBubbleTimeline.opacity(at: $0) }
        #expect(zip(fadeIn, fadeIn.dropFirst()).allSatisfy { $0 <= $1 })
        let fadeOut = stride(from: 2 - BinBubbleTimeline.fadeOut, through: 2, by: 0.02).map { BinBubbleTimeline.opacity(at: $0) }
        #expect(zip(fadeOut, fadeOut.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func bubblanSvavarUppat() {
        #expect(BinBubbleTimeline.rise(at: 0, reduceMotion: false) == 0)
        let steps = stride(from: 0.0, through: 2, by: 0.1).map { BinBubbleTimeline.rise(at: $0, reduceMotion: false) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(BinBubbleTimeline.rise(at: 2, reduceMotion: false) == BinBubbleTimeline.riseDistance)
        // Växer från lite mindre till full storlek medan den tonas in.
        #expect(BinBubbleTimeline.scale(at: 0, reduceMotion: false) < 1)
        #expect(BinBubbleTimeline.scale(at: BinBubbleTimeline.fadeIn, reduceMotion: false) == 1)
    }

    @Test func reduceraRorelseTonarBaraPaPlats() {
        for elapsed in [0, 0.1, 1, 1.9] {
            #expect(BinBubbleTimeline.rise(at: elapsed, reduceMotion: true) == 0)
            #expect(BinBubbleTimeline.scale(at: elapsed, reduceMotion: true) == 1)
        }
        // Toningen är densamma.
        #expect(BinBubbleTimeline.opacity(at: 1) == 1)
    }

    @Test func ettTryckStartarEttVarvBaraNarKarletStarStilla() {
        // Inget varv har spelats, eller det senaste är slut.
        #expect(BinBubbleTimeline.startsRound(roundElapsed: nil, reduceMotion: false))
        #expect(BinBubbleTimeline.startsRound(roundElapsed: BinLoaderTimeline.roundDuration, reduceMotion: false))
        // Under ett varv får det spela klart, så att kärlet inte hoppar. Bubblan byts ändå.
        #expect(!BinBubbleTimeline.startsRound(roundElapsed: 0.5, reduceMotion: false))
        // Med Reducera rörelse spelas inget varv alls.
        #expect(!BinBubbleTimeline.startsRound(roundElapsed: nil, reduceMotion: true))
    }

    @Test func spetsenStarOvanforLocketEllerOvanforHelaKarlet() {
        // Kärlet är 360 × 560 i SVG:n, och locket börjar vid y 150 från överkanten. 4 punkter luft till spetsen.
        #expect(abs(BinBubbleTimeline.tipY(binWidth: 135, placement: .overLid) - (135 * 150 / 360 - 4)) < 0.001)
        // Bredvid rubriken står spetsen ovanför hela kärlets ram, så att bubblan inte täcker kärlet eller texten.
        #expect(BinBubbleTimeline.tipY(binWidth: 30, placement: .aboveBin) == -4)
        #expect(BinBubbleTimeline.tipY(binWidth: 56, placement: .aboveBin) == -4)
        // Under kärlet: kärlets höjd (560 av 360 i bredd) och luften.
        #expect(abs(BinBubbleTimeline.tipY(binWidth: 36, placement: .belowBin) - (36 * 560 / 360 + 4)) < 0.001)
        #expect(BinBubbleTimeline.Placement.belowBin.isBelow)
        #expect(!BinBubbleTimeline.Placement.aboveBin.isBelow)
    }

    @Test func nastaTryckGerEnAnnanText() {
        var queue = BinLoaderTexts.Queue()
        var rng = SystemRandomNumberGenerator()
        var previous = queue.next(using: &rng)
        for _ in 0..<100 {
            let next = queue.next(using: &rng)
            #expect(next != previous)
            previous = next
        }
    }
}
