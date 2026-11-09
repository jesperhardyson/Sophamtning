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
    // Källans namn står i kortet ovanför, så raden har bara tiden.
    #expect(detail(try schedule([], fetchedAt: morning)).fetchedText == "Hämtat i dag 09:12")
    let old = StockholmClock.date(on: DayDate("2026-11-01")!, minutes: 7 * 60)
    #expect(detail(try schedule([], fetchedAt: old), source: nil).fetchedText == "Hämtat 1 nov 07:00")
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
    // Nästa tömning (9 nov) står i kortet ovanför, så Kommande börjar efter den.
    #expect(result.upcoming.map(\.date.iso) == ["2026-11-12", "2026-11-16", "2026-11-23"])
    #expect(!result.hasFullSchedule, "Alla datum står redan på sidan")
    // Hela schemat har alla datum, i samma format.
    #expect(result.rows.map(\.date.iso) == ["2026-11-09", "2026-11-12", "2026-11-16", "2026-11-23"])
}

@Test func helaSchematVisasNarFlerAnKommandeFinns() throws {
    let five = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["mat"]), event("2026-11-16", ["plast"]), event("2026-11-23", ["glas"]), event("2026-11-30", ["rest"])]))
    #expect(five.upcoming.count == 3)
    #expect(five.hasFullSchedule)
    let four = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["mat"]), event("2026-11-16", ["plast"]), event("2026-11-23", ["glas"])]))
    #expect(four.upcoming.count == 3)
    #expect(!four.hasFullSchedule)
}

@Test func utanFlerAnNastaTomningArKommandeTom() throws {
    let one = detail(try schedule([event("2026-11-09", ["rest"])]))
    #expect(one.upcoming.isEmpty)
    #expect(!one.hasFullSchedule)
    let none = detail(try schedule([]))
    #expect(none.upcoming.isEmpty)
    #expect(!none.hasFullSchedule)
}

@Test func kommandeBorjarEfterNastaTomning() throws {
    let result = detail(try schedule([event("2026-11-09", ["rest", "mat"]), event("2026-11-11", ["papper"]), event("2026-11-12", ["glas"]), event("2026-11-16", ["plast"])]))
    #expect(result.next?.date == DayDate("2026-11-09"))
    #expect(result.upcoming.map(\.date.iso) == ["2026-11-11", "2026-11-12", "2026-11-16"])
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
    // Ett schema som hämtades för en vecka sedan, med sparade fält som säger något annat: dagarna räknas från i dag och datumet.
    let old = StockholmClock.date(on: DayDate("2026-10-30")!, minutes: 8 * 60)
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    json["next"] = [[
        "fraction": "rest", "name": "Restavfall", "color": "#555555", "date": "2026-11-09",
        "daysUntil": 10, "isToday": true, "isTomorrow": true, "estimated": false, "warning": NSNull(),
        "text": "Restavfall – i dag, fredag 30 oktober",
    ]]
    json["summary"] = "Restavfall i dag"
    json["events"] = [["date": "2026-11-09", "fractions": ["rest"], "estimated": false, "deviation": NSNull(), "warning": NSNull(), "labels": [String: String]()]]
    let response = try JSONDecoder().decode(AddressResponse.self, from: JSONSerialization.data(withJSONObject: json))
    let result = detail(CachedSchedule(response: response, fetchedAt: old, lastAttemptAt: old, lastError: nil))
    #expect(result.next?.headline == "Om 3 dagar")
    #expect(result.next?.longDate == "Måndag 9 november")
    #expect(result.rows.first?.daysText == "om 3 dagar")
    #expect(result.rows.first?.shortDaysText == "om 3\u{00A0}d", "Talet och d hålls ihop med hårt mellanslag")
    #expect(result.bins.first?.daysText == "om 3 dagar")
}

