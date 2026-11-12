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
    #expect(primary.lines == HomeContent.AddressLines(address: "Storgatan\u{00A0}12 B", place: "Krylbo\u{00A0}· Avesta kommun"))
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
    #expect(row.lines == HomeContent.AddressLines(address: "Bergsvägen\u{00A0}4", place: "Horndal\u{00A0}· Avesta kommun"))
    #expect(row.summary == "Ons 18 nov\u{00A0}· om 12 dagar")
    guard case .upcoming(let pickup) = row.status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.fractions.map(\.id) == ["plast"])
    #expect(row.accessibilityLabel == "Stugan, Bergsvägen 4, Horndal, Avesta kommun, Ons 18 nov · om 12 dagar, Plastförpackningar")
}

@Test func dagarRaknasLokaltEjFranSparatDatum() throws {
    // Svaret sparades den 6:e, men nu är det lördag den 7:e.
    let later = StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 9 * 60)
    let content = make([home], [home.key: schedule([event("2026-11-08", ["rest"])])], at: later)
    guard case .upcoming(let pickup) = try #require(content.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.headline == "I morgon")
}

@Test func tvaDagarKvarArIOvermorgon() throws {
    // Nu är det lördag den 7:e, och tömningen är måndag den 9:e.
    let later = StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 9 * 60)
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])], at: later)
    guard case .upcoming(let pickup) = try #require(content.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(pickup.headline == "I övermorgon")
    // Ett beräknat datum får "Ca" först.
    let estimated = make([home], [home.key: schedule([event("2026-11-09", ["rest"], estimated: true)])], at: later)
    guard case .upcoming(let guess) = try #require(estimated.primary).status else { Issue.record("Väntade kommande hämtning"); return }
    #expect(guess.headline == "Ca i övermorgon")
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

// MARK: Tömningsdagen

@Test func tomningIDagGerRad() throws {
    let primary = try #require(make([home], [home.key: schedule([event("2026-11-06", ["rest"])])], settings: ReminderSettings()).primary)
    #expect(primary.dayNote == "Kärlen ska stå ute i dag.")
}

@Test func tomningIMorgonGerIngenRad() throws {
    let primary = try #require(make([home], [home.key: schedule([event("2026-11-07", ["rest"])])], settings: ReminderSettings()).primary)
    #expect(primary.dayNote == nil)
}

@Test func beraknadTomningIDagSagerSomBeraknat() throws {
    let primary = try #require(make([home], [home.key: schedule([event("2026-11-06", ["rest"], estimated: true)])], settings: ReminderSettings()).primary)
    #expect(primary.dayNote == "Kärlen ska stå ute i dag, om tömningen kommer som beräknat.")
}

@Test func utanHamtningarGerIngenRad() throws {
    let primary = try #require(make([home], [home.key: schedule([event("2026-11-02", ["rest"])])], settings: ReminderSettings()).primary)
    #expect(primary.dayNote == nil)
}

@Test func passeratSchemaGerIngaKommandeHamtningar() throws {
    let content = make([home], [home.key: schedule([event("2026-11-02", ["rest"])])], settings: ReminderSettings())
    let primary = try #require(content.primary)
    #expect(primary.status == .noUpcoming)
    #expect(primary.summary == "Inga kommande hämtningar")
    #expect(primary.reminder == nil)
}

@Test func utanPaslagenPaminnelseVisasInbjudan() throws {
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])])
    #expect(try #require(content.primary).reminder?.detail == nil)
}

@Test func notisPaGerPaminnelseKvallenFore() throws {
    var on = home
    on.notificationsOn = true
    let content = make([on], [on.key: schedule([event("2026-11-09", ["rest"])])])
    #expect(try #require(content.primary).reminder?.detail == "Söndag kl. 18:00")
}

@Test func utanAktivitetLovasIngenLiveActivity() throws {
    // Utan någon aktivitet hos systemet påminner inget, och kortet får inte låta som att något gör det.
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(reminderMinutes: 1050, liveActivityOn: true))
    #expect(try #require(content.primary).reminder?.detail == "Ingen Live Activity planerad")
}

@Test func felVidStartVisasPaKortet() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.")
    #expect(try #require(content.primary).reminder?.detail == "Kunde inte läggas in.")
}

@Test func felVidStartVisasAvenMedNotiser() throws {
    // Notiser på, misslyckad direktstart och passerad tid: varken aktivitet eller notis för nästa tömning.
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.")
    #expect(try #require(content.primary).reminder?.detail == "Kunde inte läggas in.")
}

@Test func felVisasInteNarValetArAv() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: false), now: now, liveActivityError: "Gammalt fel.")
    #expect(try #require(content.primary).reminder?.detail == "Söndag kl. 18:00")
}

