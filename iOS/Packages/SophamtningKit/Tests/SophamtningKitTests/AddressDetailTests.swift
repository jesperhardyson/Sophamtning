import Testing
import Foundation
import SophamtningKit

private func fixture(_ name: String) throws -> AddressResponse {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

private let key = AddressKey(source: "uppsala", id: "a")
private let address = SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/x")!, street: "Storgatan 2", locality: "Uppsala", kommun: "Uppsala kommun", detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
private let today = DayDate("2026-11-06")!
private let noon = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

private func detail(_ schedule: CachedSchedule?, now: Date = noon, source: String? = "Uppsala Vatten", address: SavedAddress = address) -> AddressDetail {
    AddressDetail.make(address: address, schedule: schedule, settings: ReminderSettings(), sourceName: source, now: now)
}

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false, deviation: Deviation? = nil, warning: String? = nil) -> PickupEvent {
    PickupEvent(date: DayDate(iso)!, fractions: fractions, estimated: estimated, deviation: deviation, warning: warning, labels: [:])
}

private func schedule(_ events: [PickupEvent], fractions: [String: FractionInfo]? = nil, fetchedAt: Date? = nil, error: APIError? = nil) throws -> CachedSchedule {
    let base = try fixture("adress")
    let response = AddressResponse(today: base.today, address: base.address, next: [], summary: "", events: events, bins: [], fractions: fractions ?? base.fractions, links: base.links, updatedAt: base.updatedAt)
    return CachedSchedule(response: response, fetchedAt: fetchedAt ?? noon, lastAttemptAt: noon, lastError: error)
}

@Test func sparatSchemaVisasMedNastaOchKarl() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest", "mat"]), event("2026-11-12", ["papper"], estimated: true)]))
    #expect(result.mode == .schedule)
    #expect(result.notice == nil)
    #expect(result.next?.date == DayDate("2026-11-09"))
    #expect(result.bins.map(\.id) == ["mat", "rest", "papper"])
    #expect(result.bins.first(where: { $0.id == "rest" })?.dateText == "Mån 9 nov")
    #expect(result.bins.first(where: { $0.id == "rest" })?.daysText == "om 3 dagar")
    #expect(result.bins.first(where: { $0.id == "papper" })?.dateText == "ca tors 12 nov")
    #expect(result.rows.map(\.dateText) == ["Mån 9 nov", "ca tors 12 nov"])
    #expect(result.title == "Hemma")
    #expect(result.webLink != nil)
}

@Test func fleraFraktionerSammaDagBlirEnRadMedAllaChips() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-09", ["mat", "rest"], warning: "Helgdag")]))
    #expect(result.rows.count == 1)
    #expect(result.rows[0].fractions.map(\.id) == ["rest", "mat"])
    #expect(result.rows[0].warning == "Helgdag")
    #expect(result.nextWarning == "Helgdag")
}

@Test func avvikelseVisasSomFlyttadFranEllerOrsak() throws {
    let result = detail(try schedule([
        event("2026-11-17", ["rest"], deviation: Deviation(originalDate: DayDate("2026-11-16"), reason: "Helg")),
        event("2026-11-18", ["mat"], deviation: Deviation(originalDate: nil, reason: "Julhelgen")),
        event("2026-11-19", ["glas"], deviation: Deviation(originalDate: nil, reason: "  ")),
    ]))
    #expect(result.rows.map(\.deviation) == ["Flyttad från mån 16 nov", "Julhelgen", nil])
}

@Test func tomVarningVisasInte() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest"], warning: "  ")]))
    #expect(result.rows[0].warning == nil)
    #expect(result.nextWarning == nil)
}

@Test func passeradeDatumVisasInteIDetKommandeSchemat() throws {
    let result = detail(try schedule([event("2026-11-05", ["rest"]), event("2026-11-06", ["mat"])]))
    #expect(result.rows.map(\.date.iso) == ["2026-11-06"])
}

@Test func tomtSchemaGerIngaKommandeHamtningarMedLank() throws {
    let result = detail(try schedule([event("2026-10-01", ["rest"])]))
    #expect(result.mode == .noUpcoming)
    #expect(result.next == nil)
    #expect(result.rows.isEmpty)
    #expect(result.webLink != nil)
}

@Test func okandFraktionIAdressvynFaarIdSomNamn() throws {
    let result = detail(try schedule([event("2026-11-24", ["tradgard"])], fractions: [:]))
    #expect(result.rows[0].fractions[0].info.name == "tradgard")
    #expect(result.bins[0].info.name == "tradgard")
}

@Test func tekniskaFelUtanSchemaSagerInteAttAdressenSaknas() {
    for error in [APIError.sourceUnavailable, .network, .unexpected(500)] {
        let result = detail(CachedSchedule(lastAttemptAt: noon, lastError: error))
        #expect(result.mode == .unavailable)
        #expect(result.notice == .sourceUnavailable)
    }
}

