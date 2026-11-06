import Testing
import Foundation
@testable import SophamtningKit

private func day(_ iso: String) -> DayDate { DayDate(iso)! }

private func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// "2026-11-08T20:00" som väggklocka i Europe/Stockholm.
private func stockholm(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.date(from: text)!
}

private let homeKey = AddressKey(source: "kallor", id: "hem/1")
private let otherKey = AddressKey(source: "kallor", id: "annan 2")

private let fractionInfo: [String: FractionInfo] = [
    "rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash"),
    "mat": FractionInfo(name: "Matavfall", short: "Mat", color: "#222222", icon: "leaf"),
    "papper": FractionInfo(name: "Pappersförpackningar", short: "Papper", color: "#333333", icon: "doc"),
    "glas": FractionInfo(name: "Glasförpackningar", short: "Glas", color: "#444444", icon: "wineglass"),
]

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false, warning: String? = nil) -> PickupEvent {
    PickupEvent(date: day(iso), fractions: fractions, estimated: estimated, deviation: nil, warning: warning, labels: [:])
}

private func schedule(_ key: AddressKey, events: [PickupEvent]) -> CachedSchedule {
    let response = AddressResponse(
        today: day("2026-11-06"),
        address: Address(id: key.id, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", source: key.source, detail: nil, selection: "address", notice: nil),
        next: [],
        summary: "",
        events: events,
        bins: [],
        fractions: fractionInfo,
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: day("2026-11-06")
    )
    return CachedSchedule(response: response, fetchedAt: utc("2026-11-06T10:00:00Z"))
}

private func address(_ key: AddressKey, name: String, primary: Bool, notifications: Bool) -> SavedAddress {
    SavedAddress(
        key: key, url: URL(string: "https://example.com/\(key.fileName)")!, street: "Gatan 1", locality: "Orten", kommun: "Kommunen",
        detail: nil, selection: "address", displayName: name, isPrimary: primary, notificationsOn: notifications,
        addedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private let standardEvents = [
    event("2026-11-09", ["rest", "mat"]),
    event("2026-11-12", ["papper"]),
]

/// Fredag 2026-11-06 kl. 12:00 svensk tid.
private let friday = stockholm("2026-11-06T12:00")

private func plan(
    notifications: Bool = false,
    live: Bool = false,
    allowed: Bool = true,
    primaryIsOther: Bool = false,
    now: Date = friday,
    events: [PickupEvent] = standardEvents,
    otherEvents: [PickupEvent] = [event("2026-11-10", ["glas"])],
    placedOut: Set<PlacedOut> = [],
    existing: Set<PlacedOut> = [],
    shown: Set<PlacedOut> = [],
    withPrimary: Bool = true,
    reminderMinutes: Int = 1080,
    starts: [PlacedOut: Date] = [:]
) -> ReminderPlan {
    let home = address(homeKey, name: "Hemma", primary: withPrimary && !primaryIsOther, notifications: notifications)
    let other = address(otherKey, name: "Stugan", primary: withPrimary && primaryIsOther, notifications: notifications)
    return ReminderPlanner.plan(PlannerInput(
        addresses: [
            PlannerAddress(address: home, schedule: schedule(homeKey, events: events)),
            PlannerAddress(address: other, schedule: schedule(otherKey, events: otherEvents)),
        ],
        settings: ReminderSettings(reminderMinutes: reminderMinutes, liveActivityOn: live),
        placedOut: placedOut,
        now: now,
        liveActivitiesAllowed: allowed,
        existingActivities: existing,
        shownActivities: shown,
        activityStarts: starts
    ))
}

private func plannerInput(notifications: Bool, now: Date, placedOut: Set<PlacedOut> = [], shown: Set<PlacedOut> = []) -> PlannerInput {
    PlannerInput(
        addresses: [PlannerAddress(address: address(homeKey, name: "Hemma", primary: true, notifications: notifications), schedule: schedule(homeKey, events: standardEvents))],
        settings: ReminderSettings(liveActivityOn: true), placedOut: placedOut, now: now, liveActivitiesAllowed: true, existingActivities: [], shownActivities: shown
    )
}

/// En enda adress, för tester av innehållet.
private func single(_ events: [PickupEvent], notifications: Bool = true, now: Date = friday, fractions: [String: FractionInfo] = fractionInfo) -> ReminderPlan {
    var cached = schedule(homeKey, events: events)
    if let response = cached.response {
        cached.response = AddressResponse(today: response.today, address: response.address, next: [], summary: "", events: events, bins: [], fractions: fractions, links: response.links, updatedAt: response.updatedAt)
    }
    return ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: address(homeKey, name: "Hemma", primary: true, notifications: notifications), schedule: cached)],
        settings: ReminderSettings(), placedOut: [], now: now, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
}

private func body(estimated: Bool = false, warning: String? = nil) -> String {
    single([event("2026-11-09", ["rest", "mat"], estimated: estimated, warning: warning)]).notifications[0].body
}

@Test func alltAvGerTomPlan() {
    #expect(plan(notifications: false, live: false) == .empty)
}

@Test func notisKvallenFore() {
    let n = plan(notifications: true).notifications[0]
    #expect(n.fireDate == utc("2026-11-08T17:00:00Z"))
    #expect(n.title == "Ställ ut kärlen")
    #expect(n.body == "Hemma: Restavfall och Matavfall töms måndag 9 november.")
    #expect(n.key == homeKey)
    #expect(n.pickupDate == day("2026-11-09"))
}

@Test func beraknatDatumOchVarningINotis() {
    #expect(body(estimated: true).contains("töms ca måndag 9 november"))
    #expect(body(warning: "Hämtning på helgdag.").hasSuffix("november. Hämtning på helgdag."))
}

@Test func tomVarningLaggsInteTill() {
    #expect(body(warning: "  ") == "Hemma: Restavfall och Matavfall töms måndag 9 november.")
}

@Test func fraktionsnamnBindsMedKommaOchOch() {
    let one = single([event("2026-11-09", ["rest"])]).notifications[0].body
    #expect(one == "Hemma: Restavfall töms måndag 9 november.")
    let three = single([event("2026-11-09", ["rest", "mat", "papper"])]).notifications[0].body
    #expect(three == "Hemma: Restavfall, Matavfall och Pappersförpackningar töms måndag 9 november.")
}

@Test func okandFraktionFaarIdSomNamn() {
    let n = single([event("2026-11-09", ["nytt"])]).notifications[0]
    #expect(n.body == "Hemma: nytt töms måndag 9 november.")
}

@Test func passeradFireDateHoppasOver() {
    let p = plan(notifications: true, now: stockholm("2026-11-08T18:01"))
    #expect(!p.notifications.contains { $0.pickupDate == day("2026-11-09") })
    #expect(p.notifications.contains { $0.pickupDate == day("2026-11-12") })
}

@Test func fireDateExaktNuHoppasOver() {
    let p = plan(notifications: true, now: stockholm("2026-11-08T18:00"))
    #expect(!p.notifications.contains { $0.pickupDate == day("2026-11-09") })
}

@Test func baraPasseratSchemaGerIngetAlls() {
    #expect(plan(notifications: true, live: true, now: stockholm("2027-02-01T12:00")) == .empty)
}

@Test func tomtSchemaGerIngetAlls() {
    #expect(plan(notifications: true, live: true, events: [], otherEvents: []) == .empty)
    let noResponse = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: address(homeKey, name: "Hemma", primary: true, notifications: true), schedule: nil),
                    PlannerAddress(address: address(otherKey, name: "Stugan", primary: false, notifications: true), schedule: CachedSchedule())],
        settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: friday, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
    #expect(noResponse == .empty)
}

