import Foundation
import Testing
@testable import SophamtningKit

private func decode(_ json: String) throws -> ReminderSettings {
    try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
}

@Test func gammalInställningFårNotisensTid() throws {
    let evening = try decode(#"{"eveningOn":true,"morningOn":true,"reminderMinutes":1140,"morningMinutes":420,"liveActivityTiming":"eveningBefore","liveActivityOn":true}"#)
    #expect(evening.liveActivityStartMinutes == 1140)
    let morning = try decode(#"{"eveningOn":true,"morningOn":false,"reminderMinutes":1140,"morningMinutes":420,"liveActivityTiming":"sameMorning","liveActivityOn":true}"#)
    #expect(morning.liveActivityStartMinutes == 420)
}

@Test func egenTidSparasOchÄrOberoende() throws {
    var s = ReminderSettings(reminderMinutes: 900, liveActivityMinutes: 1260)
    #expect(s.liveActivityStartMinutes == 1260)
    #expect(s.minutes(for: .eveningBefore) == 900)
    s.reminderMinutes = 1080
    #expect(s.liveActivityStartMinutes == 1260)
    let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test func ogiltigAktivitetstidGerNotisensTid() {
    // 21:00 går inte på morgonen, så morgonens notistid gäller.
    let s = ReminderSettings(morningMinutes: 420, liveActivityTiming: .sameMorning, liveActivityMinutes: 1260)
    #expect(s.liveActivityStartMinutes == 420)
}

@Test func aktivitetensTidFörTömning() {
    let s = ReminderSettings(reminderMinutes: 900, liveActivityMinutes: 1260)
    #expect(ReminderTime.liveActivityStart(forPickup: DayDate("2026-11-25")!, settings: s) == StockholmClock.date(on: DayDate("2026-11-24")!, minutes: 1260))
}

@Test func textenVisarHelaTiden() {
    #expect(AddressDetail.liveActivityText(settings: ReminderSettings(liveActivityMinutes: 1260)) == "Visas på låsskärmen kl. 21:00 dagen före till 09:00.")
    #expect(AddressDetail.liveActivityText(settings: ReminderSettings(liveActivityMinutes: 900)) == "Visas på låsskärmen kl. 15:00 dagen före till 03:00.")
    #expect(AddressDetail.liveActivityText(settings: ReminderSettings(liveActivityTiming: .sameMorning, liveActivityMinutes: 360)) == "Visas på låsskärmen kl. 06:00–18:00 samma dag.")
}

@Test func tidslistansTextFörAktiviteten() {
    #expect(ReminderTiming.liveActivityTimesFooter == "iOS visar en Live Activity i högst 12 timmar. Den försvinner tidigare när du trycker Klart, sveper bort den eller någon i hushållet ställer ut.")
}