@Test func passeradPaminnelseForNastaTomningVisas() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(), now: now, missedReminder: "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
    #expect(try #require(content.primary).reminder?.detail == "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
}

@Test func felGarForePasseradPaminnelse() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivityError: "Kunde inte läggas in.", missedReminder: "Passerad.")
    #expect(try #require(content.primary).reminder?.detail == "Kunde inte läggas in.")
}

@Test func passeradStarttidLovasInte() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: now.addingTimeInterval(-60)))
    #expect(try #require(content.primary).reminder?.detail == "Ingen Live Activity planerad")
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
    // Notisen kommer 20:00, efter starten, så den nämns inte. Står den på samma minut som starten nämns båda.
    // Notisen kommer efter starten och nämns efter aktiviteten.
    #expect(try #require(content.primary).reminder?.detail == "Live Activity söndag kl. 17:30, notis söndag kl. 20:00")
    let same = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(reminderMinutes: 1050, liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: start))
    #expect(try #require(same.primary).reminder?.detail == "Notis och Live Activity söndag kl. 17:30")
}

@Test func fotenVisarBådaNotistiderna() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"]), event("2026-11-16", ["rest"])])]
    let both = ReminderSettings(eveningOn: true, morningOn: true, reminderMinutes: 900, morningMinutes: 360)
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: both, now: now)
    #expect(try #require(content.primary?.reminder).line == "Påminnelse söndag kl. 15:00 och måndag kl. 06:00")
    // När kvällens tid har passerat återstår bara morgonens för samma tömning.
    let sundayEvening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 16 * 60)
    let later = HomeContent.make(addresses: [on], schedules: schedules, settings: both, now: sundayEvening)
    #expect(try #require(later.primary?.reminder).line == "Påminnelse måndag kl. 06:00")
}

@Test func fotenVisarBådaTidernaMedLiveActivity() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let start = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 900)
    let both = ReminderSettings(eveningOn: true, morningOn: true, reminderMinutes: 900, morningMinutes: 360, liveActivityOn: true)
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: both, now: now, liveActivity: activity(pending: true, start: start))
    #expect(try #require(content.primary).reminder?.detail == "Notis och Live Activity söndag kl. 15:00, notis måndag kl. 06:00")
    // Aktiviteten på morgonen och notis bara på kvällen: båda nämns, var för sig.
    let morningStart = StockholmClock.date(on: DayDate("2026-11-09")!, minutes: 360)
    let eveningOnly = ReminderSettings(reminderMinutes: 900, liveActivityTiming: .sameMorning, liveActivityOn: true)
    let split = HomeContent.make(addresses: [on], schedules: schedules, settings: eveningOnly, now: now, liveActivity: activity(pending: true, start: morningStart))
    #expect(try #require(split.primary).reminder?.detail == "Notis söndag kl. 15:00, Live Activity måndag kl. 06:00")
}

@Test func baraLiveActivityNamnerBaraLiveActivity() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let start = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 1050)
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: start))
    #expect(try #require(content.primary).reminder?.detail == "Live Activity söndag kl. 17:30")
}

@Test func startadLiveActivityVisasSomPagaende() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: false, start: now))
    #expect(try #require(content.primary).reminder?.detail == "Live Activity visas nu")
}

@Test func utanAktivitetVisasNotisenSomForut() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    // Starten misslyckades eller ska inte ske, och notisen är det som faktiskt påminner.
    let content = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: nil)
    #expect(try #require(content.primary).reminder?.detail == "Söndag kl. 18:00")
}

@Test func avstangdaLiveActivitiesSagsPaKortet() throws {
    let schedules = [home.key: schedule([event("2026-11-09", ["rest"])])]
    let content = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, liveActivitiesEnabled: false)
    #expect(try #require(content.primary).reminder?.detail == "Live Activities är avstängda")
}

@Test func notisValetSomIosInteTillaterVisasSomAv() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let denied = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(), now: now, remindersAllowed: false)
    #expect(try #require(denied.primary).reminder?.detail == nil)
    let liveOnly = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(liveActivityOn: true), now: now, remindersAllowed: false)
    #expect(try #require(liveOnly.primary).reminder?.detail == "Ingen Live Activity planerad")
}

@Test func voiceOverAtgardenForPaminnelsenHarSammaNamnSomValet() {
    #expect(HomeContent.reminderActionTitle(isOn: false) == "Slå på påminnelse")
    #expect(HomeContent.reminderActionTitle(isOn: true) == "Stäng av påminnelse")
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
    return try #require(make([on], [on.key: schedule(events)], at: time).primary).reminder?.detail
}

@Test func tomningIDagUtanSenareHamtningGerNeutralPaminnelsetext() throws {
    #expect(try reminder(events: [event("2026-11-06", ["rest"])], at: now) == nil)
}

