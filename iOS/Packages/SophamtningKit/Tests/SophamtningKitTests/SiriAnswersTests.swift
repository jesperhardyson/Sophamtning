import Testing
import Foundation
import SophamtningKit

/// Fredag 6 november 2026 klockan 12:00 svensk tid.
private let now = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

private let info: [String: FractionInfo] = [
    "rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#474C48", icon: "trash-2"),
    "mat": FractionInfo(name: "Matavfall", short: "Mat", color: "#7A4A1E", icon: "apple"),
    "papper": FractionInfo(name: "Pappersförpackningar", short: "Papper", color: "#2E5E86", icon: "package"),
]

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false) -> PickupEvent {
    PickupEvent(date: DayDate(iso)!, fractions: fractions, estimated: estimated, deviation: nil, warning: nil, labels: [:])
}

private func schedule(_ events: [PickupEvent], lastError: APIError? = nil, withResponse: Bool = true) -> CachedSchedule {
    let response = AddressResponse(
        today: DayDate("2026-11-06")!,
        address: Address(id: "a", street: "Storgatan 12 B", locality: "Krylbo", kommun: "Avesta", source: "x", detail: nil, selection: "address", notice: nil),
        next: [], summary: "", events: events, bins: [], fractions: info,
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: DayDate("2026-11-06")!
    )
    return CachedSchedule(response: withResponse ? response : nil, fetchedAt: now, lastAttemptAt: now, lastError: lastError)
}

private func address(_ id: String, name: String, primary: Bool) -> SavedAddress {
    var value = SavedAddress.fixture(key: AddressKey(source: "x", id: id), isPrimary: primary)
    value.displayName = name
    return value
}

private let home = address("home", name: "Hemma", primary: true)
private let cabin = address("cabin|område 8", name: "Stugan", primary: false)
private let hemma = SiriAddress.address(home)

private func answer(_ schedule: CachedSchedule?, placedOut: Set<PlacedOut> = [], at time: Date = now) -> String {
    SiriAnswers.nextPickup(hemma, schedule: schedule, placedOut: placedOut, now: time).text
}

@Test func valAvAdress() {
    #expect(SiriAnswers.select(id: nil, in: [cabin, home]) == .address(home))
    #expect(SiriAnswers.select(id: nil, in: [cabin]) == .address(cabin))
    #expect(SiriAnswers.select(id: nil, in: []) == SiriAddress.none)
    // Id:t är adressens filnamn och jämförs bara, så tecken som | och mellanslag i adressens id spelar ingen roll.
    #expect(SiriAnswers.select(id: SiriAnswers.id(for: cabin), in: [cabin, home]) == .address(cabin))
    #expect(SiriAnswers.select(id: "finns-inte", in: [cabin, home]) == .removed)
}

@Test func nästaTömning() {
    let s = schedule([event("2026-11-19", ["mat", "papper"]), event("2026-11-26", ["rest"])])
    let result = SiriAnswers.nextPickup(hemma, schedule: s, placedOut: [], now: now)
    #expect(result.text == "Hemma: Matavfall och Pappersförpackningar töms torsdag 19 november, om 13 dagar.")
    #expect(result.card == SiriCard(date: DayDate("2026-11-19")!, title: "Om 13 dagar", fractions: ["mat", "papper"], info: info))
}

@Test func beräknatDatum() {
    #expect(answer(schedule([event("2026-11-19", ["mat"], estimated: true)])) == "Hemma: Matavfall töms ca torsdag 19 november, om ca 13 dagar.")
}

@Test func iDagOchIMorgon() {
    #expect(answer(schedule([event("2026-11-07", ["rest"])])) == "Hemma: Restavfall töms i morgon, lördag 7 november.")
    #expect(answer(schedule([event("2026-11-06", ["rest"])])) == "Hemma: Restavfall töms i dag, fredag 6 november.")
    #expect(answer(schedule([event("2026-11-07", ["rest"], estimated: true)])) == "Hemma: Restavfall töms ca i morgon, lördag 7 november.")
}