@Test func handelseUtanFraktionerPlanerasInte() {
    let events = [event("2026-11-09", []), event("2026-11-12", ["papper"])]
    let p = single(events)
    #expect(p.notifications.map(\.pickupDate) == [day("2026-11-12")])
    let live = plan(live: true, events: events).liveActivity
    #expect(live?.pickupDate == day("2026-11-12"))
}

@Test func hogst60NarmastForst() {
    // 100 tömningar, varannan dag, i blandad ordning.
    let start = day("2026-11-10")
    let events = (0..<100).map { event(start.adding(days: $0 * 2).iso, ["rest"]) }.reversed()
    let p = single(Array(events))
    #expect(p.notifications.count == 60)
    #expect(p.notifications.map(\.fireDate) == p.notifications.map(\.fireDate).sorted())
    #expect(p.notifications.first?.pickupDate == day("2026-11-10"))
    #expect(p.notifications.last?.pickupDate == start.adding(days: 59 * 2))
}

@Test func stabilaIdentifierare() {
    let a = plan(notifications: true)
    let b = plan(notifications: true)
    #expect(a.notifications.map(\.identifier) == b.notifications.map(\.identifier))
    #expect(Set(a.notifications.map(\.identifier)).count == a.notifications.count)
    #expect(a.notifications[0].identifier == "\(homeKey.fileName)-2026-11-09")
}

