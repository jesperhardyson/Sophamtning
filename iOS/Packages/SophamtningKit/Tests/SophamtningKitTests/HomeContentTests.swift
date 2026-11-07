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

private func saved(_ id: String, name: String, street: String, locality: String, kommun: String = "Avesta kommun", primary: Bool, notifications: Bool = false) -> SavedAddress {
    var value = SavedAddress.fixture(key: AddressKey(source: "x", id: id), isPrimary: primary)
    value.displayName = name
    value.street = street
    value.locality = locality
    value.kommun = kommun
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
    #expect(primary.subtitle == "Storgatan\u{00A0}12 B, Krylbo\u{00A0}· Avesta kommun")
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
    #expect(row.subtitle == "Bergsvägen\u{00A0}4, Horndal\u{00A0}· Avesta kommun")
    #expect(row.summary == "Ons 18 nov\u{00A0}· om 12 dagar")
    guard case .upcoming(let pickup) = row.status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.fractions.map(\.id) == ["plast"])
    #expect(row.accessibilityLabel == "Stugan, Bergsvägen 4, Horndal · Avesta kommun, Ons 18 nov · om 12 dagar, Plastförpackningar")
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
    #expect(content.others[0].summary == "ca Ons 18 nov\u{00A0}· om 12 dagar")
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

@Test func felVidStartVisasAvenMedNotiser() throws {
    // Notiser på, misslyckad direktstart och passerad tid: varken aktivitet eller notis för nästa tömning.
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.")
    #expect(try #require(content.primary).reminderText == "Kunde inte läggas in.")
}

@Test func felVisasInteNarValetArAv() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: false), now: now, liveActivityError: "Gammalt fel.")
    #expect(try #require(content.primary).reminderText == "Påminnelse söndag kl. 18:00")
}

@Test func passeradPaminnelseForNastaTomningVisas() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(), now: now, missedReminder: "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
    #expect(try #require(content.primary).reminderText == "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
}

@Test func felGarForePasseradPaminnelse() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.", missedReminder: "Passerad.")
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

// MARK: Plats på alla kort

@Test func undertitelnHarGataOrtOchKommunensHelaNamn() throws {
    let street = saved("s", name: "Hemma", street: "Storgatan 12", locality: "Krylbo", primary: true)
    let area = saved("a", name: "Stugan", street: "Kaplansgården", locality: "Jularbo m.fl.", primary: false)
    let content = make([street, area], [:])
    #expect(try #require(content.primary).subtitle == "Storgatan\u{00A0}12, Krylbo\u{00A0}· Avesta kommun")
    #expect(content.others[0].subtitle == "Kaplansgården, Jularbo m.fl.\u{00A0}· Avesta kommun")
}

@Test func undertitelnForOmradeUtanOrtHarKommunen() throws {
    let area = saved("a", name: "Stugan", street: "Kaplansgården", locality: "", primary: true)
    #expect(try #require(make([area], [:]).primary).subtitle == "Kaplansgården\u{00A0}· Avesta kommun")
}

@Test func kommunenVisasInteNarDenArSammaSomOrten() throws {
    let same = saved("u", name: "Jobbet", street: "Stationsgatan 12", locality: "Uppsala", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([same], [:]).primary).subtitle == "Stationsgatan\u{00A0}12, Uppsala")
    // Utan hänsyn till skiftläge.
    let shouting = saved("v", name: "Jobbet", street: "Stationsgatan 12", locality: "UPPSALA", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([shouting], [:]).primary).subtitle == "Stationsgatan\u{00A0}12, UPPSALA")
}

@Test func undertitelnUtanGataHarOrtOchKommun() throws {
    let noStreet = saved("t", name: "Hemma", street: "", locality: "Krylbo", primary: true)
    #expect(try #require(make([noStreet], [:]).primary).subtitle == "Krylbo\u{00A0}· Avesta kommun")
    let onlyKommun = saved("k", name: "Hemma", street: " ", locality: "", primary: true)
    #expect(try #require(make([onlyKommun], [:]).primary).subtitle == "Avesta kommun")
}