@Test func utställtNämns() {
    let mark = PlacedOut(key: home.key, date: DayDate("2026-11-07")!)
    #expect(answer(schedule([event("2026-11-07", ["rest"])]), placedOut: [mark]) == "Hemma: Restavfall töms i morgon, lördag 7 november. Kärlen är utställda.")
    // En bock för en annan adress gäller inte.
    let other = PlacedOut(key: cabin.key, date: DayDate("2026-11-07")!)
    #expect(answer(schedule([event("2026-11-07", ["rest"])]), placedOut: [other]) == "Hemma: Restavfall töms i morgon, lördag 7 november.")
}

@Test func lägenUtanTömning() {
    #expect(answer(schedule([])) == "Det finns inga kommande hämtningar för Hemma.")
    #expect(answer(nil) == "Schemat för Hemma har inte hämtats än. Öppna Sophämtning så hämtas det.")
    #expect(answer(schedule([], lastError: .network, withResponse: false)) == "Schemat för Hemma har inte hämtats än. Öppna Sophämtning så hämtas det.")
    #expect(answer(schedule([], lastError: .notFound, withResponse: false)) == "Källan hittar inte Hemma längre. Öppna Sophämtning och sök adressen igen.")
    #expect(SiriAnswers.nextPickup(.none, schedule: nil, placedOut: [], now: now).text == "Du har inte sparat någon adress i Sophämtning än.")
    #expect(SiriAnswers.nextPickup(.removed, schedule: nil, placedOut: [], now: now).text == "Den adressen är inte sparad i Sophämtning längre.")
    #expect(SiriAnswers.nextPickup(.none, schedule: nil, placedOut: [], now: now).card == nil)
    #expect(SiriAnswers.unreadable == "Sophämtning kan inte läsa schemat just nu. Lås upp telefonen och försök igen.")
}

@Test func ställUtKärlen() {
    let tomorrow = schedule([event("2026-11-07", ["rest"])])
    #expect(SiriAnswers.placeOut(hemma, schedule: tomorrow, placedOut: [], now: now) == .placeOut(PlacedOut(key: home.key, date: DayDate("2026-11-07")!), name: "Hemma"))
    #expect(SiriAnswers.placeOut(hemma, schedule: schedule([event("2026-11-06", ["rest"])]), placedOut: [], now: now) == .placeOut(PlacedOut(key: home.key, date: DayDate("2026-11-06")!), name: "Hemma"))
    let mark = PlacedOut(key: home.key, date: DayDate("2026-11-07")!)
    #expect(SiriAnswers.placeOut(hemma, schedule: tomorrow, placedOut: [mark], now: now) == .answer("Kärlen för Hemma är redan utställda."))
    #expect(SiriAnswers.placeOut(hemma, schedule: schedule([event("2026-11-19", ["rest"])]), placedOut: [], now: now) == .answer("Nästa tömning för Hemma är torsdag 19 november. Kärlen kan markeras som utställda dagen före och samma dag."))
    #expect(SiriAnswers.placeOut(hemma, schedule: schedule([event("2026-11-19", ["rest"], estimated: true)]), placedOut: [], now: now) == .answer("Nästa tömning för Hemma är ca torsdag 19 november. Kärlen kan markeras som utställda dagen före och samma dag."))
    #expect(SiriAnswers.placeOut(hemma, schedule: schedule([]), placedOut: [], now: now) == .answer("Det finns inga kommande hämtningar för Hemma."))
    #expect(SiriAnswers.placeOut(.none, schedule: nil, placedOut: [], now: now) == .answer("Du har inte sparat någon adress i Sophämtning än."))
    #expect(SiriAnswers.placedOutDone(name: "Hemma") == "Klart. Kärlen för Hemma är utställda.")
    #expect(SiriAnswers.saveFailed == "Det gick inte att spara att kärlen är utställda. Försök igen i appen.")
}