@Test func varningenForNastaTomningVisasBaraIRutan() throws {
    let result = detail(try schedule([
        event("2026-11-09", ["rest"], deviation: Deviation(originalDate: DayDate("2026-11-08"), reason: "Helg"), warning: "Helgdag"),
        event("2026-11-12", ["mat"], warning: "Ställ ut tidigt"),
    ]))
    #expect(result.nextWarning == "Helgdag")
    // Kommande har bara datumen efter nästa tömning, med sina egna varningar.
    #expect(result.upcoming.map(\.date.iso) == ["2026-11-12"])
    #expect(result.upcoming.map(\.warning) == ["Ställ ut tidigt"])
    // Hela schemat visar alla varningar.
    #expect(result.rows.map(\.warning) == ["Helgdag", "Ställ ut tidigt"])
}

@Test func nastaTomningsAvvikelseStarIKortet() throws {
    let result = detail(try schedule([
        event("2026-11-09", ["rest"], deviation: Deviation(originalDate: DayDate("2026-11-08"), reason: "Helg"), warning: "Helgdag"),
        event("2026-11-12", ["mat"]),
    ]))
    #expect(result.nextDeviation == "Flyttad från sön 8 nov")
    let plain = detail(try schedule([event("2026-11-09", ["rest"]), event("2026-11-12", ["mat"])]))
    #expect(plain.nextDeviation == nil)
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
    #expect(result.rows.map(\.shortDaysText) == ["i dag", "i morgon", "om 5\u{00A0}d", "ca om 26\u{00A0}d"])
}

// MARK: Hur långt schemat gäller

private func periodSchedule(_ events: [PickupEvent], until: String?, reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget.") throws -> CachedSchedule {
    let base = try fixture("adress")
    let period = until.map { SchedulePeriod(until: DayDate($0)!, reason: reason) }
    let response = AddressResponse(today: base.today, address: base.address, next: [], summary: "", events: events, bins: [], fractions: base.fractions, links: base.links, updatedAt: base.updatedAt, schedule: period)
    return CachedSchedule(response: response, fetchedAt: noon, lastAttemptAt: noon, lastError: nil)
}

@Test func schemaperiodenAvkodasFranAvesta() throws {
    let response = try fixture("adress-avesta")
    #expect(response.schedule == SchedulePeriod(until: DayDate("2027-01-10")!, reason: "Avesta Vatten publicerar hämtschemat ett år i taget."))
    let again = try JSONDecoder().decode(AddressResponse.self, from: JSONEncoder().encode(response))
    #expect(again == response)
}