@Test func kommunensKortaNamnSomISokningen() {
    #expect(shortKommunName("Avesta kommun") == "Avesta")
    #expect(shortKommunName("Region Gotland") == "Region Gotland")
}

@Test func kommunVisasMedHelaNamnet() {
    #expect(kommunDisplayName("Säters kommun") == "Säters kommun")
    #expect(kommunDisplayName(" Avesta kommun ") == "Avesta kommun")
    #expect(kommunDisplayName("Region Gotland") == "Region Gotland")
}

@Test func kommunenUppreparOrtenAvenIGenitiv() {
    #expect(kommunRepeatsLocality("Säters kommun", locality: "Säter"))
    #expect(kommunRepeatsLocality("Stockholms kommun", locality: "Stockholm"))
    #expect(kommunRepeatsLocality("Falu kommun", locality: "Falun"))
    #expect(kommunRepeatsLocality("Uppsala kommun", locality: "Uppsala"))
    #expect(kommunRepeatsLocality("Uppsala kommun", locality: "uppsala"))
    #expect(!kommunRepeatsLocality("Avesta kommun", locality: "Krylbo"))
    #expect(!kommunRepeatsLocality("Avesta kommun", locality: ""))
    #expect(!kommunRepeatsLocality("Säters kommun", locality: "Sät"))
}

@Test func ortOchKommunSomPaKortensUndertitel() {
    // Sökträffens rad: kommunen döljs när den bara upprepar orten, annars står hela namnet efter en mittpunkt.
    #expect(localityAndKommun(locality: "Uppsala", kommun: "Uppsala kommun") == "Uppsala")
    #expect(localityAndKommun(locality: "Säter", kommun: "Säters kommun") == "Säter")
    #expect(localityAndKommun(locality: "Krylbo", kommun: "Avesta kommun") == "Krylbo\u{00A0}· Avesta kommun")
    #expect(localityAndKommun(locality: " ", kommun: "Avesta kommun") == "Avesta kommun")
    #expect(localityAndKommun(locality: "Krylbo", kommun: "") == "Krylbo")
}

@Test func undertitelnDoljerKommunenSomBaraUppreparOrten() throws {
    let sater = saved("s", name: "Hemma", street: "Storgatan 3", locality: "Säter", kommun: "Säters kommun", primary: true)
    let stockholm = saved("t", name: "Jobbet", street: "Drottninggatan 1", locality: "Stockholm", kommun: "Stockholms kommun", primary: false)
    let falun = saved("f", name: "Stugan", street: "Åsgatan 5", locality: "Falun", kommun: "Falu kommun", primary: false)
    let content = make([sater, stockholm, falun], [:])
    #expect(try #require(content.primary).subtitle == "Storgatan\u{00A0}3, Säter")
    #expect(content.others.map(\.subtitle) == ["Drottninggatan\u{00A0}1, Stockholm", "Åsgatan\u{00A0}5, Falun"])
}

@Test func mittpunktenBorjarAldrigEnRad() throws {
    let content = make([home, cabin], [home.key: schedule([event("2026-11-09", ["rest"])]), cabin.key: schedule([event("2026-11-18", ["plast"])])])
    for entry in [try #require(content.primary)] + content.others {
        #expect(!entry.subtitle.contains(" ·"))
        #expect(!entry.summary.contains(" ·"))
    }
    // Gatunamn och nummer hålls ihop, men husets bokstav får stå kvar.
    #expect(try #require(content.primary).subtitle == "Storgatan\u{00A0}12 B, Krylbo\u{00A0}· Avesta kommun")
}

// MARK: Påminnelse på raderna

private let tuesdayPickup = [event("2026-11-11", ["rest"])]

@Test func radMedNotisPaVisarPlaneradPaminnelse() throws {
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let content = make([home, other], [home.key: schedule(tuesdayPickup), other.key: schedule(tuesdayPickup)])
    #expect(content.others[0].rowReminder == .scheduled("Påminnelse tisdag kl. 18:00"))
    #expect(content.others[0].rowReminder?.text == "Påminnelse tisdag kl. 18:00")
    // Raden har sitt läge, och huvudkortets text är bara huvudkortets.
    #expect(content.others[0].reminderText == nil)
    #expect(content.primary?.rowReminder == nil)
}

