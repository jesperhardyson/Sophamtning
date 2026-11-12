import Testing
import Foundation
@testable import SophamtningKit

private let key = AddressKey(source: "kallor", id: "hem")
private let wednesday = DayDate("2026-11-11")!
private let nextWednesday = DayDate("2026-11-18")!
private let morning = ReminderSettings(eveningOn: false, morningOn: true, morningMinutes: 360, liveActivityTiming: .sameMorning)

private func at(_ day: String, _ hour: Int) -> Date {
    StockholmClock.date(on: DayDate(day)!, minutes: hour * 60)
}

private func event(_ date: DayDate) -> PickupEvent {
    PickupEvent(date: date, fractions: ["rest"], estimated: false, deviation: nil, warning: nil, labels: [:])
}

private func saved(notifications: Bool) -> SavedAddress {
    SavedAddress(key: key, url: URL(string: "https://example.com/hem")!, street: "Storgatan 1", locality: "Krylbo", kommun: "Avesta kommun",
                 detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, notificationsOn: notifications, addedAt: Date(timeIntervalSince1970: 0))
}

private func schedule(_ events: [PickupEvent]) -> CachedSchedule {
    let response = AddressResponse(
        today: DayDate("2026-11-06")!,
        address: Address(id: key.id, street: "Storgatan 1", locality: "Krylbo", kommun: "Avesta kommun", source: key.source, detail: nil, selection: "address", notice: nil),
        next: [], summary: "", events: events, bins: [],
        fractions: ["rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")],
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: DayDate("2026-11-06")!
    )
    return CachedSchedule(response: response, fetchedAt: at("2026-11-06", 10))
}

@Test func reglagetsNamn() {
    #expect(ReminderTiming.eveningBefore.toggleTitle == "Påminn mig kvällen före")
    #expect(ReminderTiming.sameMorning.toggleTitle == "Påminn mig samma morgon")
    #expect(ReminderTiming.sameMorning.actionTitle(isOn: true) == "Stäng av påminnelse samma morgon")
    #expect(ReminderTiming.sameMorning.actionTitle(isOn: false) == "Slå på påminnelse samma morgon")
    #expect(ReminderTiming.eveningBefore.actionTitle(isOn: false) == "Slå på påminnelse kvällen före")
    #expect(HomeContent.reminderTitle(timing: .sameMorning) == "Påminn mig samma morgon")
    #expect(HomeContent.reminderActionTitle(isOn: false, timing: .sameMorning) == "Slå på påminnelse samma morgon")
}

@Test func inställningensTexter() {
    #expect(ReminderTiming.eveningBefore.title == "Kvällen före")
    #expect(ReminderTiming.sameMorning.title == "Samma morgon")
    #expect(ReminderTiming.eveningBefore.settingsValue(minutes: 1080) == "Kvällen före, 18:00")
    #expect(ReminderTiming.sameMorning.settingsValue(minutes: 360) == "Samma morgon, 06:00")
    #expect(ReminderTiming.eveningBefore.settingsFooter == "Påminnelsen kommer kvällen före, mellan 15:00 och 23:00. En Live Activity försvinner senast 12 timmar efter starten, så en sen tid håller den kvar längre på morgonen. Notiser väljer du per adress.")
    #expect(ReminderTiming.sameMorning.settingsFooter == "Påminnelsen kommer samma morgon som tömningen, mellan 05:00 och 09:00. En Live Activity syns tills du trycker Klart, eller i högst 12 timmar. Notiser väljer du per adress.")
}

@Test func radenUnderReglagetPåMorgonen() {
    let events = [event(wednesday), event(nextWednesday)]
    #expect(AddressDetail.reminderText(events: events, settings: morning, today: DayDate("2026-11-10")!, now: at("2026-11-10", 20)) == "Onsdag kl. 06:00, samma dag som tömningen.")
    // Dagens tid har passerat, så nästa tömning gäller.
    let later = AddressDetail.reminderText(events: events, settings: morning, today: wednesday, now: at("2026-11-11", 7))
    #expect(later == "Onsdag kl. 06:00, samma dag som tömningen.")
    #expect(AddressDetail.reminderText(events: [], settings: morning, today: wednesday, now: at("2026-11-11", 7)) == "Samma morgon som varje tömning kl. 06:00.")
    // Kvällen är oförändrad.
    #expect(AddressDetail.reminderText(events: events, settings: ReminderSettings(), today: DayDate("2026-11-10")!, now: at("2026-11-10", 12)) == "Tisdag kl. 18:00 inför onsdagens tömning.")
}

@Test func passeradMorgon() {
    let events = [event(wednesday)]
    #expect(AddressDetail.missedReminder(events: events, settings: morning, now: at("2026-11-11", 7)) == "Tömning i dag. Påminnelsen för i morse har redan passerat.")
    #expect(AddressDetail.missedReminder(events: events, settings: morning, now: at("2026-11-11", 5)) == nil)
    // Morgonvalet säger inget om morgondagen kvällen före.
    #expect(AddressDetail.missedReminder(events: events, settings: morning, now: at("2026-11-10", 20)) == nil)
}

@Test func reservenPåMorgonen() {
    #expect(AddressDetail.reserveText(StockholmClock.date(on: wednesday, minutes: 6 * 60 + 45)) == "Onsdag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns.")
    #expect(AddressDetail.reserveText(StockholmClock.date(on: DayDate("2026-11-10")!, minutes: 18 * 60 + 45)) == "Tisdag kl. 18:45 inför onsdagens tömning, om aktiviteten inte syns.")
}

@Test func liveActivityPåMorgonen() {
    #expect(AddressDetail.liveActivityText(settings: morning) == "Visas på låsskärmen från kl. 06:00 samma morgon.")
}

@Test func huvudkortetPåMorgonen() throws {
    let on = HomeContent.make(addresses: [saved(notifications: true)], schedules: [key: schedule([event(wednesday)])], settings: morning, now: at("2026-11-10", 20))
    #expect(try #require(on.primary?.reminder).detail == "Onsdag kl. 06:00")
    let off = HomeContent.make(addresses: [saved(notifications: false)], schedules: [key: schedule([event(wednesday)])], settings: morning, now: at("2026-11-10", 20))
    #expect(try #require(off.primary?.reminder) == HomeContent.PrimaryReminder(isOn: false, isDenied: false, title: "Påminn mig samma morgon", detail: nil))
}

@Test func reservtextenFöljerNotisensDagEfterByte() {
    // Morgonens notis står kvar som reserv efter bytet tillbaka till kvällen. Den gäller ändå onsdagens tömning.
    #expect(AddressDetail.reserveText(StockholmClock.date(on: wednesday, minutes: 6 * 60)) == "Onsdag kl. 06:00, samma dag som tömningen, om aktiviteten inte syns.")
    #expect(AddressDetail.reserveText(StockholmClock.date(on: DayDate("2026-11-10")!, minutes: 18 * 60 + 45)) == "Tisdag kl. 18:45 inför onsdagens tömning, om aktiviteten inte syns.")
}
