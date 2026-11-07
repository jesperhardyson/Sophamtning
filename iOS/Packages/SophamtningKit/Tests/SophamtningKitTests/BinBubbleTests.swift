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

    @Test func ettTryckTasEmotBaraNarAlltArStilla() {
        // Inget varv och ingen bubbla.
        #expect(BinBubbleTimeline.acceptsTap(roundElapsed: nil, bubbleElapsed: nil, reduceMotion: false))
        // Under ett varv gör trycket inget.
        #expect(!BinBubbleTimeline.acceptsTap(roundElapsed: 0.5, bubbleElapsed: nil, reduceMotion: false))
        // En bubbla åt gången: varvet är slut men bubblan syns fortfarande.
        #expect(!BinBubbleTimeline.acceptsTap(roundElapsed: 1.9, bubbleElapsed: 1.9, reduceMotion: false))
        #expect(BinBubbleTimeline.acceptsTap(roundElapsed: 2.1, bubbleElapsed: 2.1, reduceMotion: false))
        // Med Reducera rörelse finns inget varv, bara bubblan.
        #expect(BinBubbleTimeline.acceptsTap(roundElapsed: 0.5, bubbleElapsed: nil, reduceMotion: true))
        #expect(!BinBubbleTimeline.acceptsTap(roundElapsed: nil, bubbleElapsed: 1, reduceMotion: true))
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