@Test func schemaperiodenSaknasNullEllerTrasig() throws {
    // Äldre svar och sparade scheman saknar fältet.
    #expect(try fixture("adress").schedule == nil)
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("adress-avesta")) as? [String: Any])
    for broken: Any in [NSNull(), "2027-01-10", ["until": "10 jan"], ["reason": "Utan datum"]] {
        json["schedule"] = broken
        let response = try JSONDecoder().decode(AddressResponse.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(response.schedule == nil)
        #expect(!response.events.isEmpty)
    }
    json["schedule"] = ["until": "2027-01-10", "reason": NSNull()]
    let noReason = try JSONDecoder().decode(AddressResponse.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(noReason.schedule == SchedulePeriod(until: DayDate("2027-01-10")!, reason: nil))
}

@Test func radenOmPeriodenVisasMedOrsak() throws {
    let result = detail(try periodSchedule([event("2026-11-09", ["rest"])], until: "2027-01-10"))
    #expect(result.mode == .schedule)
    #expect(result.schedulePeriod == AddressDetail.SchedulePeriodLine(text: "Schemat gäller till 10 januari 2027.", reason: "Avesta Vatten publicerar hämtschemat ett år i taget."))
}

@Test func radenUtanOrsakOchForLivekallor() throws {
    let blank = detail(try periodSchedule([event("2026-11-09", ["rest"])], until: "2027-01-10", reason: "  "))
    #expect(blank.schedulePeriod == AddressDetail.SchedulePeriodLine(text: "Schemat gäller till 10 januari 2027.", reason: nil))
    // `null` gäller alla live-källor: ingen rad.
    let live = detail(try periodSchedule([event("2026-11-09", ["rest"])], until: nil))
    #expect(live.schedulePeriod == nil)
    #expect(live.noUpcomingMessage.message == "Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta Uppsala Vatten.")
    // Inget schema än: ingen rad.
    #expect(detail(nil).schedulePeriod == nil)
}

@Test func liveKallaUtanNamnHanvisarTillAnsvarig() throws {
    let live = detail(try periodSchedule([], until: nil), source: nil)
    #expect(live.noUpcomingMessage.message == "Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta den som ansvarar för hämtningen.")
}

@Test func liveKallaEfterFelSagerBaraVadSchematSager() throws {
    let failed = detail(try schedule([], error: .network), source: "Uppsala Vatten")
    #expect(failed.noUpcomingMessage.message == "Det senast hämtade schemat har inga fler hämtningar.")
}

@Test func passeradPeriodUtanHamtningarSagerAttNastaPeriodInteArPublicerad() throws {
    let result = detail(try periodSchedule([event("2026-11-01", ["rest"])], until: "2026-11-05"))
    #expect(result.mode == .noUpcoming)
    #expect(result.schedulePeriod == nil)
    #expect(result.noUpcomingMessage == AddressDetail.NoUpcomingMessage(
        title: "Inga kommande hämtningar",
        message: "Schemat gällde till 5 november 2026, och källan har inte publicerat nästa period än. Avesta Vatten publicerar hämtschemat ett år i taget."
    ))
    #expect(result.notice == nil)
    let noReason = detail(try periodSchedule([], until: "2026-11-05", reason: nil))
    #expect(noReason.noUpcomingMessage.message == "Schemat gällde till 5 november 2026, och källan har inte publicerat nästa period än.")
}

@Test func sparatSchemaEfterFelSagerInteAttKallanSaknarNastaPeriod() throws {
    // Hämtningen misslyckades och ett sparat schema med passerad period visas. Nästa period kan finnas hos källan utan
    // att ha kommit fram, så kortet säger bara vad det senast hämtade schemat säger.
    var failed = try periodSchedule([event("2026-11-01", ["rest"])], until: "2026-11-05")
    failed.lastError = .network
    let result = detail(failed)
    #expect(result.mode == .noUpcoming)
    #expect(result.notice == .savedShown(fetched: "Hämtat i dag 12:00 från Uppsala Vatten."))
    #expect(result.noUpcomingMessage == AddressDetail.NoUpcomingMessage(
        title: "Inga kommande hämtningar",
        message: "Det senast hämtade schemat gällde till 5 november 2026. Avesta Vatten publicerar hämtschemat ett år i taget."
    ))
    #expect(!result.noUpcomingMessage.message.contains("inte publicerat"))
    // Utan period, som för live-källor, inte heller att schemat har tagit slut hos kommunen.
    var live = try periodSchedule([], until: nil)
    live.lastError = .network
    #expect(detail(live).noUpcomingMessage.message == "Det senast hämtade schemat har inga fler hämtningar.")
    // En period som gäller fortfarande är densamma som utan fel.
    var current = try periodSchedule([], until: "2027-01-10", reason: nil)
    current.lastError = .network
    #expect(detail(current).noUpcomingMessage.message == "Inga fler hämtningar i schemat, som gäller till 10 januari 2027.")
}

@Test func helaSchematHarNamnetForstOchAdressvynUnderRubriken() throws {
    let area = SavedAddress(key: key, url: address.url, street: "Kaplansgården, Jularbo m.fl.", locality: "", kommun: "Avesta kommun", detail: nil, selection: "area", displayName: "Kaplansgården, Jularbo m.fl.", isPrimary: false, addedAt: address.addedAt)
    let result = detail(nil, address: area)
    // Adressvyn har namnet som rubrik, så bara platsen står under.
    #expect(result.lines == HomeContent.AddressLines(address: "", place: "Avesta kommun"))
    // Hela schemat har rubriken "Hela schemat", så namnet står först.
    #expect(result.namedLines == HomeContent.AddressLines(name: "Kaplansgården, Jularbo m.fl.", address: "", place: "Avesta kommun"))
    #expect(result.namedLines.accessibilityLabel == "Kaplansgården, Jularbo m.fl., Avesta kommun")
    // Huvudadressen med eget namn: namnet, gatan och platsen.
    #expect(detail(nil).namedLines.accessibilityLabel == "Hemma, Storgatan 2, Uppsala")
}

