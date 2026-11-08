import Testing
import Foundation
import SophamtningKit

private let today = DayDate("2026-12-27")!

private func period(daysLeft: Int, reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget.") -> SchedulePeriod {
    SchedulePeriod(until: today.adding(days: daysLeft), reason: reason)
}

@Suite struct ScheduleEndingTests {
    @Test func femtonDagarKvarVisasInte() {
        #expect(ScheduleEnding.make(period(daysLeft: 15), today: today) == nil)
    }

    @Test func fjortonDagarKvarVisas() throws {
        let ending = try #require(ScheduleEnding.make(period(daysLeft: 14), today: today))
        #expect(ending.daysLeft == 14)
        #expect(ending.until == DayDate("2027-01-10"))
    }

    @Test func enDagKvarVisas() throws {
        #expect(try #require(ScheduleEnding.make(period(daysLeft: 1), today: today)).daysLeft == 1)
    }

    @Test func sistaDagenArInraknad() throws {
        // `until` är sista dagen som schemat gäller, så den dagen visas rutan fortfarande.
        #expect(try #require(ScheduleEnding.make(period(daysLeft: 0), today: today)).daysLeft == 0)
    }

    @Test func passeratDatumVisasInte() {
        #expect(ScheduleEnding.make(period(daysLeft: -1), today: today) == nil)
        #expect(ScheduleEnding.make(period(daysLeft: -60), today: today) == nil)
    }

    @Test func utanPeriodVisasInte() {
        #expect(ScheduleEnding.make(nil, today: today) == nil)
    }

    @Test func kortRadenHarKortDatumUtanAr() throws {
        let ending = try #require(ScheduleEnding.make(period(daysLeft: 14), today: today))
        #expect(ending.shortText == "Schemat slutar 10 jan")
        #expect(ending.spokenText == "Schemat slutar 10 januari")
    }

    @Test func rutanHarKallansOrsakOchSagerAttNyaTiderKommer() throws {
        let ending = try #require(ScheduleEnding.make(period(daysLeft: 10), today: today))
        #expect(ending.title == "Schemat tar snart slut")
        #expect(ending.message == "Avesta Vatten publicerar hämtschemat ett år i taget. Nya tider visas när källan publicerar dem.")
    }

    @Test func rutanUtanOrsak() throws {
        let missing = try #require(ScheduleEnding.make(period(daysLeft: 10, reason: nil), today: today))
        #expect(missing.message == "Nya tider visas när källan publicerar dem.")
        let blank = try #require(ScheduleEnding.make(period(daysLeft: 10, reason: "  \n"), today: today))
        #expect(blank.message == "Nya tider visas när källan publicerar dem.")
    }

    @Test func orsakenUtanPunktFarEnPunkt() throws {
        let ending = try #require(ScheduleEnding.make(period(daysLeft: 3, reason: "Schemat gäller ett år"), today: today))
        #expect(ending.message == "Schemat gäller ett år. Nya tider visas när källan publicerar dem.")
    }

    @Test func lovarAldrigAttPaminnelserFortsatter() throws {
        // Appen kan inte lova att påminnelserna läggs om av sig själva, så texten säger det inte.
        let ending = try #require(ScheduleEnding.make(period(daysLeft: 3), today: today))
        #expect(!ending.message.localizedCaseInsensitiveContains("påminnelse"))
    }

    @Test func dagenRaknasISvenskTidOavsettTelefonensTidszon() throws {
        // 00:30 den 27 dec i Stockholm är 18:30 den 26:e i New York. Dagen är ändå den 27:e, så 10 jan är 14 dagar kvar.
        let early = StockholmClock.date(on: DayDate("2026-12-27")!, minutes: 30)
        let day = StockholmClock.today(now: early)
        #expect(day == DayDate("2026-12-27"))
        let ending = try #require(ScheduleEnding.make(SchedulePeriod(until: DayDate("2027-01-10")!, reason: nil), today: day))
        #expect(ending.daysLeft == 14)
    }
}
