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
    #expect(s.enabledTimings == [.eveningBefore] && s.liveActivityTiming == .eveningBefore)
    #expect(s.reminderMinutes == 1140)
    #expect(s.morningMinutes == 360)
}

@Test func okäntValLäsesSomKvällenFöre() throws {
    let json = #"{"reminderMinutes":1080,"liveActivityOn":false,"timing":"lunch","morningMinutes":420}"#
    let s = try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
    #expect(s.enabledTimings == [.eveningBefore] && s.liveActivityTiming == .eveningBefore)
    #expect(s.morningMinutes == 420)
}

@Test func bådaTidernaSparas() throws {
    let s = ReminderSettings(eveningOn: false, morningOn: true, reminderMinutes: 1200, morningMinutes: 420, liveActivityTiming: .sameMorning)
    let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test(arguments: [(285, false), (300, true), (540, true), (555, false), (310, false), (1080, false)])
func giltigMorgontid(m: Int, ok: Bool) {
    #expect(ReminderSettings.isValid(minutes: m, for: .sameMorning) == ok)
}

@Test func trasigKvällstidPåverkarInteMorgonen() {
    let s = ReminderSettings(eveningOn: false, morningOn: true, reminderMinutes: 5, morningMinutes: 420, liveActivityTiming: .sameMorning)
    #expect(s.minutes(for: .sameMorning) == 420)
    #expect(ReminderSettings(eveningOn: false, morningOn: true, morningMinutes: 1000, liveActivityTiming: .sameMorning).minutes(for: .sameMorning) == 360)
    #expect(ReminderSettings(reminderMinutes: 5).minutes(for: .eveningBefore) == 1080)
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
    let morning = ReminderSettings(eveningOn: false, morningOn: true, morningMinutes: 360, liveActivityTiming: .sameMorning)
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), timing: .eveningBefore, settings: evening) == stockholm("2026-11-10T18:00"))
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), timing: .sameMorning, settings: morning) == stockholm("2026-11-11T06:00"))
    // Sommartiden slutar 2026-10-25, så klockslaget ska stå kvar i svensk tid.
    #expect(ReminderTime.date(forPickup: day("2026-10-26"), timing: .eveningBefore, settings: evening) == stockholm("2026-10-25T18:00"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .eveningBefore) == day("2026-11-11"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .sameMorning) == day("2026-11-10"))
}

private func decode(_ json: String) throws -> ReminderSettings {
    try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
}

private func event(_ iso: String, _ fractions: [String]) -> PickupEvent {
    PickupEvent(date: day(iso), fractions: fractions, estimated: false, deviation: nil, warning: nil, labels: [:])
}

@Test func gammalKvällLäses() throws {
    let s = try decode(#"{"timing":"eveningBefore","reminderMinutes":1140,"morningMinutes":420,"liveActivityOn":true}"#)
    #expect(s.eveningOn && !s.morningOn && s.liveActivityTiming == .eveningBefore)
    #expect(s.minutes(for: .eveningBefore) == 1140 && s.minutes(for: .sameMorning) == 420)
}
@Test func gammalMorgonLäses() throws {
    let s = try decode(#"{"timing":"sameMorning","reminderMinutes":1080,"morningMinutes":420,"liveActivityOn":false}"#)
    #expect(!s.eveningOn && s.morningOn && s.liveActivityTiming == .sameMorning)
}
@Test func utanTimingOchOkändTimingBlirKväll() throws {
    #expect(try decode(#"{"reminderMinutes":1080,"liveActivityOn":false}"#).enabledTimings == [.eveningBefore])
    #expect(try decode(#"{"timing":"lunch","reminderMinutes":1080,"liveActivityOn":false}"#).enabledTimings == [.eveningBefore])
}
@Test func bådaAvLäsesSomKväll() throws {
    let s = try decode(#"{"eveningOn":false,"morningOn":false,"reminderMinutes":1080,"liveActivityOn":false}"#)
    #expect(s.enabledTimings == [.eveningBefore])
}
@Test func nyaFältenSparasOchTimingSkrivsInte() throws {
    let s = ReminderSettings(eveningOn: true, morningOn: true, morningMinutes: 420, liveActivityTiming: .sameMorning)
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(ReminderSettings.self, from: data) == s)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"timing\""))
}
@Test func ogiltigTidGerFörval() {
    let s = ReminderSettings(reminderMinutes: 5, morningMinutes: 1000)
    #expect(s.minutes(for: .eveningBefore) == 1080 && s.minutes(for: .sameMorning) == 360)
}
@Test func värdetPåRaden() {
    #expect(ReminderSettings().settingsValue == "Kvällen före, 18:00")
    #expect(ReminderSettings(eveningOn: false, morningOn: true).settingsValue == "Samma morgon, 06:00")
    #expect(ReminderSettings(morningOn: true, morningMinutes: 420).settingsValue == "18:00 och 07:00")
}
@Test func nästaPåminnelse() {
    let s = ReminderSettings(morningOn: true)
    let events = [event("2026-11-11", ["rest"])]
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-10T12:00"))
        == .init(pickup: day("2026-11-11"), timing: .eveningBefore, date: stockholm("2026-11-10T18:00")))
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-10T19:00"))?.timing == .sameMorning)
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-11T07:00")) == nil)
}
