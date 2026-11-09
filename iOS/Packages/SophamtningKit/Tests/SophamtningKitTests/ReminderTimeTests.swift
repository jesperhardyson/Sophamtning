import Testing
import Foundation
@testable import SophamtningKit

private func day(_ iso: String) -> DayDate { DayDate(iso)! }

/// "2026-11-08T20:00" som väggklocka i Europe/Stockholm.
private func stockholm(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.date(from: text)!
}

@Test func gamlaInställningarLäsesSomKvällenFöre() throws {
    let json = #"{"reminderMinutes":1140,"liveActivityOn":true}"#
    let s = try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
    #expect(s.timing == .eveningBefore)
    #expect(s.reminderMinutes == 1140)
    #expect(s.morningMinutes == 360)
}

@Test func okäntValLäsesSomKvällenFöre() throws {
    let json = #"{"reminderMinutes":1080,"liveActivityOn":false,"timing":"lunch","morningMinutes":420}"#
    let s = try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
    #expect(s.timing == .eveningBefore)
    #expect(s.morningMinutes == 420)
}

@Test func bådaTidernaSparas() throws {
    let s = ReminderSettings(timing: .sameMorning, reminderMinutes: 1200, morningMinutes: 420)
    let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test(arguments: [(285, false), (300, true), (540, true), (555, false), (310, false), (1080, false)])
func giltigMorgontid(m: Int, ok: Bool) {
    #expect(ReminderSettings.isValid(minutes: m, for: .sameMorning) == ok)
}

@Test func trasigKvällstidPåverkarInteMorgonen() {
    let s = ReminderSettings(timing: .sameMorning, reminderMinutes: 5, morningMinutes: 420)
    #expect(s.activeMinutes == 420)
    #expect(ReminderSettings(timing: .sameMorning, morningMinutes: 1000).activeMinutes == 360)
    #expect(ReminderSettings(reminderMinutes: 5).activeMinutes == 1080)
}

@Test func tiderFörValen() {
    #expect(ReminderTiming.eveningBefore.defaultMinutes == 1080)
    #expect(ReminderTiming.sameMorning.defaultMinutes == 360)
    #expect(ReminderTiming.sameMorning.times.first == 300)
    #expect(ReminderTiming.sameMorning.times.last == 540)
    #expect(ReminderTiming.sameMorning.times.count == 17)
    #expect(ReminderTiming.eveningBefore.times.count == 33)
}

@Test func tidFörTömning() {
    let evening = ReminderSettings(reminderMinutes: 1080)
    let morning = ReminderSettings(timing: .sameMorning, morningMinutes: 360)
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), settings: evening) == stockholm("2026-11-10T18:00"))
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), settings: morning) == stockholm("2026-11-11T06:00"))
    // Sommartiden slutar 2026-10-25, så klockslaget ska stå kvar i svensk tid.
    #expect(ReminderTime.date(forPickup: day("2026-10-26"), settings: evening) == stockholm("2026-10-25T18:00"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .eveningBefore) == day("2026-11-11"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .sameMorning) == day("2026-11-10"))
}