@Test func tvaHandelserSammaDagSlasIhop() {
    let p = single([event("2026-11-09", ["rest"]), event("2026-11-09", ["mat"], warning: "Varning.")])
    #expect(p.notifications.count == 1)
    #expect(p.notifications[0].body == "Hemma: Restavfall och Matavfall töms måndag 9 november. Varning.")
}

@Test func notisBaraForAdressMedValPa() {
    let home = address(homeKey, name: "Hemma", primary: true, notifications: false)
    let other = address(otherKey, name: "Stugan", primary: false, notifications: true)
    let p = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: home, schedule: schedule(homeKey, events: standardEvents)),
                    PlannerAddress(address: other, schedule: schedule(otherKey, events: [event("2026-11-10", ["glas"])]))],
        settings: ReminderSettings(), placedOut: [], now: friday, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
    #expect(p.notifications.map(\.key) == [otherKey])
}

@Test func paverkarPaminnelsetiden() {
    let n = plan(notifications: true, reminderMinutes: 15 * 60 + 45).notifications[0]
    #expect(n.fireDate == utc("2026-11-08T14:45:00Z"))
}

@Test func sommartidGerRattUtcTid() {
    // Omställning till sommartid sker 2026-03-29: kvällen den 29:e är UTC+2 och kvällen den 28:e UTC+1.
    let p = single([event("2026-03-30", ["rest"])], now: stockholm("2026-03-01T12:00"))
    #expect(p.notifications[0].fireDate == utc("2026-03-29T16:00:00Z"))
    let q = single([event("2026-03-29", ["rest"])], now: stockholm("2026-03-01T12:00"))
    #expect(q.notifications[0].fireDate == utc("2026-03-28T17:00:00Z"))
}

@Test func liveActivityBaraForHuvudadressNastaTomning() {
    let la = plan(live: true).liveActivity
    #expect(la?.pickupDate == day("2026-11-09"))
    #expect(la?.start == utc("2026-11-08T17:00:00Z"))
    #expect(la?.startsImmediately == false)
    #expect(la?.key == homeKey)
    #expect(plan(live: true, primaryIsOther: true).liveActivity?.key == otherKey)
    #expect(plan(live: true, primaryIsOther: true).liveActivity?.pickupDate == day("2026-11-10"))
}

@Test func liveActivityBerorInteAvAdressensNotisval() {
    #expect(plan(notifications: false, live: true).liveActivity != nil)
}

@Test func liveActivityKraverBadaValen() {
    #expect(plan(live: false).liveActivity == nil)
    #expect(plan(live: true, allowed: false).liveActivity == nil)
}

@Test func passeradStarttidStartarDirektOmTomningArImorgon() {
    let la = plan(live: true, now: stockholm("2026-11-08T20:00")).liveActivity
    #expect(la?.pickupDate == day("2026-11-09"))
    #expect(la?.startsImmediately == true)
    #expect(la?.start == utc("2026-11-08T17:00:00Z"))
}

@Test func starttidenExaktNuStartarDirekt() {
    #expect(plan(live: true, now: stockholm("2026-11-08T18:00")).liveActivity?.startsImmediately == true)
    #expect(plan(live: true, now: stockholm("2026-11-08T17:59")).liveActivity?.startsImmediately == false)
}

@Test func paTomningsdagenPlanerasNastaTomning() {
    #expect(plan(live: true, now: stockholm("2026-11-09T07:00")).liveActivity?.pickupDate == day("2026-11-12"))
    #expect(plan(live: true, now: stockholm("2026-11-09T07:00"), events: [event("2026-11-09", ["rest"])]).liveActivity == nil)
}

