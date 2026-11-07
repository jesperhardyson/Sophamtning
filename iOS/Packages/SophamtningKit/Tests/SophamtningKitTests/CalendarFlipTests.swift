import Foundation
import SophamtningKit
import Testing
@testable import SophamtningDesign

@Suite struct CalendarFlipTests {
    private func day(_ text: String) -> DayDate { DayDate(text)! }

    // MARK: Start och datum

    @Test func vidStartVandsBladetFranDagensDatumTillTomningsdagen() {
        let today = day("2026-11-07")
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: day("2026-11-12")) == today)
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: day("2026-11-08")) == today)
    }

    @Test func tomningIDagVandsInte() {
        let today = day("2026-11-07")
        #expect(CalendarFlipTimeline.openingDate(today: today, pickup: today) == nil)
    }

    @Test func ettBladPerDagUpptillAtta() {
        let from = day("2026-11-07")
        #expect(CalendarFlipTimeline.dates(from: from, to: day("2026-11-08"), reduceMotion: false) == [day("2026-11-08")])
        #expect(CalendarFlipTimeline.dates(from: from, to: day("2026-11-11"), reduceMotion: false).map(\.iso)
                == ["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11"])
        #expect(CalendarFlipTimeline.dates(from: from, to: day("2026-11-15"), reduceMotion: false) == (1...8).map { from.adding(days: $0) })
    }

    @Test func flerDagarGerAttaJamntFordeladeBladDarSistaArTomningsdagen() {
        let from = day("2026-11-07")
        for days in [9, 13, 20, 30, 31, 90] {
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
        #expect(CalendarFlipTimeline.dates(from: day("2026-11-12"), to: day("2026-11-07"), reduceMotion: false) == [day("2026-11-07")])
        #expect(CalendarFlipTimeline.dates(from: day("2026-11-07"), to: day("2027-01-20"), reduceMotion: true) == [day("2027-01-20")])
    }

    // MARK: Start per blad och total tid

    @Test func bladenStartarCirkaVar60eMsOchBromsarIn() {
        let four = CalendarFlipTimeline.starts(pages: 4)
        #expect(four.count == 4)
        #expect(four[0] == 0)
        #expect(abs(four[1] - 0.06) < 0.0001)
        let gaps = zip(four, four.dropFirst()).map { $1 - $0 }
        #expect(zip(gaps, gaps.dropFirst()).allSatisfy { $0 < $1 }, "mellanrummen växer: \(gaps)")
        #expect(abs(gaps.last! - 1.5 * gaps.first!) < 0.0001)
        #expect(CalendarFlipTimeline.starts(pages: 1) == [0])
        #expect(CalendarFlipTimeline.starts(pages: 2) == [0, 0.06])
    }

    @Test func ettBladTarEnKvartsSekundOchAllaHogst06() {
        #expect(CalendarFlipTimeline.foldDuration == 0.25)
        #expect(CalendarFlipTimeline.duration(pages: 1) == 0.25)
        #expect(abs(CalendarFlipTimeline.duration(pages: 4) - 0.475) < 0.0001)
        #expect(abs(CalendarFlipTimeline.duration(pages: 8) - 0.6) < 0.0001)
        var previous = 0.0
        for pages in 1...8 {
            let total = CalendarFlipTimeline.duration(pages: pages)
            #expect(total <= 0.6 + 0.0001, "\(pages) blad")
            #expect(total >= previous, "fler blad tar aldrig kortare tid, \(pages) blad")
            previous = total
        }
        #expect(CalendarFlipTimeline.longest == 0.6)
    }

    @Test func attaBladHarAndaSynligaMellanrum() {
        let starts = CalendarFlipTimeline.starts(pages: 8)
        let gaps = zip(starts, starts.dropFirst()).map { $1 - $0 }
        #expect(gaps.min()! >= 0.035, "\(gaps)")
        #expect(gaps.last! > gaps.first!)
    }

    @Test func klartEfterLangden() {
        #expect(!CalendarFlipTimeline.isFinished(at: 0.47, pages: 4))
        #expect(CalendarFlipTimeline.isFinished(at: 0.475, pages: 4))
        #expect(CalendarFlipTimeline.isFinished(at: 0.4, pages: 4, reduceMotion: true))
        #expect(!CalendarFlipTimeline.isFinished(at: 0.39, pages: 4, reduceMotion: true))
    }

    // MARK: Överst och under

    @Test func foreStartenLiggerForstaBladetEnsamt() {
        for t in [-0.5, 0.0] {
            let layers = CalendarFlipTimeline.layers(at: t, pages: 4)
            #expect(layers.under == 0)
            #expect(layers.folds.isEmpty)
            #expect(layers.top == 0)
        }
    }

    @Test func nastaBladLiggerRedanUnderDetSomViks() {
        // 0,03 s: blad 0 viks, blad 1 ligger under.
        let early = CalendarFlipTimeline.layers(at: 0.03, pages: 4)
        #expect(early.folds.map(\.sheet) == [0])
        #expect(early.under == 1)
        #expect(early.top == 0)
        // 0,15 s: tre blad viks samtidigt och överlappar, blad 3 ligger under.
        let mid = CalendarFlipTimeline.layers(at: 0.15, pages: 4)
        #expect(mid.folds.map(\.sheet) == [0, 1, 2])
        #expect(mid.under == 3)
        #expect(mid.folds[0].progress > mid.folds[1].progress)
        // Det sista bladet viks och tömningsdagen ligger under.
        let late = CalendarFlipTimeline.layers(at: 0.4, pages: 4)
        #expect(late.folds.map(\.sheet) == [3])
        #expect(late.under == 4)
    }

    @Test func varjeTidpunktHarEttBladUnderSomInteViks() {
        for pages in 1...8 {
            let total = CalendarFlipTimeline.duration(pages: pages)
            for t in stride(from: -0.05, through: total + 0.05, by: 0.001) {
                let layers = CalendarFlipTimeline.layers(at: t, pages: pages)
                #expect(layers.under >= 0 && layers.under <= pages)
                #expect(layers.folds.allSatisfy { $0.sheet < layers.under && $0.progress > 0 && $0.progress < 1 })
            }
        }
    }

    @Test func efterSlutetLiggerTomningsdagenEnsam() {
        let layers = CalendarFlipTimeline.layers(at: CalendarFlipTimeline.duration(pages: 8), pages: 8)
        #expect(layers.under == 8)
        #expect(layers.folds.isEmpty)
    }

    @Test func varjeDatumLiggerOverstIOrdningOchSistaArTomningsdagen() {
        let from = day("2026-11-07")
        let dates = CalendarFlipTimeline.dates(from: from, to: day("2026-11-11"), reduceMotion: false)
        let total = CalendarFlipTimeline.duration(pages: dates.count)
        var underDates: [DayDate] = []
        for t in stride(from: -0.1, through: total + 0.1, by: 0.001) {
            let under = CalendarFlipTimeline.date(ofSheet: CalendarFlipTimeline.layers(at: t, pages: dates.count).under, from: from, dates: dates)
            if underDates.last != under { underDates.append(under) }
        }
        #expect(underDates == [from] + dates)
        #expect(CalendarFlipTimeline.shownDate(at: total, from: from, dates: dates) == day("2026-11-11"))
        #expect(CalendarFlipTimeline.shownDate(at: 0, from: from, dates: dates) == from)
    }

    @Test func manadsradenFoljerMedOverManadsskiftet() {
        let from = day("2026-11-07")
        let dates = CalendarFlipTimeline.dates(from: from, to: day("2026-12-07"), reduceMotion: false)
        let shown = (0...dates.count).map { CalendarFlipTimeline.date(ofSheet: $0, from: from, dates: dates) }
        #expect(shown.first == from)
        #expect(shown.last == day("2026-12-07"))
        #expect(Set(shown.map { SwedishFormat.monthUppercased($0) }) == ["NOV", "DEC"])
    }

    // MARK: Vinkel och toning

    @Test func bladetViksUppFranRaktTillKanten() {
        #expect(CalendarFlipTimeline.angle(progress: 0) == 0)
        #expect(CalendarFlipTimeline.angle(progress: 1) == 90)
        let angles = stride(from: 0.0, through: 1, by: 0.05).map { CalendarFlipTimeline.angle(progress: $0) }
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func reduceraRorelseGerEnToning() {
        #expect(CalendarFlipTimeline.opacity(at: 0) == 1)
        #expect(CalendarFlipTimeline.opacity(at: 0.2) == 0)
        #expect(CalendarFlipTimeline.opacity(at: 0.4) == 1)
        let from = day("2026-11-07"), to = day("2026-11-11")
        #expect(CalendarFlipTimeline.fadedDate(at: 0.19, from: from, to: to) == from)
        #expect(CalendarFlipTimeline.fadedDate(at: 0.2, from: from, to: to) == to)
        #expect(CalendarFlipTimeline.duration(pages: 8, reduceMotion: true) == 0.4)
    }

    // MARK: Vibrationer

    @Test func enLattVibrationPerBladOchEnTydligareNarDetLandar() {
        for pages in [1, 4, 8] {
            let haptics = CalendarFlipTimeline.haptics(pages: pages, reduceMotion: false)
            #expect(haptics.filter { $0.kind == .page }.count == pages)
            #expect(haptics.filter { $0.kind == .landing }.count == 1)
            #expect(haptics.last == .init(time: CalendarFlipTimeline.duration(pages: pages), kind: .landing))
            #expect(haptics.filter { $0.kind == .page }.map(\.time) == CalendarFlipTimeline.starts(pages: pages))
        }
    }

    @Test func ingenVibrationMedReduceraRorelse() {
        #expect(CalendarFlipTimeline.haptics(pages: 4, reduceMotion: true).isEmpty)
    }
}