@Test func fyrahundrafyraPaSparadAdressSagerAttAdressenInteHittas() {
    let result = detail(CachedSchedule(lastAttemptAt: noon, lastError: .notFound))
    #expect(result.mode == .unavailable)
    #expect(result.notice == .notFound)
}

@Test func fyrahundrafyraMedSparatSchemaBehallerSchemat() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest"])], error: .notFound))
    #expect(result.mode == .schedule)
    #expect(result.notice == .notFound)
}

@Test func missLyckadUppdateringVisarSparatSchemaOchNarDetHamtades() throws {
    let yesterday = StockholmClock.date(on: DayDate("2026-11-05")!, minutes: 18 * 60 + 40)
    let result = detail(try schedule([event("2026-11-09", ["rest"])], fetchedAt: yesterday, error: .sourceUnavailable))
    #expect(result.mode == .schedule)
    #expect(result.notice == .savedShown(fetched: "Hämtat i går 18:40 från Uppsala Vatten."))
}

@Test func hamtadTextFoljerSvenskTidOchDag() throws {
    let morning = StockholmClock.date(on: today, minutes: 9 * 60 + 12)
    #expect(detail(try schedule([], fetchedAt: morning)).fetchedText == "Hämtat i dag 09:12 från Uppsala Vatten.")
    let old = StockholmClock.date(on: DayDate("2026-11-01")!, minutes: 7 * 60)
    #expect(detail(try schedule([], fetchedAt: old), source: nil).fetchedText == "Hämtat 1 nov 07:00.")
}

@Test func schemaSomInteHamtatsAnnuVisarLaddning() {
    let result = detail(nil)
    #expect(result.mode == .loading)
    #expect(result.notice == nil)
    #expect(result.fetchedText == nil)
}

@Test func notistextenAngerKvallenForeOchTomningensDag() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest"])]))
    #expect(result.reminderText == "Söndag kl. 18:00 inför måndagens tömning.")
}

@Test func notistextenHopparOverKvallarSomPasserat() throws {
    // Söndag 8 nov 19:00: kvällen före måndag har passerat.
    let late = StockholmClock.date(on: DayDate("2026-11-08")!, minutes: 19 * 60)
    let result = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["glas"])]), now: late)
    #expect(result.reminderText == "Onsdag kl. 18:00 inför torsdagens tömning.")
}

@Test func tiderVisasMedValdTid() {
    let result = AddressDetail.make(address: address, schedule: nil, settings: ReminderSettings(reminderMinutes: 20 * 60 + 15), sourceName: nil, now: noon)
    #expect(result.reminderText == "Kvällen före varje tömning kl. 20:15.")
    #expect(result.liveActivityText == "Visas på låsskärmen från kl. 20:15 kvällen före. Starten aviseras med ljud, och den försvinner senast efter 12 timmar. Öppna appen ibland, så att nästa tömning kommer med. Med notiser på får du också en reserv om du inte bekräftar.")
}

@Test func fyrahundraArVarkenNatfelEllerSaknadAdressOchHarEgenText() throws {
    let none = detail(CachedSchedule(lastAttemptAt: noon, lastError: .badRequest))
    #expect(none.mode == .unavailable)
    #expect(none.notice == .badRequest)
    let saved = detail(try schedule([event("2026-11-09", ["rest"])], error: .badRequest))
    #expect(saved.mode == .schedule)
    #expect(saved.notice == .badRequest)
}

@Test func sparfelSkiljsFranKallfel() throws {
    #expect(detail(CachedSchedule(lastAttemptAt: noon, lastError: .unexpected(0))).notice == .storageFailed)
    #expect(detail(CachedSchedule(lastAttemptAt: noon, lastError: .unexpected(503))).notice == .sourceUnavailable)
}

@Test func missadPaminnelseKravsMorgondagensTomningOchPasseradTid() throws {
    let tomorrow = try schedule([event("2026-11-07", ["rest"])])
    let late = StockholmClock.date(on: today, minutes: 18 * 60 + 1)
    let early = StockholmClock.date(on: today, minutes: 17 * 60 + 59)
    let text = "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
    func make(_ now: Date, on: Bool = true, schedule: CachedSchedule) -> AddressDetail {
        AddressDetail.make(address: address, schedule: schedule, settings: ReminderSettings(), sourceName: nil, now: now, remindersOn: on)
    }
    #expect(make(late, schedule: tomorrow).missedReminder == text)
    #expect(make(early, schedule: tomorrow).missedReminder == nil)
    #expect(make(late, on: false, schedule: tomorrow).missedReminder == nil)
    // Tömning först i övermorgon har ingen missad kväll.
    #expect(make(late, schedule: try schedule([event("2026-11-08", ["rest"])])).missedReminder == nil)
    // Exakt påminnelsetid räknas som passerad, eftersom planeraren inte schemalägger det.
    #expect(make(StockholmClock.date(on: today, minutes: 18 * 60), schedule: tomorrow).missedReminder == text)
}