@Test func innehallSagerInteImorgon() throws {
    let content = try #require(plan(live: true).liveActivity?.content)
    #expect(content.addressName == "Hemma")
    #expect(content.dateText == "Måndag 9 november")
    #expect(content.shortDateText == "Mån 9 nov")
    #expect(!content.dateText.lowercased().contains("morgon"))
    #expect(!content.shortDateText.lowercased().contains("morgon"))
    #expect(content.fractions == [
        ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash"),
        ActivityFraction(id: "mat", name: "Matavfall", short: "Mat", color: "#222222", icon: "leaf"),
    ])
    #expect(!content.estimated)
}

@Test func beraknatDatumBlirEgetFaltOchTextenArOforandrad() throws {
    let content = try #require(plan(live: true, events: [event("2026-11-09", ["rest"], estimated: true)]).liveActivity?.content)
    #expect(content.estimated)
    #expect(content.dateText == "Måndag 9 november")
    #expect(content.shortDateText == "Mån 9 nov")
}

@Test func okandFraktionIAktivitetenFaarNeutralVisning() throws {
    let content = try #require(plan(live: true, events: [event("2026-11-09", ["nytt"])]).liveActivity?.content)
    #expect(content.fractions.map(\.id) == ["nytt"])
    #expect(content.fractions[0].name == "nytt")
    #expect(!content.fractions[0].color.isEmpty && !content.fractions[0].icon.isEmpty)
}

@Test func utstalltStopparAktiviteten() {
    let placed: Set = [PlacedOut(key: homeKey, date: day("2026-11-09"))]
    let la = plan(live: true, placedOut: placed).liveActivity
    #expect(la?.pickupDate == day("2026-11-12"))
    #expect(la?.start == utc("2026-11-11T17:00:00Z"))
    // Utställt för en annan adress eller ett annat datum påverkar inte.
    #expect(plan(live: true, placedOut: [PlacedOut(key: otherKey, date: day("2026-11-09"))]).liveActivity?.pickupDate == day("2026-11-09"))
    #expect(plan(live: true, placedOut: [PlacedOut(key: homeKey, date: day("2026-11-12"))]).liveActivity?.pickupDate == day("2026-11-09"))
}

@Test func utstalldTomningIDagGerNastaTomning() {
    let placed: Set = [PlacedOut(key: homeKey, date: day("2026-11-09"))]
    let la = plan(live: true, now: stockholm("2026-11-09T07:00"), placedOut: placed).liveActivity
    #expect(la?.pickupDate == day("2026-11-12"))
}

private let homeMonday: Set<PlacedOut> = [PlacedOut(key: homeKey, date: day("2026-11-09"))]

@Test func badaPaBehallerNotisUtanSchemalagdAktivitet() {
    let p = plan(notifications: true, live: true, existing: [])
    #expect(p.liveActivity?.pickupDate == day("2026-11-09"))
    #expect(p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
}

private func mondayNotification(_ p: ReminderPlan) -> PlannedNotification? {
    p.notifications.first { $0.key == homeKey && $0.pickupDate == day("2026-11-09") }
}

@Test func badaPaGerReservnotisEfterStart() throws {
    let p = plan(notifications: true, live: true, existing: homeMonday)
    let fallback = try #require(mondayNotification(p))
    // Starten är 18:00, så reserven är 18:45 och inte 18:00.
    #expect(fallback.fireDate == stockholm("2026-11-08T18:45"))
    #expect(fallback.fireDate != p.liveActivity?.start)
    #expect(fallback.title == "Har du ställt ut kärlen?")
    // Samma innehåll som den vanliga notisen.
    let ordinary = try #require(mondayNotification(plan(notifications: true, live: false)))
    #expect(fallback.body == ordinary.body)
    #expect(fallback.title != ordinary.title)
    #expect(ordinary.title == "Ställ ut kärlen")
    #expect(p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-12") })
    // Aktivitetsplanen beror inte på vad som finns.
    #expect(p.liveActivity == plan(notifications: true, live: true, existing: []).liveActivity)
}

@Test func reservnotisenHarSammaIdentifierareSomVanligNotis() throws {
    let fallback = try #require(mondayNotification(plan(notifications: true, live: true, existing: homeMonday)))
    let ordinary = try #require(mondayNotification(plan(notifications: true, live: true, existing: [])))
    #expect(fallback.identifier == ordinary.identifier)
    #expect(NotificationDiff.isOwn(identifier: fallback.identifier))
    // En enda notis för tömningen, aldrig både ordinarie och reserv.
    let p = plan(notifications: true, live: true, existing: homeMonday)
    #expect(p.notifications.filter { $0.identifier == fallback.identifier }.count == 1)
    // Diffen ersätter den ordinarie notisen i stället för att lägga till en andra.
    let changes = NotificationDiff.diff(desired: [fallback], pendingIds: [ordinary.identifier], pendingFireDates: [ordinary.identifier: ordinary.fireDate])
    #expect(changes.add == [fallback])
    #expect(changes.removeIds == [fallback.identifier])
}

