import Foundation
import SophamtningKit
import Testing
@testable import SophamtningDesign

@Suite struct CalendarFlipTests {
    @Test func bladetVandsPaTvaHalvor() {
        #expect(CalendarFlipTimeline.duration == 2 * CalendarFlipTimeline.half)
        // En tydlig vändning, cirka 0,6 s.
        #expect(abs(CalendarFlipTimeline.duration - 0.6) < 0.05)
    }

    @Test func vidStartVandsBladetFranDagensDatumTillTomningsdagen() {
        let today = DayDate("2026-11-07")!
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: DayDate("2026-11-12")!) == today)
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: DayDate("2026-11-08")!) == today)
    }

    @Test func tomningIDagVandsInte() {
        let today = DayDate("2026-11-07")!
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: today) == nil)
    }

    @Test func foreOchEfterVandningenSynsRattDatumOchBladetArRakt() {
        // Tiden är negativ medan kortet kommer in: dagens datum, rakt blad och ingen toning.
        #expect(!CalendarFlipTimeline.showsNewDate(at: -0.5))
        #expect(CalendarFlipTimeline.angle(at: -0.5) == 0)
        #expect(CalendarFlipTimeline.opacity(at: -0.5) == 1)
        #expect(CalendarFlipTimeline.showsNewDate(at: CalendarFlipTimeline.duration))
    }

    @Test func bladetStartarOchSlutarRaktOchStilla() {
        #expect(CalendarFlipTimeline.angle(at: 0) == 0)
        #expect(CalendarFlipTimeline.angle(at: CalendarFlipTimeline.duration) == 0)
        #expect(CalendarFlipTimeline.angle(at: 5) == 0)
        #expect(CalendarFlipTimeline.angle(at: -1) == 0)
    }

    @Test func gamlaBladetViksUppTillNittioGrader() {
        let half = CalendarFlipTimeline.half
        #expect(CalendarFlipTimeline.angle(at: half - 0.0001) < -89)
        let first = stride(from: 0.0, to: half, by: half / 20).map { CalendarFlipTimeline.angle(at: $0) }
        #expect(zip(first, first.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func nyaBladetKommerInfranNittioGrader() {
        let half = CalendarFlipTimeline.half
        #expect(CalendarFlipTimeline.angle(at: half) == 90)
        let second = stride(from: half, through: CalendarFlipTimeline.duration, by: half / 20).map { CalendarFlipTimeline.angle(at: $0) }
        #expect(zip(second, second.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func nyttDatumVisasEfterForstaHalvan() {
        #expect(!CalendarFlipTimeline.showsNewDate(at: 0))
        #expect(!CalendarFlipTimeline.showsNewDate(at: CalendarFlipTimeline.half - 0.001))
        #expect(CalendarFlipTimeline.showsNewDate(at: CalendarFlipTimeline.half))
        #expect(CalendarFlipTimeline.showsNewDate(at: 10))
    }

    @Test func reduceraRorelseGerBaraToningUtanVridning() {
        #expect(CalendarFlipTimeline.opacity(at: 0) == 1)
        #expect(CalendarFlipTimeline.opacity(at: CalendarFlipTimeline.half) == 0)
        #expect(CalendarFlipTimeline.opacity(at: CalendarFlipTimeline.duration) == 1)
        let mid = CalendarFlipTimeline.opacity(at: CalendarFlipTimeline.half / 2)
        #expect(mid > 0 && mid < 1)
    }

    @Test func klartEfterLangden() {
        #expect(!CalendarFlipTimeline.isFinished(at: CalendarFlipTimeline.duration - 0.01))
        #expect(CalendarFlipTimeline.isFinished(at: CalendarFlipTimeline.duration))
    }
}
