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
        #expect(CalendarFlipTimeline.currentPage(at: -0.5, pages: 1) == 0)
        #expect(CalendarFlipTimeline.angle(at: -0.5) == 0)
        #expect(CalendarFlipTimeline.opacity(at: -0.5) == 1)
        #expect(CalendarFlipTimeline.currentPage(at: CalendarFlipTimeline.duration, pages: 1) == 1)
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
        #expect(CalendarFlipTimeline.currentPage(at: 0, pages: 1) == 0)
        #expect(CalendarFlipTimeline.currentPage(at: CalendarFlipTimeline.half - 0.001, pages: 1) == 0)
        #expect(CalendarFlipTimeline.currentPage(at: CalendarFlipTimeline.half, pages: 1) == 1)
        #expect(CalendarFlipTimeline.currentPage(at: 10, pages: 1) == 1)
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

    // MARK: Flera blad

    private func day(_ text: String) -> DayDate { DayDate(text)! }

    @Test func enDagGerEttBladSomForut() {
        #expect(CalendarFlipTimeline.dates(from: day("2026-11-07"), to: day("2026-11-08"), reduceMotion: false) == [day("2026-11-08")])
        #expect(CalendarFlipTimeline.duration(pages: 1) == 0.6)
        #expect(CalendarFlipTimeline.duration(pages: 1) == CalendarFlipTimeline.duration)
    }

    @Test func ettBladPerDagUpptillAtta() {
        let from = day("2026-11-07")
        #expect(CalendarFlipTimeline.dates(from: from, to: day("2026-11-12"), reduceMotion: false).map(\.iso)
                == ["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12"])
        let eight = CalendarFlipTimeline.dates(from: from, to: day("2026-11-15"), reduceMotion: false)
        #expect(eight == (1...8).map { from.adding(days: $0) })
    }

    @Test func flerDagarGerAttaJamntFordeladeBladDarSistaArTomningsdagen() {
        let from = day("2026-11-07")
        for days in [9, 13, 20, 31, 90] {
            let to = from.adding(days: days)
            let dates = CalendarFlipTimeline.dates(from: from, to: to, reduceMotion: false)
            #expect(dates.count == 8, "\(days) dagar")
            #expect(dates.last == to, "\(days) dagar")
            let steps = zip([from] + dates, dates).map { $0.days(until: $1) }
            #expect(steps.allSatisfy { $0 >= 1 }, "\(days) dagar")
            #expect(steps.max()! - steps.min()! <= 1, "jämnt fördelade, \(days) dagar: \(steps)")
        }
    }

    @Test func bakatOchReduceraRorelseGerEttBlad() {
        let from = day("2026-11-12")
        #expect(CalendarFlipTimeline.dates(from: from, to: day("2026-11-07"), reduceMotion: false) == [day("2026-11-07")])
        #expect(CalendarFlipTimeline.dates(from: day("2026-11-07"), to: from, reduceMotion: true) == [from])
        #expect(CalendarFlipTimeline.dates(from: day("2026-11-07"), to: day("2027-01-20"), reduceMotion: true) == [day("2027-01-20")])
    }

    @Test func flerBladGarFortarePerBladOchAlltArKlartInom12() {
        var previous = CalendarFlipTimeline.duration(pages: 1)
        for pages in 2...8 {
            let total = CalendarFlipTimeline.duration(pages: pages)
            #expect(total <= 1.2, "\(pages) blad")
            #expect(total > previous, "fler blad tar lite längre tid totalt, \(pages) blad")
            #expect(total / Double(pages) < 0.6, "\(pages) blad")
            previous = total
        }
    }

    @Test func varjeBladVisasIOrdningOchSistaBladetArTomningsdagen() {
        let from = day("2026-11-07")
        let dates = CalendarFlipTimeline.dates(from: from, to: day("2026-11-12"), reduceMotion: false)
        let total = CalendarFlipTimeline.duration(pages: dates.count)
        let shown = stride(from: -0.1, through: total + 0.1, by: 0.002).map { CalendarFlipTimeline.shownDate(at: $0, from: from, dates: dates) }
        // Varje datum visas, i ordning, och inget annat.
        var distinct: [DayDate] = []
        for date in shown where distinct.last != date { distinct.append(date) }
        #expect(distinct == [from] + dates)
        #expect(CalendarFlipTimeline.shownDate(at: total, from: from, dates: dates) == day("2026-11-12"))
        #expect(CalendarFlipTimeline.isFinished(at: total, pages: dates.count))
        #expect(!CalendarFlipTimeline.isFinished(at: total - 0.01, pages: dates.count))
    }

    @Test func bladetBytsMittIVarjeVandning() {
        let pages = 5
        let samples = stride(from: 0.0, through: CalendarFlipTimeline.duration(pages: pages), by: 0.001).map {
            (page: CalendarFlipTimeline.currentPage(at: $0, pages: pages), angle: CalendarFlipTimeline.angle(at: $0, pages: pages))
        }
        // Där bladet byts står det på kanten: vinkeln hoppar från nästan -90 till 90.
        for (before, after) in zip(samples, samples.dropFirst()) where after.page != before.page {
            #expect(after.page == before.page + 1)
            #expect(before.angle < -80 && after.angle > 80)
        }
        #expect(samples.allSatisfy { $0.angle >= -90 && $0.angle <= 90 })
        #expect(samples.first!.angle == 0 && samples.last!.angle == 0)
    }

    @Test func sistaBladetGarLangsammareAnDetForsta() {
        let pages = 8
        let times = stride(from: 0.0, through: CalendarFlipTimeline.duration(pages: pages), by: 0.0005).map { ($0, CalendarFlipTimeline.currentPage(at: $0, pages: pages)) }
        let changes = zip(times, times.dropFirst()).filter { $0.1 != $1.1 }.map { $1.0 }
        #expect(changes.count == pages)
        let gaps = zip(changes, changes.dropFirst()).map { $1 - $0 }
        #expect(gaps.last! > gaps.first! * 1.5, "bromsar in mot slutet: \(gaps)")
        // Inget blad är så kort att det inte syns, även med 8 blad.
        #expect(gaps.min()! > 0.08)
    }

    @Test func manadsradenFoljerMedOverManadsskiftet() {
        let from = day("2026-11-28")
        let dates = CalendarFlipTimeline.dates(from: from, to: day("2026-12-03"), reduceMotion: false)
        let total = CalendarFlipTimeline.duration(pages: dates.count)
        let shown = Set(stride(from: 0.0, through: total, by: 0.002).map { CalendarFlipTimeline.shownDate(at: $0, from: from, dates: dates) })
        #expect(shown.contains(day("2026-11-30")))
        #expect(shown.contains(day("2026-12-01")))
        #expect(SwedishFormat.monthUppercased(day("2026-11-30")) != SwedishFormat.monthUppercased(day("2026-12-01")))
    }
}