@Test func tomningIDagRaknarPaminnelsenFranNastaHamtning() throws {
    let events = [event("2026-11-06", ["rest"]), event("2026-11-09", ["mat"])]
    #expect(try reminder(events: events, at: now) == "Söndag kl. 18:00")
}

@Test func tomningIMorgonForeKlockan18GerPaminnelseSammaKvall() throws {
    #expect(try reminder(events: [event("2026-11-07", ["rest"])], at: now) == "Fredag kl. 18:00")
}

@Test func tomningIMorgonEfter18GerNeutralTextOmIngenSenareFinns() throws {
    let evening = StockholmClock.date(on: today, minutes: 19 * 60)
    #expect(try reminder(events: [event("2026-11-07", ["rest"])], at: evening) == nil)
    let later = [event("2026-11-07", ["rest"]), event("2026-11-12", ["mat"])]
    #expect(try reminder(events: later, at: evening) == "Onsdag kl. 18:00")
}

// MARK: Adress och plats på var sin rad

@Test func adressenOchPlatsenPaVarSinRad() throws {
    let street = saved("s", name: "Hemma", street: "Storgatan 12", locality: "Krylbo", primary: true)
    // Ett område har hela namnet som gata och ingen ort, som i API:t.
    let area = saved("a", name: "Stugan", street: "Kaplansgården, Jularbo m.fl.", locality: "", primary: false)
    let content = make([street, area], [:])
    #expect(try #require(content.primary).lines == HomeContent.AddressLines(address: "Storgatan\u{00A0}12", place: "Krylbo\u{00A0}· Avesta kommun"))
    #expect(content.others[0].lines == HomeContent.AddressLines(address: "Kaplansgården, Jularbo m.fl.", place: "Avesta kommun"))
}

@Test func kommunenVisasInteNarDenArSammaSomOrten() throws {
    let same = saved("u", name: "Jobbet", street: "Stationsgatan 12", locality: "Uppsala", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([same], [:]).primary).lines == HomeContent.AddressLines(address: "Stationsgatan\u{00A0}12", place: "Uppsala"))
    // Utan hänsyn till skiftläge.
    let shouting = saved("v", name: "Jobbet", street: "Stationsgatan 12", locality: "UPPSALA", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([shouting], [:]).primary).lines.place == "UPPSALA")
}

@Test func utanGataFinnsBaraPlatsen() throws {
    let noStreet = saved("t", name: "Hemma", street: "", locality: "Krylbo", primary: true)
    #expect(try #require(make([noStreet], [:]).primary).lines == HomeContent.AddressLines(address: "", place: "Krylbo\u{00A0}· Avesta kommun"))
    let onlyKommun = saved("k", name: "Hemma", street: " ", locality: "", primary: true)
    #expect(try #require(make([onlyKommun], [:]).primary).lines == HomeContent.AddressLines(address: "", place: "Avesta kommun"))
}

@Test func gatanUpprepasInteNarNamnetArDetsamma() throws {
    // Ett område sparas med sitt namn, som också är gatan. Bara platsen står under namnet.
    let area = saved("r", name: "Ringänget, Veddarsbo m.fl.", street: "Ringänget, Veddarsbo m.fl.", locality: "", primary: true)
    let entry = try #require(make([area], [:]).primary)
    #expect(entry.lines == HomeContent.AddressLines(address: "", place: "Avesta kommun"))
    #expect(entry.accessibilityLabel.hasPrefix("Ringänget, Veddarsbo m.fl., Avesta kommun"))
    // Samma sak med en gata med nummer, oavsett skiftläge och mellanslag runt omkring.
    let street = saved("s", name: "testgatan 3", street: " Testgatan 3 ", locality: "Uppsala", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([street], [:]).primary).lines == HomeContent.AddressLines(address: "", place: "Uppsala"))
    // Ett eget namn ger gatan på raden under, som förut.
    let named = saved("n", name: "Hemma", street: "Testgatan 3", locality: "Uppsala", kommun: "Uppsala kommun", primary: true)
    #expect(try #require(make([named], [:]).primary).lines.address == "Testgatan\u{00A0}3")
}