@Test func reservnotisensTidHarTak() {
    // Start 22:59 ger 23:44, 23:00 ger 23:45 och en senare start ger aldrig mer än 23:45.
    #expect(ReminderPlanner.fallbackDate(start: stockholm("2026-11-08T15:00")) == stockholm("2026-11-08T15:45"))
    #expect(ReminderPlanner.fallbackDate(start: stockholm("2026-11-08T22:59")) == stockholm("2026-11-08T23:44"))
    #expect(ReminderPlanner.fallbackDate(start: stockholm("2026-11-08T23:00")) == stockholm("2026-11-08T23:45"))
    #expect(ReminderPlanner.fallbackDate(start: stockholm("2026-11-08T23:30")) == stockholm("2026-11-08T23:45"))
}

@Test func reserventRaknasFranAktivitetensEgenStart() throws {
    // Aktiviteten väntar med start 17:00 (en äldre påminnelsetid), fast inställningen nu är 20:00.
    let id = PlacedOut(key: homeKey, date: day("2026-11-09"))
    let p = plan(notifications: true, live: true, existing: [id], reminderMinutes: 20 * 60, starts: [id: stockholm("2026-11-08T17:00")])
    #expect(try #require(mondayNotification(p)).fireDate == stockholm("2026-11-08T17:45"))
    // Utan känd start används påminnelsetiden.
    let q = plan(notifications: true, live: true, existing: [id], reminderMinutes: 20 * 60)
    #expect(try #require(mondayNotification(q)).fireDate == stockholm("2026-11-08T20:45"))
}

@Test func passeradOrdinarieTidUtanAktivitetGerIngenNotisMenGeRetainable() {
    let now = stockholm("2026-11-08T18:10")
    let p = plan(notifications: true, live: true, now: now, existing: [])
    #expect(mondayNotification(p) == nil)
    let input = plannerInput(notifications: true, now: now)
    let id = PlannedNotification.identifier(key: homeKey, date: day("2026-11-09"))
    #expect(ReminderPlanner.retainable(input)[id] == PlacedOut(key: homeKey, date: day("2026-11-09")))
}

@Test func retainableUtelamnarUtstalldVisadOchAvstangdaNotiser() {
    let now = stockholm("2026-11-08T18:10")
    let id = PlannedNotification.identifier(key: homeKey, date: day("2026-11-09"))
    #expect(ReminderPlanner.retainable(plannerInput(notifications: true, now: now, placedOut: homeMonday))[id] == nil)
    #expect(ReminderPlanner.retainable(plannerInput(notifications: true, now: now, shown: homeMonday))[id] == nil)
    // Användaren har stängt av notiserna: inget behålls.
    #expect(ReminderPlanner.retainable(plannerInput(notifications: false, now: now)).isEmpty)
    // Före ordinarie tid planeras den vanliga notisen, och inget behöver behållas.
    #expect(ReminderPlanner.retainable(plannerInput(notifications: true, now: stockholm("2026-11-08T17:00")))[id] == nil)
}

@Test func reservnotisenTakasKlockan2345() throws {
    // 23:00 är sista tillåtna påminnelsetid.
    let p = plan(notifications: true, live: true, existing: homeMonday, reminderMinutes: 23 * 60)
    #expect(try #require(mondayNotification(p)).fireDate == stockholm("2026-11-08T23:45"))
}

@Test func reservnotisenFolkerSvenskTidOavsettTelefonensZon() throws {
    // Sommartid och vintertid: väggklockan är densamma. Telefonens zon läses aldrig, vilket körningen med TZ=America/New_York prövar.
    let p = plan(notifications: true, live: true, existing: homeMonday)
    #expect(try #require(mondayNotification(p)).fireDate == utc("2026-11-08T17:45:00Z"))
    let spring = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: address(homeKey, name: "Hemma", primary: true, notifications: true), schedule: schedule(homeKey, events: [event("2026-03-30", ["rest"])]))],
        settings: ReminderSettings(reminderMinutes: 23 * 60, liveActivityOn: true), placedOut: [], now: stockholm("2026-03-01T12:00"),
        liveActivitiesAllowed: true, existingActivities: [PlacedOut(key: homeKey, date: day("2026-03-30"))], shownActivities: []
    ))
    #expect(spring.notifications.first?.fireDate == utc("2026-03-29T21:45:00Z"))
}

