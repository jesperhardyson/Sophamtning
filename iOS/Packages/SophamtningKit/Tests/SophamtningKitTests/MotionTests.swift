import Foundation
import SophamtningKit
import Testing
@testable import SophamtningDesign

@Suite struct MotionTests {
    // MARK: Hemskärmen kommer in

    @Test func kortenKommerEttEfterEtt() {
        #expect(EntranceTimeline.cardDistance == 24)
        #expect(EntranceTimeline.cardDuration == 0.45)
        let delays = (0..<5).map { EntranceTimeline.cardDelay(index: $0, reduceMotion: false) }
        #expect(delays.first == 0)
        for (earlier, later) in zip(delays, delays.dropFirst()) {
            #expect(abs(later - earlier - 0.06) < 0.0001)
        }
    }

    @Test func reduceraRorelseToningUtanFordrojningOchUtanGlid() {
        for index in 0..<5 {
            #expect(EntranceTimeline.cardDelay(index: index, reduceMotion: true) == 0)
            #expect(EntranceTimeline.rowDelay(index: index, reduceMotion: true) == 0)
        }
        #expect(EntranceTimeline.offset(24, reduceMotion: true) == 0)
        #expect(EntranceTimeline.offset(24, reduceMotion: false) == 24)
    }

    @Test func vandningenBorjarNarKortetKommitIn() {
        // Huvudkortet är andra kortet i ordningen: 60 ms väntan och 0,45 s glidning.
        #expect(abs(EntranceTimeline.flipDelay(cardIndex: 1, reduceMotion: false) - 0.51) < 0.0001)
        #expect(abs(EntranceTimeline.flipDelay(cardIndex: 1, reduceMotion: true) - 0.2) < 0.0001)
    }

    // MARK: En gång per process

    @Test func spelasBaraEnGangPerProcess() {
        #expect(StartEntrance.shouldPlay(arguments: ["Sophamtning"], alreadyPlayed: false))
        #expect(!StartEntrance.shouldPlay(arguments: ["Sophamtning"], alreadyPlayed: true))
        #expect(!StartEntrance.shouldPlay(arguments: ["Sophamtning", "-uitest"], alreadyPlayed: false))
        // Testet av inträdet har testdata men låter korten komma in.
        #expect(StartEntrance.shouldPlay(arguments: ["Sophamtning", "-uitest-intrade"], alreadyPlayed: false))
    }

    @Test func enStartBorjarEnGangOchAldrigOm() {
        var entrance = StartEntrance(plays: true)
        #expect(entrance.hidesCards)
        #expect(entrance.begin == nil)
        #expect(entrance.allowsOpeningFlip)
        let first = Date(timeIntervalSince1970: 100)
        entrance.start(at: first)
        #expect(!entrance.hidesCards)
        #expect(entrance.begin == first)
        entrance.start(at: first.addingTimeInterval(50))
        #expect(entrance.begin == first)
        entrance.finish()
        #expect(!entrance.hidesCards)
        #expect(!entrance.allowsOpeningFlip)
        // När den är klar kan den inte starta på nytt, till exempel vid retur från bakgrunden.
        entrance.start(at: first.addingTimeInterval(100))
        #expect(entrance.begin == nil)
        #expect(!entrance.hidesCards)
        #expect(!entrance.allowsOpeningFlip)
    }

    @Test func utanStartVisasAlltDirektUtanVandning() {
        var entrance = StartEntrance(plays: false)
        #expect(!entrance.hidesCards)
        #expect(!entrance.allowsOpeningFlip)
        entrance.start(at: Date())
        #expect(entrance.begin == nil)
    }

    @Test func enListaSomRedanVisatsSpelasInteIgen() {
        var shown = ShownOnce<String>()
        #expect(shown.shouldPlay("a"))
        shown.markShown("a")
        #expect(!shown.shouldPlay("a"))
        #expect(shown.shouldPlay("b"))
    }

    // MARK: Listor

    @Test func radernaKommerEnEfterEnOchBaraDeForstaAtta() {
        #expect(EntranceTimeline.rowLimit == 8)
        let delays = (0..<8).map { EntranceTimeline.rowDelay(index: $0, reduceMotion: false) }
        #expect(delays.first == 0)
        for (earlier, later) in zip(delays, delays.dropFirst()) {
            #expect(abs(later - earlier - 0.04) < 0.0001)
        }
        #expect(EntranceTimeline.animatesRow(index: 7))
        #expect(!EntranceTimeline.animatesRow(index: 8))
        // Den sista raden väntar kortare tid än en tredjedels sekund, så att nya sökresultat aldrig känns sena.
        #expect(delays.last! < 0.3)
    }

    // MARK: Tryck

    @Test func tryckFjadrarOchReduceraRorelseToning() {
        #expect(PressMotion.scale(pressed: false, reduceMotion: false) == 1)
        #expect(PressMotion.scale(pressed: true, reduceMotion: false) == 0.96)
        #expect(PressMotion.opacity(pressed: true, reduceMotion: false) == 1)
        #expect(PressMotion.scale(pressed: true, reduceMotion: true) == 1)
        #expect(PressMotion.opacity(pressed: true, reduceMotion: true) < 1)
        #expect(PressMotion.opacity(pressed: false, reduceMotion: true) == 1)
    }
}