// MARK: Ordningen i adressvyn

@Test func kommandeVisarDeTreNarmasteDatumenOchLankForFler() throws {
    let events = [
        event("2026-11-09", ["rest", "mat"]),
        event("2026-11-12", ["papper"], estimated: true),
        event("2026-11-16", ["plast"]),
        event("2026-11-23", ["glas"]),
    ]
    let result = detail(try schedule(events))
    #expect(result.upcoming.map(\.date.iso) == ["2026-11-09", "2026-11-12", "2026-11-16"])
    #expect(result.hasFullSchedule)
    // Hela schemat har alla datum, i samma format.
    #expect(result.rows.map(\.date.iso) == ["2026-11-09", "2026-11-12", "2026-11-16", "2026-11-23"])
}

@Test func utanFlerAnTreDatumFinnsIngenLank() throws {
    let three = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["mat"]), event("2026-11-16", ["plast"])]))
    #expect(three.upcoming.count == 3)
    #expect(!three.hasFullSchedule)
    let one = detail(try schedule([event("2026-11-09", ["rest"])]))
    #expect(one.upcoming.count == 1)
    #expect(!one.hasFullSchedule)
    let none = detail(try schedule([]))
    #expect(none.upcoming.isEmpty)
    #expect(!none.hasFullSchedule)
}

@Test func forstaRadenKanVaraSammaDagSomNastaTomning() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest", "mat"]), event("2026-11-12", ["papper"])]))
    #expect(result.next?.date == result.upcoming.first?.date)
    #expect(result.upcoming.first?.fractions.map(\.id) == ["rest", "mat"])
}

@Test func radenHarDatumbrickaOchDagarKvarRaknatFranIDag() throws {
    let result = detail(try schedule([
        event("2026-11-06", ["rest"]),
        event("2026-11-07", ["mat"]),
        event("2026-11-11", ["plast"]),
        event("2026-12-02", ["glas"], estimated: true),
    ]))
    #expect(result.rows.map(\.dayNumber) == ["6", "7", "11", "2"])
    #expect(result.rows.map(\.month) == ["NOV", "NOV", "NOV", "DEC"])
    #expect(result.rows.map(\.daysText) == ["i dag", "i morgon", "om 5 dagar", "ca om 26 dagar"])
}

@Test func dagarKvarRaknasFranDatumetOchInteFranSparadeFalt() throws {
    // Ett schema som hämtades för en vecka sedan: dagarna räknas från i dag, inte från när det hämtades.
    let old = StockholmClock.date(on: DayDate("2026-10-30")!, minutes: 8 * 60)
    let result = detail(try schedule([event("2026-11-09", ["rest"])], fetchedAt: old))
    #expect(result.upcoming.first?.daysText == "om 3 dagar")
    #expect(result.bins.first?.daysText == "om 3 dagar")
}

@Test func voiceOverLaserRadenMedDagarKvar() throws {
    let result = detail(try schedule([event("2026-11-12", ["rest", "mat"], estimated: true, warning: "Helgdag")]))
    #expect(result.rows[0].accessibilityLabel == "ca tors 12 nov, ca om 6 dagar. Restavfall, Matavfall. Helgdag")
}

@Test func voiceOverLaserNastaTomningMedDatumDagarOchKarl() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest", "mat"])]))
    #expect(result.next?.accessibilityLabel == "Nästa tömning. Om 3 dagar. Måndag 9 november. Restavfall, Matavfall")
    let estimated = detail(try schedule([event("2026-11-09", ["rest"], estimated: true)]))
    #expect(estimated.next?.accessibilityLabel == "Nästa tömning. Ca om 3 dagar. Ca måndag 9 november. Restavfall")
}

@Test func voiceOverLaserKarletsKort() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["papper"], estimated: true)]))
    #expect(result.bins.map(\.accessibilityLabel) == ["Restavfall, om 3 dagar, Mån 9 nov", "Pappersförpackningar, om 6 dagar, ca tors 12 nov"])
}

@Test func radensKortaDagarKvarHarCaOchLasesHeltAvVoiceOver() throws {
    let result = detail(try schedule([
        event("2026-11-06", ["rest"]),
        event("2026-11-07", ["mat"]),
        event("2026-11-11", ["plast"]),
        event("2026-12-02", ["glas"], estimated: true),
    ]))
    #expect(result.rows.map(\.shortDaysText) == ["i dag", "i morgon", "om 5 d", "ca om 26 d"])
}