@Test func helaSchematVisarAlltidAdressenMedNamn() throws {
    // Ett område som sparats med sitt namn: namnet står en gång, som namn, och platsen under. Gatan tas bort som dubblett,
    // inte adressen.
    let area = saved("r", name: "Ringänget, Veddarsbo m.fl.", street: "Ringänget, Veddarsbo m.fl.", locality: "", primary: true)
    let areaLines = HomeContent.namedLines(for: area)
    #expect(areaLines == HomeContent.AddressLines(name: "Ringänget, Veddarsbo m.fl.", address: "", place: "Avesta kommun"))
    #expect(areaLines.accessibilityLabel == "Ringänget, Veddarsbo m.fl., Avesta kommun")
    // En gata som sparats med gatan som namn, som alla adresser utom den första.
    let street = saved("s", name: "Storgatan 12", street: "Storgatan 12", locality: "Krylbo", primary: false)
    let streetLines = HomeContent.namedLines(for: street)
    #expect(streetLines == HomeContent.AddressLines(name: "Storgatan\u{00A0}12", address: "", place: "Krylbo\u{00A0}· Avesta kommun"))
    #expect(streetLines.accessibilityLabel == "Storgatan 12, Krylbo, Avesta kommun")
    // Ett eget namn: namnet, gatan och platsen.
    let named = saved("n", name: "Hemma", street: "Storgatan 12", locality: "Krylbo", primary: true)
    let namedLines = HomeContent.namedLines(for: named)
    #expect(namedLines == HomeContent.AddressLines(name: "Hemma", address: "Storgatan\u{00A0}12", place: "Krylbo\u{00A0}· Avesta kommun"))
    #expect(namedLines.accessibilityLabel == "Hemma, Storgatan 12, Krylbo, Avesta kommun")
    // Ett område med eget namn.
    let stugan = saved("a", name: "Stugan", street: "Kaplansgården, Jularbo m.fl.", locality: "", primary: false)
    #expect(HomeContent.namedLines(for: stugan) == HomeContent.AddressLines(name: "Stugan", address: "Kaplansgården, Jularbo m.fl.", place: "Avesta kommun"))
}

