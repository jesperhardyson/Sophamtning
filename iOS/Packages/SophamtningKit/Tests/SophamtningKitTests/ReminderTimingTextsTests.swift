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
    #expect(HomeContent.reminderTitle() == "Påminn mig")
    #expect(HomeContent.reminderActionTitle(isOn: true) == "Stäng av påminnelse")
    #expect(HomeContent.reminderActionTitle(isOn: false) == "Slå på påminnelse")
}

@Test func delarnasTexter() {
    #expect(ReminderTiming.eveningBefore.sectionFooter(minutes: 900) == "Dagen före tömningen kl. 15:00.")
    #expect(ReminderTiming.sameMorning.sectionFooter(minutes: 360) == "Samma dag som tömningen kl. 06:00. Minst en påminnelse är på. Notiser slår du på och av per adress.")
}

@Test func tidslistansText() {
    #expect(ReminderTiming.eveningBefore.timesFooter == "Välj en tid mellan 15:00 och 23:00.")
    #expect(ReminderTiming.sameMorning.timesFooter == "Välj en tid mellan 05:00 och 09:00.")
}

private let both = ReminderSettings(eveningOn: true, morningOn: true, reminderMinutes: 1080, morningMinutes: 360)

@Test func radenVisarNästa() {
    let events = [event(wednesday)]
    #expect(AddressDetail.reminderText(events: events, settings: both, now: at("2026-11-10", 12)) == "Tisdag kl. 18:00 inför onsdagens tömning.")
    #expect(AddressDetail.reminderText(events: events, settings: both, now: at("2026-11-10", 19)) == "Onsdag kl. 06:00, samma dag som tömningen.")
}

@Test func radenUtanKommandeTömningNämnerVarjeVal() {
    #expect(AddressDetail.reminderText(events: [], settings: both, now: at("2026-11-10", 12)) == "Kvällen före varje tömning kl. 18:00. Samma morgon som varje tömning kl. 06:00.")
}

@Test func passeradMedBåda() {
    let events = [event(wednesday)]
    #expect(AddressDetail.missedReminder(events: events, settings: both, now: at("2026-11-11", 7)) == "Tömning i dag. Påminnelsen för i morse har redan passerat.")
    #expect(AddressDetail.missedReminder(events: events, settings: both, now: at("2026-11-10", 19)) == nil)
}

@Test func passeradBaraKväll() {
    let events = [event(wednesday)]
    #expect(AddressDetail.missedReminder(events: events, settings: ReminderSettings(), now: at("2026-11-10", 19)) == "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
}

private func pending(start: Date) -> ExistingActivity {
    ExistingActivity(id: "a", key: key, pickupDate: wednesday, content: PickupActivityContent(addressName: "Hemma", dateText: "Onsdag 11 november", shortDateText: "Ons 11 nov", fractions: [], estimated: false, warning: nil), isPending: true, start: start)
}

@Test func fotenNotisFöreAktivitet() throws {
    let start = at("2026-11-11", 6)
    let bothOn = ReminderSettings(eveningOn: true, morningOn: true, liveActivityTiming: .sameMorning, liveActivityOn: true)
    let content = HomeContent.make(addresses: [saved(notifications: true)], schedules: [key: schedule([event(wednesday)])], settings: bothOn, now: at("2026-11-10", 12), liveActivity: pending(start: start))
    #expect(try #require(content.primary?.reminder).detail == "Notis tisdag kl. 18:00, notis och Live Activity onsdag kl. 06:00")
    let morningOnly = ReminderSettings(eveningOn: false, morningOn: true, liveActivityTiming: .sameMorning, liveActivityOn: true)
    let same = HomeContent.make(addresses: [saved(notifications: true)], schedules: [key: schedule([event(wednesday)])], settings: morningOnly, now: at("2026-11-10", 12), liveActivity: pending(start: start))
    #expect(try #require(same.primary?.reminder).detail == "Notis och Live Activity onsdag kl. 06:00")
}

@Test func liveActivityTextFöljerSittVal() {
    let settings = ReminderSettings(eveningOn: true, morningOn: false, liveActivityTiming: .sameMorning)
    #expect(AddressDetail.liveActivityText(settings: settings) == "Visas på låsskärmen kl. 06:00–18:00 samma dag.")
}

@Test func inställningensTexter() {
    #expect(ReminderTiming.eveningBefore.title == "Kvällen före")
    #expect(ReminderTiming.sameMorning.title == "Samma morgon")
}

@Test func radenUnderReglagetPåMorgonen() {
    let events = [event(wednesday), event(nextWednesday)]
    #expect(AddressDetail.reminderText(events: events, settings: morning, now: at("2026-11-10", 20)) == "Onsdag kl. 06:00, samma dag som tömningen.")
    // Dagens tid har passerat, så nästa tömning gäller.
    let later = AddressDetail.reminderText(events: events, settings: morning, now: at("2026-11-11", 7))
    #expect(later == "Onsdag kl. 06:00, samma dag som tömningen.")
    #expect(AddressDetail.reminderText(events: [], settings: morning, now: at("2026-11-11", 7)) == "Samma morgon som varje tömning kl. 06:00.")
    // Kvällen är oförändrad.
    #expect(AddressDetail.reminderText(events: events, settings: ReminderSettings(), now: at("2026-11-10", 12)) == "Tisdag kl. 18:00 inför onsdagens tömning.")
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
    #expect(AddressDetail.liveActivityText(settings: morning) == "Visas på låsskärmen kl. 06:00–18:00 samma dag.")
}

@Test func huvudkortetPåMorgonen() throws {
    let on = HomeContent.make(addresses: [saved(notifications: true)], schedules: [key: schedule([event(wednesday)])], settings: morning, now: at("2026-11-10", 20))
    #expect(try #require(on.primary?.reminder).detail == "Onsdag kl. 06:00")
    let off = HomeContent.make(addresses: [saved(notifications: false)], schedules: [key: schedule([event(wednesday)])], settings: morning, now: at("2026-11-10", 20))
    #expect(try #require(off.primary?.reminder) == HomeContent.PrimaryReminder(isOn: false, isDenied: false, title: "Påminn mig", detail: nil))
}

@Test func reservtextenFöljerNotisensDagEfterByte() {
    // Morgonens notis står kvar som reserv efter bytet tillbaka till kvällen. Den gäller ändå onsdagens tömning.
    #expect(AddressDetail.reserveText(StockholmClock.date(on: wednesday, minutes: 6 * 60)) == "Onsdag kl. 06:00, samma dag som tömningen, om aktiviteten inte syns.")
    #expect(AddressDetail.reserveText(StockholmClock.date(on: DayDate("2026-11-10")!, minutes: 18 * 60 + 45)) == "Tisdag kl. 18:45 inför onsdagens tömning, om aktiviteten inte syns.")
}