@Test func reservnotisenHoppasOverNarTidenPasserat() {
    // Söndag 18:50: reserven 18:45 har passerat.
    let p = plan(notifications: true, live: true, now: stockholm("2026-11-08T18:50"), existing: homeMonday)
    #expect(mondayNotification(p) == nil)
    // Strax före reserven finns den kvar.
    let before = plan(notifications: true, live: true, now: stockholm("2026-11-08T18:44"), existing: homeMonday)
    #expect(mondayNotification(before)?.fireDate == stockholm("2026-11-08T18:45"))
}

@Test func visadTomningGerIngenReservnotis() {
    let p = plan(notifications: true, live: true, existing: homeMonday, shown: homeMonday)
    #expect(mondayNotification(p) == nil)
    #expect(p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-12") })
}

@Test func utstalldTomningMedAktivitetGerIngenReservnotis() {
    let p = plan(notifications: true, live: true, placedOut: homeMonday, existing: homeMonday)
    #expect(mondayNotification(p) == nil)
}

@Test func visadUtanAktivitetGerOrdinarieNotis() throws {
    // Den bortsvepta aktiviteten finns inte kvar, och då är det den vanliga notisen som gäller.
    let p = plan(notifications: true, live: true, existing: [], shown: homeMonday)
    #expect(try #require(mondayNotification(p)).fireDate == stockholm("2026-11-08T18:00"))
}

@Test func bastaLiveActivityUtanNotiserGerIngenNotis() {
    let p = plan(notifications: false, live: true, existing: homeMonday)
    #expect(p.notifications.isEmpty)
    #expect(p.liveActivity != nil)
}

@Test func aktivitetForAnnatDatumHindrarInteNotis() {
    let otherDate: Set<PlacedOut> = [PlacedOut(key: homeKey, date: day("2026-11-12"))]
    #expect(plan(notifications: true, live: true, existing: otherDate).notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
    let otherAddress: Set<PlacedOut> = [PlacedOut(key: otherKey, date: day("2026-11-09"))]
    #expect(plan(notifications: true, live: true, existing: otherAddress).notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
}

@Test func existerandeAktivitetUtanValPaHindrarInteNotis() {
    #expect(plan(notifications: true, live: false, existing: homeMonday).notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
    #expect(plan(notifications: true, live: true, allowed: false, existing: homeMonday).notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
}

@Test func notisForAnnanAdressSammaDatumBehalls() throws {
    let p = plan(notifications: true, live: true, otherEvents: [event("2026-11-09", ["glas"])], existing: homeMonday)
    let other = try #require(p.notifications.first { $0.key == otherKey && $0.pickupDate == day("2026-11-09") })
    #expect(other.title == "Ställ ut kärlen")
    #expect(other.fireDate == stockholm("2026-11-08T18:00"))
    #expect(try #require(mondayNotification(p)).title == "Har du ställt ut kärlen?")
}

@Test func utstalldTomningGerIngenNotis() {
    let p = plan(notifications: true, live: true, placedOut: homeMonday)
    #expect(p.liveActivity?.pickupDate == day("2026-11-12"))
    #expect(!p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
    #expect(p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-12") })
    #expect(p.notifications.contains { $0.key == otherKey })
}

@Test(arguments: [0, -1, 2880, 899, 1381, 1000])
func ogiltigPaminnelsetidGerStandardtid(minutes: Int) {
    #expect(plan(notifications: true, reminderMinutes: minutes).notifications[0].fireDate == utc("2026-11-08T17:00:00Z"))
    #expect(plan(live: true, reminderMinutes: minutes).liveActivity?.start == utc("2026-11-08T17:00:00Z"))
}

@Test func varningFolkerMedIAktiviteten() {
    #expect(plan(live: true, events: [event("2026-11-09", ["rest"], warning: "Helgdag.")]).liveActivity?.content.warning == "Helgdag.")
    #expect(plan(live: true).liveActivity?.content.warning == nil)
}

