import Testing
import Foundation
import SophamtningKit

private let monday = DayDate("2026-11-09")!
private let today = DayDate("2026-11-06")!
/// Fredag 6 november 2026 klockan 12:00 svensk tid.
private let now = StockholmClock.date(on: today, minutes: 12 * 60)

private let info: [String: FractionInfo] = [
    "rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#474C48", icon: "trash-2"),
    "mat": FractionInfo(name: "Matavfall", short: "Mat", color: "#7A4A1E", icon: "apple"),
    "plast": FractionInfo(name: "Plastförpackningar", short: "Plast", color: "#A8431F", icon: "cup-soda"),
]

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false) -> PickupEvent {
    PickupEvent(date: DayDate(iso)!, fractions: fractions, estimated: estimated, deviation: nil, warning: nil, labels: [:])
}

private func schedule(_ events: [PickupEvent], savedToday: String = "2026-11-06", lastError: APIError? = nil) -> CachedSchedule {
    let response = AddressResponse(
        today: DayDate(savedToday)!,
        address: Address(id: "a", street: "Storgatan 12 B", locality: "Krylbo", kommun: "Avesta", source: "x", detail: nil, selection: "address", notice: nil),
        next: [], summary: "Gammal text", events: events, bins: [], fractions: info,
        links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
        updatedAt: DayDate(savedToday)!
    )
    return CachedSchedule(response: response, fetchedAt: now, lastAttemptAt: now, lastError: lastError)
}

private func saved(_ id: String, name: String, street: String, locality: String, primary: Bool, notifications: Bool = false) -> SavedAddress {
    var value = SavedAddress.fixture(key: AddressKey(source: "x", id: id), isPrimary: primary)
    value.displayName = name
    value.street = street
    value.locality = locality
    value.notificationsOn = notifications
    return value
}

private let home = saved("home", name: "Hemma", street: "Storgatan 12 B", locality: "Krylbo", primary: true)
private let cabin = saved("cabin", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false)

private func make(_ addresses: [SavedAddress], _ schedules: [AddressKey: CachedSchedule], settings: ReminderSettings = ReminderSettings(), at time: Date = now) -> HomeContent {
    HomeContent.make(addresses: addresses, schedules: schedules, settings: settings, now: time)
}

@Test func utanAdresserFinnsInteNagotHuvudkort() {
    let content = make([], [:])
    #expect(content.primary == nil)
    #expect(content.others.isEmpty)
}

@Test func huvudkortetVisarNastaTomning() throws {
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest", "mat"])])])
    let primary = try #require(content.primary)
    #expect(primary.title == "Hemma")
    #expect(primary.subtitle == "Storgatan 12 B, Krylbo")
    guard case .upcoming(let pickup) = primary.status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.date == monday)
    #expect(pickup.headline == "Om 3 dagar")
    #expect(pickup.longDate == "Måndag 9 november")
    #expect(pickup.fractions.map(\.id) == ["rest", "mat"])
    #expect(pickup.fractions.map(\.info.name) == ["Restavfall", "Matavfall"])
}

@Test func ovrigaAdresserBlirRaderMedKortDatumOchRelativDag() throws {
    let content = make([home, cabin], [
        home.key: schedule([event("2026-11-09", ["rest"])]),
        cabin.key: schedule([event("2026-11-18", ["plast"])]),
    ])
    let row = try #require(content.others.first)
    #expect(content.others.count == 1)
    #expect(row.title == "Stugan")
    #expect(row.subtitle == "Bergsvägen 4, Horndal")
    #expect(row.summary == "Ons 18 nov · om 12 dagar")
    guard case .upcoming(let pickup) = row.status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.fractions.map(\.id) == ["plast"])
    #expect(row.accessibilityLabel == "Stugan, Bergsvägen 4, Horndal, Ons 18 nov · om 12 dagar, Plastförpackningar")
}

