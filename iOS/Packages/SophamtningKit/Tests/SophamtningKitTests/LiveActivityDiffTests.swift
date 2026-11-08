import Testing
import Foundation
import SophamtningKit

private let home = AddressKey(source: "kallor", id: "hem")
private let other = AddressKey(source: "kallor", id: "annan")
private let today = DayDate("2026-11-08")!
private let monday = DayDate("2026-11-09")!
private let thursday = DayDate("2026-11-12")!
private let start = StockholmClock.date(on: today, minutes: 1080)

private func content(_ name: String = "Hemma", date: String = "Måndag 9 november", estimated: Bool = false, warning: String? = nil) -> PickupActivityContent {
    PickupActivityContent(addressName: name, dateText: date, shortDateText: "Mån 9 nov", fractions: [
        ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash"),
    ], estimated: estimated, warning: warning)
}

private let plan = PlannedLiveActivity(key: home, pickupDate: monday, start: start, startsImmediately: false, content: content())

private func existing(_ id: String, key: AddressKey = home, date: DayDate = monday, content c: PickupActivityContent = content(), pending: Bool = true, start s: Date = start) -> ExistingActivity {
    ExistingActivity(id: id, key: key, pickupDate: date, content: c, isPending: pending, start: s)
}

private func actions(_ desired: PlannedLiveActivity?, _ list: [ExistingActivity], enabled: Bool = true, primary: AddressKey? = nil, canStart: Bool = true, now: Date = start.addingTimeInterval(-3600), todayContent: PickupActivityContent? = nil) -> [LiveActivityAction] {
    LiveActivityDiff.actions(desired: desired, existing: list, today: today, enabled: enabled, primary: primary, canStart: canStart, now: now, todayContent: todayContent)
}

@Test func ingenOnskadTarBortAlla() {
    let a = existing("a"), b = existing("b", date: thursday)
    #expect(actions(nil, [a, b]) == [.remove(id: "a"), .remove(id: "b")])
}

@Test func samma() {
    #expect(actions(plan, [existing("a")]) == [])
    #expect(actions(plan, [existing("a", pending: false)]) == [])
}

@Test func nyStartar() {
    #expect(actions(plan, []) == [.start(plan)])
}

@Test func nyttDatumErsatter() {
    let oldDate = existing("a", date: thursday)
    #expect(actions(plan, [oldDate]) == [.remove(id: "a"), .start(plan)])
}

@Test func nyttInnehallPaStartadUppdaterar() {
    let running = existing("a", content: content(warning: "Helgdag"), pending: false)
    #expect(actions(plan, [running]) == [.update(id: "a", plan.content)])
}

@Test func nyttInnehallPaVantandeErsatter() {
    let pending = existing("a", content: content("Stugan"))
    #expect(actions(plan, [pending]) == [.remove(id: "a"), .start(plan)])
}

@Test func nyTidPaVantandeErsatter() {
    // Användaren ändrar påminnelsetiden. Utan det här startar aktiviteten på den gamla tiden.
    let pending = existing("a", start: start.addingTimeInterval(3600))
    #expect(actions(plan, [pending]) == [.remove(id: "a"), .start(plan)])
}

@Test func nyTidPaStartadRorInget() {
    let running = existing("a", pending: false, start: start.addingTimeInterval(-3600))
    #expect(actions(plan, [running]) == [])
}

@Test func dubblettStadas() {
    #expect(actions(plan, [existing("a"), existing("b")]) == [.remove(id: "b")])
}

@Test func dubblettBeharDenStartade() {
    let pending = existing("a"), running = existing("b", pending: false)
    #expect(actions(plan, [pending, running]) == [.remove(id: "a")])
}

@Test func dubblettMedNyttInnehallUppdaterarDenStartade() {
    let pending = existing("a", content: content("Stugan")), running = existing("b", content: content("Stugan"), pending: false)
    #expect(actions(plan, [pending, running]) == [.remove(id: "a"), .update(id: "b", plan.content)])
}

@Test func pagaendeForIDagLeverKvar() {
    let running = existing("a", date: today, pending: false)
    #expect(actions(plan, [running]) == [.start(plan)])
}

@Test func pagaendeForIDagLeverKvarUtanNastaTomning() {
    let running = existing("a", date: today, pending: false)
    #expect(actions(nil, [running], primary: home) == [])
}

@Test func vantandeForIDagTasBort() {
    // Den har inte startat och hinner inte starta i tid.
    let pending = existing("a", date: today, pending: true)
    #expect(actions(plan, [pending]) == [.remove(id: "a"), .start(plan)])
}

@Test func gardagensTasBort() {
    let old = existing("a", date: today.adding(days: -1), pending: false)
    #expect(actions(plan, [old]) == [.remove(id: "a"), .start(plan)])
}