@Test func radMedNotisAvVisarIngenPaminnelse() throws {
    let content = make([home, cabin], [home.key: schedule(tuesdayPickup), cabin.key: schedule(tuesdayPickup)])
    #expect(content.others[0].rowReminder == nil)
}

@Test func radMedNekadeNotiserSagerAttNotiserArAvstangda() throws {
    var primary = home
    primary.notificationsOn = true
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let content = HomeContent.make(addresses: [primary, other], schedules: [primary.key: schedule(tuesdayPickup), other.key: schedule(tuesdayPickup)], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    #expect(content.others[0].rowReminder == .denied)
    #expect(content.others[0].rowReminder?.text == "Notiser är avstängda i iOS")
    // Huvudkortet ändras inte.
    #expect(content.primary?.reminderText == "Påminn mig kvällen före")
}

@Test func radMedNotisAvOchNekadeNotiserVisarIngenting() throws {
    let content = HomeContent.make(addresses: [home, cabin], schedules: [home.key: schedule(tuesdayPickup), cabin.key: schedule(tuesdayPickup)], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    #expect(content.others[0].rowReminder == nil)
}

@Test func radNarNotiserInteArBestamdaVisarPlaneradPaminnelse() throws {
    // iOS har inte frågat än (till exempel efter en ominstallation): inte nekat, så raden visar det planerade läget.
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let content = HomeContent.make(addresses: [home, other, cabin], schedules: [home.key: schedule(tuesdayPickup), other.key: schedule(tuesdayPickup), cabin.key: schedule(tuesdayPickup)], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: false)
    #expect(content.others[0].rowReminder == .scheduled("Påminnelse tisdag kl. 18:00"))
    // Notis av för adressen: ingenting.
    #expect(content.others[1].rowReminder == nil)
}

@Test func radensPaminnelseHarIngenLiveActivity() throws {
    // Live Activity gäller bara huvudadressen. Raden visar notisen även när Live Activity är på eller har fel.
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let pending = activity(pending: true, start: StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 17 * 60 + 30))
    let content = HomeContent.make(addresses: [home, other], schedules: [home.key: schedule([event("2026-11-09", ["rest"])]), other.key: schedule(tuesdayPickup)], settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: pending, liveActivityError: "Kunde inte läggas in.", reserveAt: now.addingTimeInterval(3600))
    #expect(content.others[0].rowReminder == .scheduled("Påminnelse tisdag kl. 18:00"))
}

@Test func radenRaknarFranNastaKvallSomInteHarPasserat() throws {
    // Tömning i morgon lördag, och kvällen före (fredag 18:00) har passerat: samma text som huvudkortet.
    let evening = StockholmClock.date(on: today, minutes: 19 * 60)
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let events = [event("2026-11-07", ["rest"]), event("2026-11-11", ["mat"])]
    let content = make([home, other], [home.key: schedule(events), other.key: schedule(events)], at: evening)
    #expect(content.others[0].rowReminder == .missed("Tömning i morgon. Påminnelsen för i kväll har redan passerat."))
    // Tömning i dag: kvällen före har passerat, och påminnelsen gäller tömningen på onsdag.
    let todayFirst = make([home, other], [home.key: schedule(tuesdayPickup), other.key: schedule([event("2026-11-06", ["rest"]), event("2026-11-11", ["mat"])])])
    #expect(todayFirst.others[0].rowReminder == .scheduled("Påminnelse tisdag kl. 18:00"))
    // Ingen senare tömning: samma neutrala text som huvudkortet.
    let onlyToday = make([home, other], [home.key: schedule(tuesdayPickup), other.key: schedule([event("2026-11-06", ["rest"])])])
    #expect(onlyToday.others[0].rowReminder == .scheduled("Påminnelser på"))
}

@Test func radUtanKommandeHamtningHarIngenPaminnelse() throws {
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let content = make([home, other], [home.key: schedule(tuesdayPickup), other.key: schedule([event("2026-11-02", ["rest"])])])
    #expect(content.others[0].rowReminder == nil)
}