@Test func langtAdressnamnKortasTill60Tecken() {
    let home = address(homeKey, name: String(repeating: "å", count: 100), primary: true, notifications: false)
    let p = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: home, schedule: schedule(homeKey, events: standardEvents))],
        settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: friday, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
    #expect(p.liveActivity?.content.addressName == String(repeating: "å", count: 60))
    let short = ReminderPlanner.plan(PlannerInput(
        addresses: [PlannerAddress(address: address(homeKey, name: "Hemma", primary: true, notifications: false), schedule: schedule(homeKey, events: standardEvents))],
        settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: friday, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []
    ))
    #expect(short.liveActivity?.content.addressName == "Hemma")
}

@Test func hogst60MedFleraAdresser() {
    var entries: [PlannerAddress] = []
    for n in 0..<4 {
        let key = AddressKey(source: "s", id: "a\(n)")
        let events = (0..<30).map { event(day("2026-11-10").adding(days: $0 * 2 + n).iso, ["rest"]) }
        entries.append(PlannerAddress(address: address(key, name: "A\(n)", primary: n == 0, notifications: true), schedule: schedule(key, events: events)))
    }
    let p = ReminderPlanner.plan(PlannerInput(addresses: entries, settings: ReminderSettings(), placedOut: [], now: friday, liveActivitiesAllowed: true, existingActivities: [], shownActivities: []))
    #expect(p.notifications.count == 60)
    #expect(p.notifications.map(\.fireDate) == p.notifications.map(\.fireDate).sorted())
    #expect(Set(p.notifications.map(\.identifier)).count == 60)
    // 120 tömningar finns. De 60 närmaste ryms före 2026-11-10 + 30 dagar.
    #expect(p.notifications.last!.pickupDate <= day("2026-11-10").adding(days: 31))
}

@Test func liveActivityNekadBehallerNotisen() {
    let p = plan(notifications: true, live: true, allowed: false)
    #expect(p.liveActivity == nil)
    #expect(p.notifications[0].pickupDate == day("2026-11-09"))
}

@Test func liveActivityAvBehallerNotisen() {
    #expect(plan(notifications: true, live: false).notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-09") })
}

@Test func paTomningsdagenGerNastaAktivitetOchNotisenStarKvarUtanExisterandeAktivitet() {
    let p = plan(notifications: true, live: true, now: stockholm("2026-11-09T07:00"))
    #expect(p.liveActivity?.pickupDate == day("2026-11-12"))
    #expect(p.notifications.contains { $0.key == homeKey && $0.pickupDate == day("2026-11-12") })
}

@Test func borttagenHuvudadressGerInteAktivitetForDen() {
    #expect(plan(live: true, withPrimary: false).liveActivity == nil)
    // Notiserna påverkas inte.
    #expect(plan(notifications: true, live: true, withPrimary: false).notifications.contains { $0.pickupDate == day("2026-11-09") })
}

@Test func planenAnvanderTidenFranNowOchInteSvarets_today() {
    // Svaret är hämtat 6 nov, men "i dag" är 11 nov: 9 nov är passerad.
    let la = plan(live: true, now: stockholm("2026-11-11T12:00")).liveActivity
    #expect(la?.pickupDate == day("2026-11-12"))
    #expect(la?.startsImmediately == false)
}

/// Ändrar processens tidszon och måste därför köras ensam. Telefonens tidszon får inte påverka planen.
@Suite(.serialized)
struct TelefonensTidszon {
    @Test func telefonensTidszonSpelarIngenRoll() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }

        func run(_ zone: String) -> ReminderPlan {
            NSTimeZone.default = TimeZone(identifier: zone)!
            return plan(notifications: true, live: true, now: stockholm("2026-11-08T20:00"))
        }
        let stockholmPlan = run("Europe/Stockholm")
        let newYorkPlan = run("America/New_York")
        let tokyoPlan = run("Asia/Tokyo")
        #expect(stockholmPlan == newYorkPlan)
        #expect(stockholmPlan == tokyoPlan)
        #expect(stockholmPlan.liveActivity?.start == utc("2026-11-08T17:00:00Z"))
        #expect(stockholmPlan.notifications.first?.fireDate == utc("2026-11-09T17:00:00Z"))
    }
}