@Test func avstangtValTarBortAvenPagaende() {
    let running = existing("a", date: today, pending: false)
    #expect(actions(plan, [running, existing("b")], enabled: false) == [.remove(id: "a"), .remove(id: "b")])
    #expect(actions(nil, [running], enabled: false, primary: home) == [.remove(id: "a")])
}

@Test func bytHuvudadressTarBortPagaendeForIDag() {
    let running = existing("a", key: other, date: today, pending: false)
    #expect(actions(plan, [running]) == [.remove(id: "a"), .start(plan)])
    #expect(actions(nil, [running], primary: home) == [.remove(id: "a")])
}

@Test func ingenHuvudadressTarBortPagaendeForIDag() {
    let running = existing("a", date: today, pending: false)
    #expect(actions(nil, [running], primary: nil) == [.remove(id: "a")])
}

// MARK: Utan start, i bakgrunden

@Test func utanStartStartasIngen() {
    #expect(actions(plan, [], canStart: false) == [])
    #expect(actions(plan, [existing("a", date: thursday)], canStart: false) == [.remove(id: "a")])
}

@Test func utanStartBehallsVantandeMedSammaDatum() {
    // Bakgrunden kan inte lägga in en ny, så den gamla är bättre än ingen alls.
    #expect(actions(plan, [existing("a", content: content(warning: "Helgdag"))], canStart: false) == [])
    #expect(actions(plan, [existing("a", start: start.addingTimeInterval(3600))], canStart: false) == [])
}

@Test func utanStartUppdaterasStartad() {
    let running = existing("a", content: content(warning: "Helgdag"), pending: false)
    #expect(actions(plan, [running], canStart: false) == [.update(id: "a", plan.content)])
}

// MARK: Väntande vars start har passerat

@Test func passeradVantandeErsattsOmDetGar() {
    let late = start.addingTimeInterval(LiveActivityDiff.overdueMargin + 1)
    #expect(actions(plan, [existing("a")], now: late) == [.remove(id: "a"), .start(plan)])
    #expect(actions(plan, [existing("a")], canStart: false, now: late) == [])
}

@Test func vantandeInomMarginalenRorsInte() {
    let within = start.addingTimeInterval(LiveActivityDiff.overdueMargin)
    #expect(actions(plan, [existing("a")], now: within) == [])
    #expect(!LiveActivityDiff.isOverdue(existing("a"), now: within))
    #expect(LiveActivityDiff.isOverdue(existing("a"), now: within.addingTimeInterval(1)))
    #expect(!LiveActivityDiff.isOverdue(existing("a", pending: false), now: within.addingTimeInterval(1)))
}

// MARK: Dagens pågående

@Test func tvaPagaendeForIDagStadas() {
    let first = existing("a", date: today, pending: false), second = existing("b", date: today, pending: false)
    #expect(actions(plan, [first, second]) == [.remove(id: "b"), .start(plan)])
}

@Test func dagensPagaendeUppdaterasMedNyttInnehall() {
    let running = existing("a", date: today, pending: false)
    let updated = content("Nytt namn", warning: "Helgdag")
    #expect(actions(nil, [running], primary: home, todayContent: updated) == [.update(id: "a", updated)])
    #expect(actions(nil, [running], primary: home, todayContent: content()) == [])
    #expect(actions(nil, [running], primary: home, canStart: false, todayContent: updated) == [.update(id: "a", updated)])
}

// MARK: Lägen

@Test func baraVantandeOchPagaendeRaknasSomBefintliga() {
    #expect(LiveActivityPhase.pending.countsAsExisting)
    #expect(LiveActivityPhase.active.countsAsExisting)
    #expect(!LiveActivityPhase.ended.countsAsExisting)
    #expect(!LiveActivityPhase.dismissed.countsAsExisting)
    #expect(!LiveActivityPhase.stale.countsAsExisting)
}

// MARK: Start

@Test func startlage() {
    let scheduled = PlannedLiveActivity(key: home, pickupDate: monday, start: start, startsImmediately: false, content: content())
    #expect(scheduled.startMode(now: start.addingTimeInterval(-60)) == .scheduled(start))
    // Tiden hann passera mellan planeringen och anropet: en start i det förflutna får aldrig skickas.
    #expect(scheduled.startMode(now: start) == .immediately)
    #expect(scheduled.startMode(now: start.addingTimeInterval(1)) == .immediately)
    let immediate = PlannedLiveActivity(key: home, pickupDate: monday, start: start, startsImmediately: true, content: content())
    #expect(immediate.startMode(now: start.addingTimeInterval(60)) == .immediately)
}

// MARK: Texter