@Test func adressenSynsMinstEnGangOverallt() throws {
    // Kortet, raderna och adressvyn har namnet som rubrik, och Hela schemat har det på första raden. Varje vy visar
    // alltså namnet, och gatan när den skiljer sig från namnet.
    let addresses = [
        saved("r", name: "Ringänget, Veddarsbo m.fl.", street: "Ringänget, Veddarsbo m.fl.", locality: "", primary: true),
        saved("s", name: "Storgatan 12", street: "Storgatan 12", locality: "Krylbo", primary: false),
        saved("n", name: "Hemma", street: "Bergsvägen 4", locality: "Horndal", primary: false),
    ]
    let content = make(addresses, [:])
    let entries = [try #require(content.primary)] + content.others
    for (entry, address) in zip(entries, addresses) {
        let plain = address.displayName
        #expect(entry.title == plain)
        #expect(entry.accessibilityLabel.hasPrefix(plain))
        let street = address.street
        #expect(entry.title == street || entry.lines.accessibilityLabel.hasPrefix(street.replacingOccurrences(of: "\u{00A0}", with: " ")))
        let full = HomeContent.namedLines(for: address).accessibilityLabel
        #expect(full.hasPrefix(plain))
        #expect(full.contains(street))
        #expect(full.hasSuffix("kommun"))
    }
}

@Test func voiceOverLaserAdressOchPlatsUtanMittpunkt() {
    #expect(HomeContent.AddressLines(address: "Storgatan\u{00A0}12", place: "Krylbo\u{00A0}· Avesta kommun").accessibilityLabel == "Storgatan 12, Krylbo, Avesta kommun")
    #expect(HomeContent.AddressLines(address: "Kaplansgården, Jularbo m.fl.", place: "Avesta kommun").accessibilityLabel == "Kaplansgården, Jularbo m.fl., Avesta kommun")
    #expect(HomeContent.AddressLines(address: "", place: "Uppsala").accessibilityLabel == "Uppsala")
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
    #expect(try #require(content.primary).lines.place == "Säter")
    #expect(content.others.map(\.lines.place) == ["Stockholm", "Falun"])
}

@Test func mittpunktenBorjarAldrigEnRad() throws {
    let content = make([home, cabin], [home.key: schedule([event("2026-11-09", ["rest"])]), cabin.key: schedule([event("2026-11-18", ["plast"])])])
    for entry in [try #require(content.primary)] + content.others {
        #expect(!entry.lines.place.contains(" ·"))
        #expect(!entry.summary.contains(" ·"))
    }
    // Gatunamn och nummer hålls ihop, men husets bokstav får stå kvar.
    #expect(try #require(content.primary).lines.address == "Storgatan\u{00A0}12 B")
}

// MARK: Påminnelse på raderna

private let tuesdayPickup = [event("2026-11-11", ["rest"])]

@Test func radMedNotisPaVisarPlaneradPaminnelse() throws {
    let other = saved("o", name: "Stugan", street: "Bergsvägen 4", locality: "Horndal", primary: false, notifications: true)
    let content = make([home, other], [home.key: schedule(tuesdayPickup), other.key: schedule(tuesdayPickup)])
    #expect(content.others[0].rowReminder == .scheduled("Påminnelse tisdag kl. 18:00"))
    #expect(content.others[0].rowReminder?.text == "Påminnelse tisdag kl. 18:00")
    // Raden har sitt läge, och huvudkortets text är bara huvudkortets.
    #expect(content.others[0].reminder == nil)
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
    // Huvudkortets reglage är av och säger att notiserna är avstängda.
    #expect(content.primary?.reminder?.isOn == false)
    #expect(content.primary?.reminder?.isDenied == true)
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

// MARK: Reglaget för påminnelsen på huvudkortet

@Test func reglagetArAvUtanPaminnelse() throws {
    let content = make([home], [home.key: schedule([event("2026-11-09", ["rest"])])])
    let reminder = try #require(content.primary?.reminder)
    #expect(reminder == HomeContent.PrimaryReminder(isOn: false, isDenied: false, title: "Påminn mig", detail: nil))
}

@Test func reglagetArPaMedTidenForPaminnelsenUnder() throws {
    var on = home
    on.notificationsOn = true
    let content = make([on], [on.key: schedule([event("2026-11-09", ["rest"])])])
    let reminder = try #require(content.primary?.reminder)
    #expect(reminder.isOn)
    #expect(!reminder.isDenied)
    #expect(reminder.title == "Påminn mig")
    #expect(reminder.detail == "Söndag kl. 18:00")
}

@Test func nekadeNotiserGerAvstangtReglageOchText() throws {
    var on = home
    on.notificationsOn = true
    let schedules = [on.key: schedule([event("2026-11-09", ["rest"])])]
    let denied = HomeContent.make(addresses: [on], schedules: schedules, settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    #expect(try #require(denied.primary?.reminder) == HomeContent.PrimaryReminder(isOn: false, isDenied: true, title: "Notiser är avstängda i iOS", detail: nil, showsDeniedNotice: true))
    // Också när valet inte är på vet modellen att iOS nekar, men kortet visar då ingen ruta.
    let off = HomeContent.make(addresses: [home], schedules: [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    #expect(try #require(off.primary?.reminder).isDenied)
}

@Test func ejFragadeNotiserVisasSomAvUtanNekat() throws {
    var on = home
    on.notificationsOn = true
    let content = HomeContent.make(addresses: [on], schedules: [on.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, remindersAllowed: false)
    let reminder = try #require(content.primary?.reminder)
    #expect(!reminder.isOn)
    #expect(!reminder.isDenied)
    #expect(reminder.title == "Påminn mig")
}

@Test func liveActivityVisasIUndertexten() throws {
    let start = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 17 * 60 + 30)
    let content = HomeContent.make(addresses: [home], schedules: [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: start))
    let reminder = try #require(content.primary?.reminder)
    #expect(!reminder.isOn)
    #expect(reminder.detail == "Live Activity söndag kl. 17:30")
}

@Test func passeradPaminnelseVisasIUndertexten() throws {
    var on = home
    on.notificationsOn = true
    let missed = "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
    let content = HomeContent.make(addresses: [on], schedules: [on.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, missedReminder: missed)
    #expect(try #require(content.primary?.reminder).detail == missed)
}

@Test func raderOchKortUtanHamtningHarInteReglaget() throws {
    let content = make([home, cabin], [
        home.key: schedule([event("2026-11-02", ["rest"])]),
        cabin.key: schedule([event("2026-11-18", ["plast"])]),
    ])
    #expect(try #require(content.primary).reminder == nil)
    #expect(content.others[0].reminder == nil)
}

@Test func reglagetUppreparInteAttPaminnelserArPa() throws {
    // Tömning i dag och ingen senare: reglaget säger redan att påminnelsen är på, så ingen undertext.
    var on = home
    on.notificationsOn = true
    let reminder = try #require(make([on], [on.key: schedule([event("2026-11-06", ["rest"])])]).primary?.reminder)
    #expect(reminder.isOn)
    #expect(reminder.title == "Påminn mig")
    #expect(reminder.detail == nil)
}

// MARK: Schemat slutar

private func endingSchedule(until: String?, events: [PickupEvent] = [event("2026-11-09", ["rest"])], lastError: APIError? = nil) -> CachedSchedule {
    var cached = schedule(events, lastError: lastError)
    let base = cached.response!
    cached.response = AddressResponse(today: base.today, address: base.address, next: [], summary: "", events: events, bins: [], fractions: base.fractions, links: base.links, updatedAt: base.updatedAt, schedule: until.map { SchedulePeriod(until: DayDate($0)!, reason: "Orsak.") })
    return cached
}

private func endingHome(_ cached: CachedSchedule?) -> HomeContent {
    let address = SavedAddress.fixture(key: AddressKey(source: "x", id: "a"), isPrimary: true)
    return HomeContent.make(addresses: [address], schedules: cached.map { [address.key: $0] } ?? [:], settings: ReminderSettings(), now: now)
}

@Test func hemkortetVisarNarSchematSlutarInomFjortonDagar() {
    // Fredag 6 november: 20 november är 14 dagar kvar, 21 november 15.
    #expect(endingHome(endingSchedule(until: "2026-11-20")).primary?.scheduleEnding?.shortText == "Schemat slutar 20 nov")
    #expect(endingHome(endingSchedule(until: "2026-11-21")).primary?.scheduleEnding == nil)
    #expect(endingHome(endingSchedule(until: "2026-11-06")).primary?.scheduleEnding?.daysLeft == 0)
    #expect(endingHome(endingSchedule(until: "2026-11-05")).primary?.scheduleEnding == nil)
}

@Test func hemkortetVisarInteRadenForLivekallorEllerUtanSchema() {
    #expect(endingHome(endingSchedule(until: nil)).primary?.scheduleEnding == nil)
    #expect(endingHome(nil).primary?.scheduleEnding == nil)
}

@Test func hemkortetVisarInteRadenUtanKommandeHamtningar() {
    #expect(endingHome(endingSchedule(until: "2026-11-10", events: [event("2026-11-01", ["rest"])])).primary?.scheduleEnding == nil)
}

@Test func hemkortetVisarRadenOckssaMedEttSparatSchemaEfterFel() {
    #expect(endingHome(endingSchedule(until: "2026-11-20", lastError: .sourceUnavailable)).primary?.scheduleEnding != nil)
}

@Test func radenUnderFlerAdresserHarIngenSchemaslutarOchVoiceOverLaserDenInte() {
    let other = SavedAddress.fixture(key: AddressKey(source: "x", id: "b"), isPrimary: false)
    let primary = SavedAddress.fixture(key: AddressKey(source: "x", id: "a"), isPrimary: true)
    let ending = endingSchedule(until: "2026-11-20")
    let content = HomeContent.make(addresses: [primary, other], schedules: [primary.key: ending, other.key: ending], settings: ReminderSettings(), now: now)
    #expect(content.primary?.scheduleEnding != nil)
    #expect(content.primary?.accessibilityLabel.contains("Schemat slutar") == true)
    #expect(content.others[0].scheduleEnding == nil)
    #expect(content.others[0].accessibilityLabel.contains("Schemat slutar") == false)
}

// MARK: Hushåll

private let sunday = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 12 * 60)
private let kim = HouseholdParticipant(id: "kim", name: "Kim", isOwner: true)

private func household(addresses: [SavedAddress] = [home], marks: [HouseholdMark] = [], status: HouseholdStatus = .synced) -> HouseholdState {
    HouseholdState(role: .member, myId: "jag", participants: [kim], addresses: addresses.map { HouseholdAddress(address: $0, addedBy: "kim") }, marks: marks, status: status)
}

private func householdMark(pending: Bool = false) -> HouseholdMark {
    // 18:42 UTC är 19:42 i Stockholm i november.
    let at = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60 + 42)
    return HouseholdMark(placedOut: PlacedOut(key: home.key, date: monday), by: "kim", at: at, isPending: pending)
}

private func householdLine(_ state: HouseholdState, at time: Date = sunday) -> HouseholdLine? {
    let content = HomeContent.make(addresses: [home], schedules: [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: time, household: state)
    return content.primary?.household
}

@Test func utanHushallIngenRad() {
    #expect(householdLine(.empty) == nil)
}

@Test func deladAdressDagenForeVisarKnappen() throws {
    let line = try #require(householdLine(household()))
    #expect(line.isShared)
    #expect(line.showsButton)
    #expect(line.placedOutText == nil)
    #expect(line.statusText == nil)
}

@Test func bockadVisarTextenInteKnappen() throws {
    let line = try #require(householdLine(household(marks: [householdMark()])))
    #expect(!line.showsButton)
    #expect(line.placedOutText == "Utställt av Kim, kl. 19:42")
    #expect(!line.isPending)
}

@Test func vantandeBockHarKlocka() throws {
    let line = try #require(householdLine(household(marks: [householdMark(pending: true)])))
    #expect(line.isPending)
}

@Test func delningenSynsInteForEnAdressSomInteDelas() throws {
    let line = try #require(householdLine(household(addresses: [cabin])))
    #expect(!line.isShared)
    #expect(!line.showsButton)
}

@Test func knappenSaknasLangtForeTomningen() throws {
    let line = try #require(householdLine(household()))
    #expect(line.showsButton)
    let early = try #require(householdLine(household(), at: now))
    #expect(!early.showsButton)
}

@Test func statusTextenFolerHushallets() throws {
    let line = try #require(householdLine(household(status: .notSignedIn)))
    #expect(line.statusText == "Synkar inte just nu")
}

private func lineFor(_ cached: CachedSchedule?, _ state: HouseholdState) -> HouseholdLine? {
    HomeContent.make(addresses: [home], schedules: cached.map { [home.key: $0] } ?? [:], settings: ReminderSettings(), now: sunday, household: state).primary?.household
}

@Test func hushallsradenFinnsUtanKommandeTomning() throws {
    let state = household(status: .notSignedIn)
    for cached in [schedule([]), CachedSchedule(response: nil, fetchedAt: nil, lastAttemptAt: now, lastError: .network), nil] {
        let line = try #require(lineFor(cached, state))
        #expect(line.isShared)
        #expect(line.statusText == "Synkar inte just nu")
        #expect(!line.showsButton)
    }
}

@Test func hushallsradenFinnsMedFelDaRollenSaknasMenAdresserFinns() throws {
    var state = household(status: .notSignedIn)
    state.role = .none
    let line = try #require(lineFor(schedule([event("2026-11-09", ["rest"])]), state))
    #expect(line.isShared)
    #expect(line.statusText == "Synkar inte just nu")
    var empty = HouseholdState.empty
    empty.status = .notSignedIn
    #expect(lineFor(schedule([event("2026-11-09", ["rest"])]), empty) == nil)
}

@Test func ingaKommandeHamtningarArNeutral() throws {
    let none = try #require(make([home], [home.key: schedule([event("2026-11-02", ["rest"])])], settings: ReminderSettings()).primary)
    #expect(none.summaryTone == .neutral)
    let upcoming = try #require(make([home], [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings()).primary)
    #expect(upcoming.summaryTone == .date)
    let loading = try #require(make([home], [:]).primary)
    #expect(loading.summaryTone == .neutral)
    let failed = try #require(make([home], [home.key: CachedSchedule(response: nil, fetchedAt: nil, lastAttemptAt: now, lastError: .network)]).primary)
    #expect(failed.summaryTone == .warning)
}

// MARK: Påminnelsen i huvudkortets fot

@Test func paminnelsenArEnRadIKortetsFot() throws {
    var on = home
    on.notificationsOn = true
    let reminder = try #require(make([on], [on.key: schedule([event("2026-11-09", ["rest"])])]).primary?.reminder)
    #expect(reminder.line == "Påminnelse söndag kl. 18:00")
    #expect(!reminder.showsDeniedNotice)
}

@Test func avstangdPaminnelseGerIngenRadIFoten() throws {
    let reminder = try #require(make([home], [home.key: schedule([event("2026-11-09", ["rest"])])]).primary?.reminder)
    #expect(reminder.line == nil)
    #expect(!reminder.showsDeniedNotice)
}

@Test func liveActivityArEnRadIFotenAvenMedNotisenAv() throws {
    let start = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 17 * 60 + 30)
    let content = HomeContent.make(addresses: [home], schedules: [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(liveActivityOn: true), now: now, liveActivity: activity(pending: true, start: start))
    #expect(try #require(content.primary?.reminder).line == "Live Activity söndag kl. 17:30")
}

@Test func rutanOmNekadeNotiserVisasBaraNarPaminnelsenArPa() throws {
    var on = home
    on.notificationsOn = true
    let denied = HomeContent.make(addresses: [on], schedules: [on.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    let wanted = try #require(denied.primary?.reminder)
    #expect(wanted.showsDeniedNotice)
    #expect(wanted.line == nil)
    // Påminnelsen är av: inget har slutat fungera, så ingen ruta och ingen rad.
    let off = HomeContent.make(addresses: [home], schedules: [home.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, remindersAllowed: false, remindersDenied: true)
    let notWanted = try #require(off.primary?.reminder)
    #expect(!notWanted.showsDeniedNotice)
    #expect(notWanted.line == nil)
}

@Test func ejFragadeNotiserGerIngenRadOchIngenRuta() throws {
    var on = home
    on.notificationsOn = true
    let content = HomeContent.make(addresses: [on], schedules: [on.key: schedule([event("2026-11-09", ["rest"])])], settings: ReminderSettings(), now: now, remindersAllowed: false)
    let reminder = try #require(content.primary?.reminder)
    #expect(reminder.line == nil)
    #expect(!reminder.showsDeniedNotice)
}

// MARK: Adress och plats på en rad

@Test func adressOchPlatsStarPaEnRad() {
    #expect(HomeContent.AddressLines(address: "Storgatan\u{00A0}12", place: "Krylbo\u{00A0}· Avesta kommun").singleLine == "Storgatan\u{00A0}12, Krylbo\u{00A0}· Avesta kommun")
    #expect(HomeContent.AddressLines(address: "Kaplansgården, Jularbo m.fl.", place: "Avesta kommun").singleLine == "Kaplansgården, Jularbo m.fl., Avesta kommun")
    // Utan gata står bara platsen, och utan plats bara gatan.
    #expect(HomeContent.AddressLines(address: "", place: "Uppsala").singleLine == "Uppsala")
    #expect(HomeContent.AddressLines(address: "Testgatan 1", place: "").singleLine == "Testgatan 1")
}

@Test func listradenVisarUtstalltForEnAnnanAdress() throws {
    let mark = HouseholdMark(placedOut: PlacedOut(key: cabin.key, date: monday), by: "kim", at: StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60 + 42), isPending: false)
    let state = household(addresses: [home, cabin], marks: [mark])
    let content = HomeContent.make(
        addresses: [home, cabin],
        schedules: [home.key: schedule([event("2026-11-10", ["rest"])]), cabin.key: schedule([event("2026-11-09", ["rest"])])],
        settings: ReminderSettings(), now: sunday, household: state
    )
    let row = try #require(content.others.first { $0.key == cabin.key }?.household)
    #expect(row.placedOutText == "Utställt av Kim, kl. 19:42")
    #expect(row.placedOutTitle == "Utställt")
    #expect(row.placedOutSubtitle == "av Kim · kl. 19:42")
}

@Test func huvudadressMedNotiserFarKnappenStallUtPaTomningsdagen() throws {
    let on = saved("hemma", name: "Hemma", street: "Storgatan 3", locality: "Avesta", primary: true, notifications: true)
    let primary = try #require(make([on], [on.key: schedule([event("2026-11-06", ["rest"])])]).primary)
    #expect(primary.household?.showsButton == true)
}

@Test func huvudadressMedLiveActivityFarKnappenStallUt() throws {
    let off = saved("hemma", name: "Hemma", street: "Storgatan 3", locality: "Avesta", primary: true)
    let primary = try #require(make([off], [off.key: schedule([event("2026-11-07", ["rest"])])], settings: ReminderSettings(liveActivityOn: true)).primary)
    #expect(primary.household?.showsButton == true)
}

@Test func utanPaminnelserFarHuvudadressenIngenKnapp() throws {
    let off = saved("hemma", name: "Hemma", street: "Storgatan 3", locality: "Avesta", primary: true)
    let primary = try #require(make([off], [off.key: schedule([event("2026-11-06", ["rest"])])]).primary)
    #expect(primary.household == nil)
}

@Test func radUtanNotiserFarIngenKnappFastLiveActivityArPa() throws {
    let main = saved("hemma", name: "Hemma", street: "Storgatan 3", locality: "Avesta", primary: true)
    let other = saved("jobbet", name: "Jobbet", street: "Torget 1", locality: "Avesta", primary: false)
    let content = make([main, other], [main.key: schedule([event("2026-11-06", ["rest"])]), other.key: schedule([event("2026-11-06", ["rest"])])], settings: ReminderSettings(liveActivityOn: true))
    #expect(content.others.first?.household == nil)
}

// MARK: Utställda tömningar hoppas över i påminnelsetexten

private let sundayEvening = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)

private func footLine(placedOut: Set<PlacedOut> = [], silenced: Set<PlacedOut> = []) throws -> String? {
    var on = home
    on.notificationsOn = true
    let events = [event("2026-11-09", ["rest"]), event("2026-11-11", ["rest"])]
    let content = HomeContent.make(addresses: [on], schedules: [on.key: schedule(events)], settings: ReminderSettings(morningOn: true), now: sundayEvening, ownPlacedOut: placedOut, silencedPickups: silenced)
    return try #require(content.primary?.reminder).line
}

@Test func morgonpaminnelsenLovasInteNarTomningenArUtstalld() throws {
    // Kvällens tid har passerat. Utan bock är morgonen nästa.
    #expect(try footLine() == "Påminnelse måndag kl. 06:00")
    // Utställt tar bort morgonens notis, så raden går vidare till nästa tömning och dess båda tider.
    let mark = PlacedOut(key: home.key, date: monday)
    #expect(try footLine(placedOut: [mark]) == "Påminnelse tisdag kl. 18:00 och onsdag kl. 06:00")
}

@Test func hushallsbockenTystarMorgonpaminnelsenIFoten() throws {
    let mark = PlacedOut(key: home.key, date: monday)
    #expect(try footLine(silenced: [mark]) == "Påminnelse tisdag kl. 18:00 och onsdag kl. 06:00")
    // En bock för en annan adress påverkar inte.
    #expect(try footLine(silenced: [PlacedOut(key: cabin.key, date: monday)]) == "Påminnelse måndag kl. 06:00")
}