@Test func dagarRaknasLokaltEjFranSparatDatum() throws {
    // Svaret sparades den 6:e, men nu är det lördag den 7:e.
    let later = StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 9 * 60)
    let content = make([home], [home.key: schedule([event("2026-11-08", ["rest"])])], at: later)
    guard case .upcoming(let pickup) = try #require(content.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.headline == "I morgon")
}

@Test func hamtningIDagVisasSomIDag() throws {
    let content = make([home], [home.key: schedule([event("2026-11-06", ["rest"])])])
    guard case .upcoming(let pickup) = try #require(content.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.headline == "I dag")
}

@Test func uppskattatDatumVisasMedCa() throws {
    let content = make([home, cabin], [
        home.key: schedule([event("2026-11-09", ["rest"], estimated: true)]),
        cabin.key: schedule([event("2026-11-18", ["plast"], estimated: true)]),
    ])
    guard case .upcoming(let pickup) = try #require(content.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.headline == "Ca om 3 dagar")
    #expect(pickup.longDate == "Ca måndag 9 november")
    #expect(content.others[0].summary == "ca Ons 18 nov · om 12 dagar")
}

@Test func passeratSchemaGerIngaKommandeHamtningar() throws {
    let content = make([home], [home.key: schedule([event("2026-11-02", ["rest"])])], settings: ReminderSettings())
    let primary = try #require(content.primary)
    #expect(primary.status == .noUpcoming)
    #expect(primary.summary == "Inga kommande hämtningar")
    #expect(primary.reminderText == nil)
}

@Test func utanPaslagenPaminnelseVisasInbjudan() throws {
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])])
    #expect(try #require(content.primary).reminderText == "Påminn mig kvällen före")
}

@Test func notisPaGerPaminnelseKvallenFore() throws {
    var on = home
    on.notificationsOn = true
    let content = make([on], [on.key: schedule([event("2026-11-09", ["rest"])])])
    #expect(try #require(content.primary).reminderText == "Påminnelse söndag kl. 18:00")
}

@Test func utanAktivitetLovasIngenLiveActivity() throws {
    // Utan någon aktivitet hos systemet påminner inget, och kortet får inte låta som att något gör det.
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(reminderMinutes: 1050, liveActivityOn: true))
    #expect(try #require(content.primary).reminderText == "Ingen Live Activity planerad")
}

@Test func felVidStartVisasPaKortet() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.")
    #expect(try #require(content.primary).reminderText == "Kunde inte läggas in.")
}

@Test func passeradStarttidLovasInte() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: now.addingTimeInterval(-60)))
    #expect(try #require(content.primary).reminderText == "Ingen Live Activity planerad")
}

private func activity(pending: Bool, start: Date) -> ExistingActivity {
    ExistingActivity(id: "a", key: home.key, pickupDate: DayDate("2026-11-09")!, content: PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [], estimated: false, warning: nil), isPending: pending, start: start)
}

@Test func vantandeLiveActivityVisarSinStarttid() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let start = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 1050)
    // Tiden kommer från aktiviteten, som kan ha lagts in före en ändring av inställningen.
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(reminderMinutes: 1200, liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: start))
    #expect(try #require(content.primary).reminderText == "Live Activity söndag kl. 17:30")
}

@Test func startadLiveActivityVisasSomPagaende() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: false, start: now))
    #expect(try #require(content.primary).reminderText == "Live Activity visas nu")
}

@Test func utanAktivitetVisasNotisenSomForut() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    // Starten misslyckades eller ska inte ske, och notisen är det som faktiskt påminner.
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: nil)
    #expect(try #require(content.primary).reminderText == "Påminnelse söndag kl. 18:00")
}

@Test func avstangdaLiveActivitiesSagsPaKortet() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivitiesEnabled: false)
    #expect(try #require(content.primary).reminderText == "Live Activities är avstängda")
}