@Test func periodenGallerHelaSistaDagenISverige() throws {
    let schedule = try periodSchedule([event("2026-11-06", ["rest"])], until: "2026-11-06")
    // 23:30 svensk tid den sista dagen: perioden gäller fortfarande, och dagens hämtning visas.
    let late = detail(schedule, now: StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 23 * 60 + 30))
    #expect(late.mode == .schedule)
    #expect(late.schedulePeriod?.text == "Schemat gäller till 6 november 2026.")
    // 00:30 svensk tid dagen efter, som är kvällen före i New York: perioden har passerat.
    let after = detail(schedule, now: StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 30))
    #expect(after.mode == .noUpcoming)
    #expect(after.schedulePeriod == nil)
    #expect(after.noUpcomingMessage.message.hasPrefix("Schemat gällde till 6 november 2026"))
}

@Test func datumMedArUtanVeckodag() {
    #expect(SwedishFormat.dayMonthYear(DayDate("2027-01-10")!) == "10 januari 2027")
}

@Test func utanFlerHamtningarForeSlutetSagerKortetHurLangtSchematGaller() throws {
    // Sista hämtningen har passerat, men perioden gäller fortfarande: kortet och raden får inte motsäga varandra.
    let result = detail(try periodSchedule([event("2026-11-02", ["rest"])], until: "2027-01-10"))
    #expect(result.mode == .noUpcoming)
    #expect(result.noUpcomingMessage == AddressDetail.NoUpcomingMessage(
        title: "Inga kommande hämtningar",
        message: "Inga fler hämtningar i schemat, som gäller till 10 januari 2027. Avesta Vatten publicerar hämtschemat ett år i taget."
    ))
    // Perioden står i kortet, så den separata raden visas inte en gång till.
    #expect(result.schedulePeriod == nil)
    let noReason = detail(try periodSchedule([], until: "2027-01-10", reason: nil))
    #expect(noReason.noUpcomingMessage.message == "Inga fler hämtningar i schemat, som gäller till 10 januari 2027.")
}

@Test func passeradPeriodMedHamtningarEfterIDagVisarIngenRad() throws {
    // Källans data säger emot sig själv: hämtningar efter en period som har passerat. Schemat visas, men ingen rad.
    let result = detail(try periodSchedule([event("2026-11-09", ["rest"])], until: "2026-11-05"))
    #expect(result.mode == .schedule)
    #expect(result.next?.date == DayDate("2026-11-09"))
    #expect(result.schedulePeriod == nil)
}

// MARK: Schemat tar snart slut

/// Fredag 6 november 2026 är i dag, så `until` 14 dagar bort är 20 november.
private func ending(_ untilDaysFromToday: Int?, events: [PickupEvent] = [event("2026-11-09", ["rest"])], reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget.", now: Date = noon) throws -> AddressDetail {
    let until = untilDaysFromToday.map { StockholmClock.today(now: now).adding(days: $0).iso }
    return detail(try periodSchedule(events, until: until, reason: reason), now: now)
}

@Test func rutanVisasNarSchematHarFjortonDagarEllerMindreKvar() throws {
    #expect(try ending(15).scheduleEnding == nil)
    #expect(try ending(14).scheduleEnding?.daysLeft == 14)
    #expect(try ending(1).scheduleEnding?.daysLeft == 1)
    #expect(try ending(0).scheduleEnding?.daysLeft == 0)
}

