import Testing
import Foundation
import SophamtningKit

private func day(_ iso: String) -> DayDate { DayDate(iso)! }

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false, warning: String? = nil) -> PickupEvent {
    PickupEvent(date: day(iso), fractions: fractions, estimated: estimated, deviation: nil, warning: warning, labels: [:])
}

private let events = [
    event("2026-11-01", ["rest"]),
    event("2026-11-09", ["rest", "plast"]),
    event("2026-11-12", ["glas"]),
]

@Test func filtrerarBortPasseradeDatum() {
    let upcoming = ScheduleLogic.upcoming(events, today: day("2026-11-09"))
    #expect(upcoming.map(\.date) == [day("2026-11-09"), day("2026-11-12")])
}

@Test func upcomingSortererarPaDatum() {
    let shuffled = [events[2], events[1]]
    #expect(ScheduleLogic.upcoming(shuffled, today: day("2026-11-01")).map(\.date) == [day("2026-11-09"), day("2026-11-12")])
}

@Test func nastaHamtningArForstaKommande() {
    #expect(ScheduleLogic.nextPickup(events, today: day("2026-11-10"))?.date == day("2026-11-12"))
}

@Test func baraPasseradeDatumGerIngenNastaHamtning() {
    #expect(ScheduleLogic.nextPickup(events, today: day("2027-01-10")) == nil)
    #expect(ScheduleLogic.nextByFraction(events, today: day("2027-01-10")).isEmpty)
}

@Test func dagarKvarRaknasFranGivenDag() throws {
    let list = [event("2026-11-11", ["plast"])]
    #expect(try #require(ScheduleLogic.nextByFraction(list, today: day("2026-11-08")).first).daysUntil == 3)
    #expect(try #require(ScheduleLogic.nextByFraction(list, today: day("2026-11-10")).first).daysUntil == 1)
}

@Test func nastaPerFraktionGerForstaDatumSorteratMedStabilOrdning() {
    let list = [
        event("2026-11-12", ["rest", "glas"], warning: "Sen tömning"),
        event("2026-11-10", ["plast", "papper"], estimated: true),
        event("2026-11-20", ["plast"]),
    ]
    let result = ScheduleLogic.nextByFraction(list, today: day("2026-11-09"))
    #expect(result.map(\.fraction) == ["papper", "plast", "glas", "rest"])
    #expect(result.map(\.daysUntil) == [1, 1, 3, 3])
    #expect(result[1].estimated)
    #expect(result[1].warning == nil)
    #expect(!result[2].estimated)
    #expect(result[2].warning == "Sen tömning")
}

@Test func dagensDatumRaknasSomNollDagar() {
    let result = ScheduleLogic.nextByFraction([event("2026-11-09", ["rest"])], today: day("2026-11-09"))
    #expect(result.first?.daysUntil == 0)
}

@Test func okandFraktionGarTillIdEfterNamn() {
    let info = ScheduleLogic.displayInfo(for: "tradgard", in: [:])
    #expect(info.name == "tradgard")
    #expect(info.short == "tradgard")
    #expect(info.color == "#526158")
    #expect(info.icon == "recycle")
}

@Test func kandFraktionAnvandsOforandrad() {
    let glas = FractionInfo(name: "Glas", short: "Glas", color: "#1F6A7A", icon: "wine")
    #expect(ScheduleLogic.displayInfo(for: "glas", in: ["glas": glas]) == glas)
}