@Test func aviseringensText() {
    #expect(PickupActivityContent.alertTitle == "Ställ ut kärlen")
    let two = PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [
        ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash"),
        ActivityFraction(id: "mat", name: "Matavfall", short: "Mat", color: "#222222", icon: "leaf"),
    ], estimated: false, warning: nil)
    #expect(two.alertBody == "Hemma: Restavfall och Matavfall töms måndag 9 november.")
    let estimated = PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: two.fractions, estimated: true, warning: "Hämtning på helgdag.")
    #expect(estimated.alertBody == "Hemma: Restavfall och Matavfall töms ca måndag 9 november. Hämtning på helgdag.")
}

@Test func vyernasTexter() {
    let plain = content()
    #expect(plain.subtitle == "Hemma · måndag 9 november")
    #expect(plain.shortDate == "Mån 9 nov")
    #expect(plain.compactDate == "Mån")
    #expect(plain.fractionsLine == "Hemma: Restavfall")
    let estimated = content(estimated: true)
    #expect(estimated.subtitle == "Hemma · ca måndag 9 november")
    #expect(estimated.shortDate == "ca mån 9 nov")
    #expect(estimated.compactDate == "ca mån")
}

@Test func aktivitetensTextSagerAldrigIMorgon() throws {
    // Söndag kväll, tömning måndag: alltså i morgon. Innehållet uppdateras inte under natten.
    let tomorrow = PickupEvent(date: DayDate("2026-11-09")!, fractions: ["rest"], estimated: true, deviation: nil, warning: nil, labels: [:])
    let address = SavedAddress(key: home, url: URL(string: "https://example.com/a")!, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", detail: nil, selection: "address", displayName: String(repeating: "x", count: 80), isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
    let response = AddressResponse(
        today: today,
        address: Address(id: home.id, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", source: home.source, detail: nil, selection: "address", notice: nil),
        next: [], summary: "", events: [tomorrow], bins: [],
        fractions: ["rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")],
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: today
    )
    let plan = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: address, schedule: CachedSchedule(response: response))],
        settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: start.addingTimeInterval(60), liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
    let content = try #require(plan.liveActivity).content
    #expect(content.addressName.count == 60)
    for text in [content.alertBody, content.subtitle, content.shortDate, content.compactDate, content.fractionsLine, content.dateText] {
        #expect(!text.lowercased().contains("i morgon"))
        #expect(!text.lowercased().contains("i dag"))
    }
}

@Test func varningenKortas() {
    let long = PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [], estimated: false, warning: String(repeating: "x", count: 500))
    #expect(long.warning?.count == 200)
    #expect(long.warning?.hasSuffix("…") == true)
    #expect(content(warning: String(repeating: "x", count: 200)).warning == String(repeating: "x", count: 200))
}

@Test func innehalletHallerSigUnderSystemetsGrans() throws {
    // ActivityKit vägrar innehåll över 4 KB. Tolv fraktioner är fler än någon källa har i dag.
    let fractions = (0..<12).map { ActivityFraction(id: "fraktion-\($0)", name: "Pappersförpackningar och kartong \($0)", short: "Papper", color: "#2E5E86", icon: "package") }
    let largest = PickupActivityContent(addressName: String(repeating: "å", count: 60), dateText: "Onsdag 30 september", shortDateText: "Ons 30 sep", fractions: fractions, estimated: true, warning: String(repeating: "å", count: 500))
    #expect(try JSONEncoder().encode(largest).count < 4096)
}

// MARK: Fraktionernas rader

private func fractions(_ count: Int) -> [ActivityFraction] {
    (0..<count).map { ActivityFraction(id: "f\($0)", name: "Namn \($0)", short: "K\($0)", color: "#111111", icon: "trash") }
}

private func withFractions(_ count: Int, warning: String? = nil) -> PickupActivityContent {
    PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: fractions(count), estimated: false, warning: warning)
}

@Test func allaFraktionerRymsPaHogstTvaRader() {
    for count in 1...8 {
        let rows = withFractions(count).fractionRows
        #expect(rows.count <= 2, "\(count)")
        // Ingen fraktion försvinner, och ordningen är kvar.
        #expect(rows.flatMap { $0 }.map(\.id) == fractions(count).map(\.id), "\(count)")
    }
    #expect(withFractions(3).fractionRows.map(\.count) == [3])
    #expect(withFractions(4).fractionRows.map(\.count) == [2, 2])
    #expect(withFractions(5).fractionRows.map(\.count) == [3, 2])
    #expect(withFractions(6).fractionRows.map(\.count) == [3, 3])
}

@Test func varningenFarEnRadNarFraktionernaTarTvaRader() {
    #expect(withFractions(3).warningLineLimit == 2)
    #expect(withFractions(4).warningLineLimit == 1)
    #expect(withFractions(6).warningLineLimit == 1)
}