@Test func notisValetSomIosInteTillaterVisasSomAv() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let denied = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(), now: now, remindersAllowed: false)
    #expect(try #require(denied.primary).reminderText == "Påminn mig kvällen före")
    let liveOnly = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, remindersAllowed: false)
    #expect(try #require(liveOnly.primary).reminderText == "Ingen Live Activity planerad")
}

@Test func saknatSchemaVisasInteSomAttAdressenSaknas() throws {
    let loading = make([home], [:])
    #expect(try #require(loading.primary).status == .loading)
    let failed = make([home], [home.key: CachedSchedule(response: nil, fetchedAt: nil, lastAttemptAt: now, lastError: .network)])
    #expect(try #require(failed.primary).status == .failed(.network))
    #expect(try #require(failed.primary).summary == "Kunde inte hämta schemat")
}

@Test func felEfterTidigareLyckatSvarBehallerSchemaOchNoterarFelet() throws {
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])], lastError: .sourceUnavailable)])
    let primary = try #require(content.primary)
    guard case .upcoming = primary.status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(primary.refreshFailed)
}

@Test func okandFraktionVisasMedIdSomNamn() throws {
    var unknown = schedule([event("2026-11-09", ["tradgard"])])
    unknown.response = AddressResponse(today: unknown.response!.today, address: unknown.response!.address, next: [], summary: "", events: unknown.response!.events, bins: [], fractions: [:], links: unknown.response!.links, updatedAt: today)
    guard case .upcoming(let pickup) = try #require(make([home], [home.key: unknown]).primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.fractions.map(\.info.name) == ["tradgard"])
}

@Test func utanHuvudmarkeringFarForstaAdressenHuvudkortet() throws {
    var first = home
    first.isPrimary = false
    #expect(try #require(make([first, cabin], [:]).primary).title == "Hemma")
}

@Test func adressSomInteFinnsLangreFarEgenText() throws {
    let gone = make([home], [home.key: CachedSchedule(response: nil, fetchedAt: nil, lastAttemptAt: now, lastError: .notFound)])
    #expect(try #require(gone.primary).summary == "Adressen hittas inte längre")
}

@Test func radMedMisslyckadUppdateringNamnerDetISinEtikett() throws {
    let content = make([home, cabin], [
        home.key: schedule([event("2026-11-09", ["rest"])]),
        cabin.key: schedule([event("2026-11-18", ["plast"])], lastError: .network),
    ])
    #expect(content.others[0].accessibilityLabel.contains("Kunde inte uppdateras"))
}

private func reminder(events: [PickupEvent], at time: Date) throws -> String? {
    var on = home
    on.notificationsOn = true
    return try #require(make([on], [on.key: schedule(events)], at: time).primary).reminderText
}

@Test func tomningIDagUtanSenareHamtningGerNeutralPaminnelsetext() throws {
    #expect(try reminder(events: [event("2026-11-06", ["rest"])], at: now) == "Påminnelser på")
}

@Test func tomningIDagRaknarPaminnelsenFranNastaHamtning() throws {
    let events = [event("2026-11-06", ["rest"]), event("2026-11-09", ["mat"])]
    #expect(try reminder(events: events, at: now) == "Påminnelse söndag kl. 18:00")
}

@Test func tomningIMorgonForeKlockan18GerPaminnelseSammaKvall() throws {
    #expect(try reminder(events: [event("2026-11-07", ["rest"])], at: now) == "Påminnelse fredag kl. 18:00")
}

@Test func tomningIMorgonEfter18GerNeutralTextOmIngenSenareFinns() throws {
    let evening = StockholmClock.date(on: today, minutes: 19 * 60)
    #expect(try reminder(events: [event("2026-11-07", ["rest"])], at: evening) == "Påminnelser på")
    let later = [event("2026-11-07", ["rest"]), event("2026-11-12", ["mat"])]
    #expect(try reminder(events: later, at: evening) == "Påminnelse onsdag kl. 18:00")
}