@Test func rutanVisasInteForPasseratDatumEllerLivekallor() throws {
    #expect(try ending(-1).scheduleEnding == nil)
    #expect(try ending(nil).scheduleEnding == nil)
    #expect(detail(nil).scheduleEnding == nil)
}

@Test func rutanHarOrsakenOchSagerAttNyaTiderKommer() throws {
    let result = try ending(10)
    #expect(result.scheduleEnding?.title == "Schemat tar snart slut")
    #expect(result.scheduleEnding?.message == "Nya tider visas när källan publicerar dem.")
    #expect(try ending(10, reason: nil).scheduleEnding?.message == "Nya tider visas när källan publicerar dem.")
    // Källans orsak står en gång, under raden "Schemat gäller till", och inte i rutan.
    #expect(result.schedulePeriod?.reason == "Avesta Vatten publicerar hämtschemat ett år i taget.")
    #expect(result.scheduleEnding?.message.contains("Avesta Vatten") == false)
}

@Test func rutanVisasInteUtanKommandeHamtningar() throws {
    // Då säger kortet utan hämtningar hur långt schemat gäller, så rutan skulle bara upprepa det.
    let result = try ending(5, events: [event("2026-11-01", ["rest"])])
    #expect(result.mode == .noUpcoming)
    #expect(result.scheduleEnding == nil)
}

@Test func efterDatumetGallerOmgangCsTexter() throws {
    let result = try ending(-3, events: [event("2026-11-01", ["rest"])])
    #expect(result.scheduleEnding == nil)
    #expect(result.noUpcomingMessage.message.contains("källan har inte publicerat nästa period än"))
}

// Prövar Stockholmstid mot telefonens tidszon och säger något först med TZ=America/New_York, som sviten körs med.
@Test func rutanRaknasISvenskTidOavsettTelefonensTidszon() throws {
    // 00:30 den 7 november i Stockholm är 18:30 den 6:e i New York. I dag är den 7:e, och 21 november är 14 dagar kvar.
    let early = StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 30)
    let result = detail(try periodSchedule([event("2026-11-09", ["rest"])], until: "2026-11-21"), now: early)
    #expect(result.scheduleEnding?.daysLeft == 14)
}

// MARK: Påminnelser utan hämtningar

private func reminderDetail(_ schedule: CachedSchedule?, notificationsOn: Bool = false, isPrimary: Bool = true, liveActivityOn: Bool = false) -> AddressDetail {
    var saved = address
    saved.notificationsOn = notificationsOn
    saved.isPrimary = isPrimary
    return AddressDetail.make(address: saved, schedule: schedule, settings: ReminderSettings(liveActivityOn: liveActivityOn), sourceName: "Uppsala Vatten", now: noon)
}

@Test func paminnelserVisasMedHamtningar() throws {
    #expect(reminderDetail(try schedule([event("2026-11-09", ["rest"])])).showsReminders)
}

@Test func paminnelserDoljsUtanHamtningar() throws {
    let result = reminderDetail(try schedule([]))
    #expect(result.mode == .noUpcoming)
    #expect(!result.showsReminders)
}

@Test func paminnelserVisasUtanHamtningarNarNotisenArPa() throws {
    let result = reminderDetail(try schedule([]), notificationsOn: true)
    #expect(result.showsReminders)
    #expect(result.reminderText == "Inga hämtningar att påminna om just nu.")
}

@Test func paminnelserVisasUtanHamtningarNarLiveActivityArPaForHuvudadressen() throws {
    let primary = reminderDetail(try schedule([]), liveActivityOn: true)
    #expect(primary.showsReminders)
    #expect(primary.liveActivityText == "Inga hämtningar att påminna om just nu.")
    // Live Activity gäller bara huvudadressen.
    #expect(!reminderDetail(try schedule([]), isPrimary: false, liveActivityOn: true).showsReminders)
}

@Test func paminnelserVisasInteMedanSchematLaddas() {
    #expect(!reminderDetail(nil, notificationsOn: true).showsReminders)
}
