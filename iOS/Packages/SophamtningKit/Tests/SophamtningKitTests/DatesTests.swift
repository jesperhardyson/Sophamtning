import Testing
import Foundation
import SophamtningKit

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

private func day(_ iso: String) -> DayDate {
    DayDate(iso)!
}

@Test func idagFoljerStockholmEfterMidnatt() {
    // 2026-11-08 23:30 UTC är 00:30 den 9 november i Sverige
    #expect(StockholmClock.today(now: utc("2026-11-08T23:30:00Z")) == day("2026-11-09"))
}
@Test func artonNollNollVidOmstallning() {
    #expect(StockholmClock.date(on: day("2026-11-08"), minutes: 1080) == utc("2026-11-08T17:00:00Z"))
    #expect(StockholmClock.date(on: day("2027-03-28"), minutes: 1080) == utc("2027-03-28T16:00:00Z"))
    #expect(StockholmClock.date(on: day("2027-10-31"), minutes: 1080) == utc("2027-10-31T17:00:00Z"))
}
@Test func svenskaTexter() {
    #expect(SwedishFormat.longDate(day("2026-11-09"), capitalized: true) == "Måndag 9 november")
    #expect(SwedishFormat.longDate(day("2026-11-09"), capitalized: false) == "måndag 9 november")
    #expect(SwedishFormat.shortDate(day("2026-11-09")) == "Mån 9 nov")
    #expect(SwedishFormat.relative(days: 0) == "i dag")
    #expect(SwedishFormat.relative(days: 1) == "i morgon")
    #expect(SwedishFormat.relative(days: 2) == "i övermorgon")
    #expect(SwedishFormat.relative(days: 3) == "om 3 dagar")
    #expect(SwedishFormat.estimated("tors 12 nov", true) == "ca tors 12 nov")
}
@Test func ogiltigtDatumGerNil() { #expect(DayDate("2026-13-40") == nil) }
