import Testing
import Foundation
import SophamtningKit

/// Fredag 6 november 2026 klockan 12:00 svensk tid.
private let now = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

private func stockholm(_ text: String) -> Date {
    let parts = text.split(separator: "T")
    let clock = parts[1].split(separator: ":").compactMap { Int($0) }
    return StockholmClock.date(on: DayDate(String(parts[0]))!, minutes: clock[0] * 60 + clock[1])
}

private let info: [String: FractionInfo] = [
    "rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#474C48", icon: "trash-2"),
    "mat": FractionInfo(name: "Matavfall", short: "Mat", color: "#7A4A1E", icon: "apple"),
    "papper": FractionInfo(name: "Papper", short: "Papper", color: "#2E5E86", icon: "package"),
]

private func event(_ iso: String, _ fractions: [String], estimated: Bool = false) -> PickupEvent {
    PickupEvent(date: DayDate(iso)!, fractions: fractions, estimated: estimated, deviation: nil, warning: nil, labels: [:])
}

private func schedule(_ events: [PickupEvent], lastError: APIError? = nil, withResponse: Bool = true) -> CachedSchedule {
    let response = AddressResponse(
        today: DayDate("2026-11-06")!,
        address: Address(id: "a", street: "Storgatan 12 B", locality: "Krylbo", kommun: "Avesta", source: "x", detail: nil, selection: "address", notice: nil),
        next: [], summary: "Gammal text", events: events, bins: [], fractions: info,
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
private let cabin = address("cabin", name: "Stugan", primary: false)

@Test func utanAdress() {
    #expect(WidgetContent.make(addresses: [], schedule: nil, now: now) == .noAddress)
}

@Test func anvanderHuvudadressen() {
    let content = WidgetContent.make(addresses: [cabin, home], schedule: schedule([event("2026-11-09", ["rest"])]), now: now)
    guard case .pickup(let name, _, _, _) = content else { Issue.record("Väntade kommande hämtning"); return }
    #expect(name == "Hemma")
}

@Test func utanMarkeringAnvandsForstaAdressen() {
    let content = WidgetContent.make(addresses: [address("a", name: "Första", primary: false), cabin], schedule: schedule([]), now: now)
    #expect(content == .noUpcoming(name: "Första"))
}

@Test func raknarDagarLokalt() {
    // Svaret sparades den 6:e, och dess egna dagsfält ignoreras. Nu är det lördag den 7:e, dagen före tömningen.
    let saturday = stockholm("2026-11-07T09:00")
    let content = WidgetContent.make(addresses: [home], schedule: schedule([event("2026-11-08", ["rest"])]), now: saturday)
    guard case .pickup(_, let relative, let shortDate, _) = content else { Issue.record("Väntade kommande hämtning"); return }
    #expect(relative == "i morgon")
    #expect(shortDate == "Sön 8 nov")
}

@Test func visarOmTreDagarMedAllaFraktionerPerNastaDatum() {
    let events = [event("2026-11-09", ["rest", "mat"]), event("2026-11-12", ["papper"], estimated: true)]
    let content = WidgetContent.make(addresses: [home], schedule: schedule(events), now: now)
    guard case .pickup(_, let relative, let shortDate, let fractions) = content else { Issue.record("Väntade kommande hämtning"); return }
    #expect(relative == "om 3 dagar")
    #expect(shortDate == "Mån 9 nov")
    #expect(fractions.map(\.fraction) == ["mat", "rest", "papper"])
    #expect(fractions.map(\.daysUntil) == [3, 3, 6])
    #expect(fractions.map(\.estimated) == [false, false, true])
}

@Test func beraknatDatumFarCa() {
    let content = WidgetContent.make(addresses: [home], schedule: schedule([event("2026-11-09", ["rest"], estimated: true)]), now: now)
    guard case .pickup(_, let relative, let shortDate, _) = content else { Issue.record("Väntade kommande hämtning"); return }
    #expect(relative == "ca om 3 dagar")
    #expect(shortDate == "ca mån 9 nov")
}

@Test func raderVisarKortDatumMedCaForBeraknade() {
    let events = [event("2026-11-09", ["rest"]), event("2026-11-12", ["papper"], estimated: true)]
    guard case .pickup(_, _, _, let fractions) = WidgetContent.make(addresses: [home], schedule: schedule(events), now: now) else { Issue.record("Väntade kommande hämtning"); return }
    #expect(fractions.map { WidgetContent.rowDate($0) } == ["mån 9 nov", "ca tors 12 nov"])
}

@Test func tomningIDagVisasSomIDag() {
    let content = WidgetContent.make(addresses: [home], schedule: schedule([event("2026-11-06", ["rest"])]), now: now)
    guard case .pickup(_, let relative, _, _) = content else { Issue.record("Väntade kommande hämtning"); return }
    #expect(relative == "i dag")
}

@Test func baraPasseratVisarIngaKommande() {
    let content = WidgetContent.make(addresses: [home], schedule: schedule([event("2026-11-02", ["rest"]), event("2026-11-05", ["mat"])]), now: now)
    #expect(content == .noUpcoming(name: "Hemma"))
}

@Test func saknatSchemaArInteTomtLage() {
    #expect(WidgetContent.make(addresses: [home], schedule: nil, now: now) == .noSchedule(name: "Hemma"))
    // Ett försök utan svar och utan fel är också "ännu inte hämtat".
    #expect(WidgetContent.make(addresses: [home], schedule: schedule([], withResponse: false), now: now) == .noSchedule(name: "Hemma"))
}

@Test func misslyckadHamtningOchNotFoundHarEgnaLagen() {
    #expect(WidgetContent.make(addresses: [home], schedule: schedule([], lastError: .network, withResponse: false), now: now) == .failed(name: "Hemma"))
    #expect(WidgetContent.make(addresses: [home], schedule: schedule([], lastError: .sourceUnavailable, withResponse: false), now: now) == .failed(name: "Hemma"))
    #expect(WidgetContent.make(addresses: [home], schedule: schedule([], lastError: .notFound, withResponse: false), now: now) == .notFound(name: "Hemma"))
}

@Test func faltFelDoljerInteEttSparatSchema() {
    // Ett äldre svar visas även om det senaste försöket misslyckades, som på hemskärmen.
    let content = WidgetContent.make(addresses: [home], schedule: schedule([event("2026-11-09", ["rest"])], lastError: .notFound), now: now)
    if case .pickup = content {} else { Issue.record("Väntade det sparade schemat, fick \(content)") }
}

@Test func harSammaSanningSomHemskarmen() {
    // Huvudkortet och widgeten läser samma schema och ska vara överens i varje läge.
    let cases: [(CachedSchedule?, String)] = [
        (nil, "loading"),
        (schedule([], lastError: .notFound, withResponse: false), "notFound"),
        (schedule([], lastError: .network, withResponse: false), "failed"),
        (schedule([]), "noUpcoming"),
        (schedule([event("2026-11-09", ["rest"])]), "pickup"),
    ]
    for (value, expected) in cases {
        let widget = WidgetContent.make(addresses: [home], schedule: value, now: now)
        let schedules = value.map { [home.key: $0] } ?? [:]
        let status = HomeContent.make(addresses: [home], schedules: schedules, settings: ReminderSettings(), now: now).primary?.status
        let widgetName: String
        switch widget {
        case .noSchedule: widgetName = "loading"
        case .notFound: widgetName = "notFound"
        case .failed: widgetName = "failed"
        case .noUpcoming: widgetName = "noUpcoming"
        case .pickup: widgetName = "pickup"
        default: widgetName = "annat"
        }
        let homeName: String
        switch status {
        case .loading: homeName = "loading"
        case .failed(.notFound): homeName = "notFound"
        case .failed: homeName = "failed"
        case .noUpcoming: homeName = "noUpcoming"
        case .upcoming: homeName = "pickup"
        case nil: homeName = "ingen"
        }
        #expect(widgetName == expected)
        #expect(homeName == expected)
    }
}

// MARK: Tidslinje

@Test func tidslinjenByterVidSvenskMidnatt() {
    #expect(WidgetContent.timelineDates(from: stockholm("2026-11-08T20:00"), days: 2)
        == [stockholm("2026-11-08T20:00"), stockholm("2026-11-09T00:00"), stockholm("2026-11-10T00:00")])
}

@Test func tidslinjenStartarPaNuOchBorjarOmDagenGarOver() {
    // Klockan 23:59:30 svensk tid: nästa byte är om en halv minut.
    let almostMidnight = stockholm("2026-11-08T23:59").addingTimeInterval(30)
    let dates = WidgetContent.timelineDates(from: almostMidnight, days: 1)
    #expect(dates == [almostMidnight, stockholm("2026-11-09T00:00")])
}

@Test func tidslinjenFoljerSvenskTidAvenOmSommartidenAndras() {
    // 25 oktober 2026 slutar sommartiden: dygnet är 25 timmar, midnatten byts ändå vid väggklockan 00:00.
    let dates = WidgetContent.timelineDates(from: stockholm("2026-10-24T12:00"), days: 2)
    #expect(dates == [stockholm("2026-10-24T12:00"), stockholm("2026-10-25T00:00"), stockholm("2026-10-26T00:00")])
    #expect(dates[2].timeIntervalSince(dates[1]) == 25 * 3600)
}

@Test func tidslinjenUtanDagarArBaraNu() {
    #expect(WidgetContent.timelineDates(from: now, days: 0) == [now])
}

// MARK: Läsning från lagringen

private final class TempDir {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sophamtning-widget-\(UUID().uuidString)", isDirectory: true)
    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Gör alla filer i katalogen oläsbara (som skyddad data före upplåsning) eller läsbara igen.
private func setReadable(_ readable: Bool, in directory: URL) throws {
    let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
    for file in files where file.pathExtension == "json" {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o644 : 0o000], ofItemAtPath: file.path)
    }
}

@Test func lagringenUtanFilerGerNoAddress() {
    let temp = TempDir()
    let data = WidgetData.read(from: LocalStore(directory: temp.url))
    #expect(data.content(at: now) == .noAddress)
    #expect(data.reloadDate(after: now) == nil)
}

@Test func lagringenGerHuvudadressenOchDessSchema() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([cabin, home])
    try store.setSchedule(schedule([event("2026-11-09", ["rest", "mat"])]), for: home.key)
    let data = WidgetData.read(from: store)
    guard case .pickup(let name, _, _, let fractions) = data.content(at: now) else { Issue.record("Väntade kommande hämtning"); return }
    #expect(name == "Hemma")
    #expect(fractions.count == 2)
    #expect(data.info(for: "mat").name == "Matavfall")
    // Okända fraktioner får sitt id som namn, som i appen.
    #expect(data.info(for: "okand").name == "okand")
}

@Test func adresserSomInteGarAttLasaArInteNoAddress() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try setReadable(false, in: temp.url)
    defer { try? setReadable(true, in: temp.url) }
    let data = WidgetData.read(from: store)
    #expect(data.content(at: now) == .unavailable)
    #expect(data.content(at: now) != .noAddress)
    // Försöker igen inom 15 minuter.
    #expect(data.reloadDate(after: now) == now.addingTimeInterval(15 * 60))
}

@Test func skadadAdressfilArInteNoAddress() throws {
    let temp = TempDir()
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    try Data("inte json".utf8).write(to: temp.url.appendingPathComponent("addresses.json"))
    let data = WidgetData.read(from: LocalStore(directory: temp.url))
    #expect(data.content(at: now) == .unavailable)
    #expect(data.reloadDate(after: now) == now.addingTimeInterval(15 * 60))
}

@Test func schemaSomInteGarAttLasaGerUnavailableOchInteSaknatSchema() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(schedule([event("2026-11-09", ["rest"])]), for: home.key)
    // Bara schemafilen blir oläsbar, adresserna går att läsa.
    let schedules = temp.url.appendingPathComponent("schedules")
    try setReadable(false, in: schedules)
    defer { try? setReadable(true, in: schedules) }
    let data = WidgetData.read(from: store)
    #expect(data.content(at: now) == .unavailable)
    #expect(data.reloadDate(after: now) == now.addingTimeInterval(15 * 60))
}

@Test func skadatSchemaArInteSaknatSchemaHellre() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(schedule([]), for: home.key)
    let file = temp.url.appendingPathComponent("schedules/\(home.key.fileName).json")
    try Data("{".utf8).write(to: file)
    #expect(WidgetData.read(from: store).content(at: now) == .unavailable)
}

@Test func saknadSchemafilArSaknatSchema() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    let data = WidgetData.read(from: store)
    #expect(data.content(at: now) == .noSchedule(name: "Hemma"))
    #expect(data.reloadDate(after: now) == nil)
}

// MARK: Schemat slutar

private func endingSchedule(until: String?, events: [PickupEvent] = [event("2026-11-09", ["rest"])]) -> CachedSchedule {
    var cached = schedule(events)
    let base = cached.response!
    cached.response = AddressResponse(today: base.today, address: base.address, next: [], summary: "", events: events, bins: [], fractions: base.fractions, links: base.links, updatedAt: base.updatedAt, schedule: until.map { SchedulePeriod(until: DayDate($0)!, reason: nil) })
    return cached
}

@Test func widgetenVisarNarSchematSlutarInomFjortonDagar() {
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: "2026-11-20"), now: now)?.shortText == "Schemat slutar 20 nov")
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: "2026-11-21"), now: now) == nil)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: "2026-11-06"), now: now)?.daysLeft == 0)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: "2026-11-05"), now: now) == nil)
}

@Test func widgetenVisarInteRadenForLivekallorUtanSchemaOchUtanHamtningar() {
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: nil), now: now) == nil)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: nil, now: now) == nil)
    #expect(WidgetContent.scheduleEnding(addresses: [], schedule: endingSchedule(until: "2026-11-20"), now: now) == nil)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: endingSchedule(until: "2026-11-10", events: [event("2026-11-01", ["rest"])]), now: now) == nil)
}

@Test func widgetenRaknarRadenFranTidslinjensTid() {
    // Raden försvinner av sig själv när dagarna går, utan att appen sparar något. Den 21 november är 15 dagar kvar i dag
    // och 14 dagar kvar i morgon.
    let cached = endingSchedule(until: "2026-11-21")
    let tomorrow = StockholmClock.date(on: DayDate("2026-11-07")!, minutes: 0)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: cached, now: now) == nil)
    #expect(WidgetContent.scheduleEnding(addresses: [home], schedule: cached, now: tomorrow)?.daysLeft == 14)
}

@Test func widgetdataFranLagringenGerRadenOchGammalSparadDataUtanFaltetGarBra() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(endingSchedule(until: "2026-11-20"), for: home.key)
    #expect(WidgetData.read(from: store).scheduleEnding(at: now)?.shortText == "Schemat slutar 20 nov")
    // Sparad data utan `schedule` avkodas utan fel och ger ingen rad.
    try store.setSchedule(schedule([event("2026-11-09", ["rest"])]), for: home.key)
    let old = WidgetData.read(from: store)
    #expect(old.scheduleEnding(at: now) == nil)
    guard case .pickup = old.content(at: now) else { Issue.record("Väntade kommande hämtning"); return }
}

// MARK: Hushållets bock

private func household(marks: [HouseholdMark], role: HouseholdRole = .member, status: HouseholdStatus = .synced) -> HouseholdState {
    HouseholdState(role: role, myId: "jag", participants: [], addresses: [HouseholdAddress(address: home, addedBy: "kim")], marks: marks, status: status)
}

private func mark(_ iso: String, key: AddressKey = home.key) -> HouseholdMark {
    HouseholdMark(placedOut: PlacedOut(key: key, date: DayDate(iso)!), by: "kim", at: now, isPending: false)
}

@Test func widgetenVisarUtstalltNarHushalletHarBockatNastaTomning() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(schedule([event("2026-11-07", ["rest"]), event("2026-11-14", ["mat"])]), for: home.key)
    try store.setHouseholdState(household(marks: [mark("2026-11-07")]))
    let data = WidgetData.read(from: store)
    #expect(data.placedOut(at: now))
    // Kim finns inte bland deltagarna i det här hushållet.
    #expect(data.placedOutBy(at: now) == "av någon")
    // Dagen efter gäller nästa tömning, som inte är bockad.
    #expect(!data.placedOut(at: stockholm("2026-11-08T08:00")))
    #expect(data.placedOutBy(at: stockholm("2026-11-08T08:00")) == nil)
}

@Test func widgetenVisarInteUtstalltForEnAnnanTomningEllerUtanHushall() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home, cabin])
    try store.setSchedule(schedule([event("2026-11-07", ["rest"])]), for: home.key)
    // Ingen fil: inget hushåll.
    #expect(!WidgetData.read(from: store).placedOut(at: now))
    // En bock för en annan adress.
    try store.setHouseholdState(household(marks: [mark("2026-11-07", key: cabin.key)]))
    #expect(!WidgetData.read(from: store).placedOut(at: now))
    // Ingen roll: bocken räknas inte.
    try store.setHouseholdState(household(marks: [mark("2026-11-07")], role: .none))
    #expect(!WidgetData.read(from: store).placedOut(at: now))
}

private func fractionPickup(_ id: String, _ iso: String) -> FractionPickup {
    FractionPickup(fraction: id, date: DayDate(iso)!, estimated: false, warning: nil, daysUntil: 0)
}

@Test func mellanstoraVisarBaraNästaTömning() {
    // Hemma: mat och papper den 25:e, plast den 9 dec och rest den 23 dec. Bara kärlen den 25:e visas, utan "+2 till".
    let fractions = [fractionPickup("mat", "2026-11-25"), fractionPickup("papper", "2026-11-25"), fractionPickup("plast", "2026-12-09"), fractionPickup("rest", "2026-12-23")]
    let result = WidgetContent.mediumRows(fractions, maxRows: 3)
    #expect(result.rows.map(\.fraction) == ["mat", "papper"])
    #expect(result.hidden == 0)
}

@Test func mellanstoraDöljerBaraSammaDagsKärl() {
    // Fyra kärl samma dag och plats för tre rader: två rader och "+2 till", som alla gäller samma tömning.
    let fractions = [fractionPickup("mat", "2026-11-25"), fractionPickup("papper", "2026-11-25"), fractionPickup("plast", "2026-11-25"), fractionPickup("rest", "2026-11-25"), fractionPickup("glas", "2026-12-09")]
    let result = WidgetContent.mediumRows(fractions, maxRows: 3)
    #expect(result.rows.map(\.fraction) == ["mat", "papper"])
    #expect(result.hidden == 2)
    #expect(WidgetContent.mediumRows([], maxRows: 3).rows.isEmpty)
}

// MARK: Låsskärmen

private func lock(_ events: [PickupEvent], placedOut: Bool = false) -> LockScreenContent {
    LockScreenContent.make(content: WidgetContent.make(addresses: [home], schedule: schedule(events), now: now), info: info, placedOut: placedOut)
}

@Test func låsskärmenNästaTömning() {
    // Fredag 6 november. Torsdag 19 november är om 13 dagar.
    let c = lock([event("2026-11-19", ["mat", "papper"]), event("2026-11-26", ["rest"])])
    #expect(c.inline == "Tors 19 nov: Mat, Papper")
    #expect(c.title == "Om 13 dagar")
    #expect(c.date == "Tors 19 nov")
    #expect(c.line == "Mat, Papper")
    #expect(c.days == "13")
    #expect(!c.placedOut)
}

@Test func låsskärmenIDagOchIMorgon() {
    let tomorrow = lock([event("2026-11-07", ["rest"])])
    #expect(tomorrow.inline == "I morgon: Rest")
    #expect(tomorrow.title == "I morgon")
    #expect(tomorrow.days == "1")
    #expect(lock([event("2026-11-06", ["rest"])]).inline == "I dag: Rest")
    #expect(lock([event("2026-11-06", ["rest"])]).days == "0")
}

@Test func låsskärmenBeräknatDatum() {
    let c = lock([event("2026-11-19", ["mat"], estimated: true)])
    #expect(c.title == "Ca om 13 dagar")
    #expect(c.inline == "Ca tors 19 nov: Mat")
    #expect(c.date == "Ca tors 19 nov")
}

@Test func låsskärmenUtställt() {
    let c = lock([event("2026-11-07", ["rest", "mat"])], placedOut: true)
    #expect(c.inline == "Utställt: Mat, Rest")
    #expect(c.line == "Utställt")
    #expect(c.days == nil)
    #expect(c.placedOut)
}

@Test func låsskärmenUtanSchema() {
    for content in [WidgetContent.noAddress, .unavailable, .noSchedule(name: "Hemma"), .failed(name: "Hemma")] {
        let c = LockScreenContent.make(content: content, info: [:], placedOut: false)
        #expect(c.title == "Sophämtning")
        #expect(c.line == "Öppna appen")
        #expect(c.inline == "Sophämtning: öppna appen")
        #expect(c.days == nil)
    }
    let none = LockScreenContent.make(content: .noUpcoming(name: "Hemma"), info: [:], placedOut: false)
    #expect(none.title == "Hemma")
    #expect(none.line == "Inga kommande hämtningar")
    #expect(none.inline == "Hemma: inga kommande hämtningar")
}

// MARK: Ställ ut kärlen i widgeten

@Test func widgetensKnappDagenFöreOchSammaDag() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(schedule([event("2026-11-07", ["rest"])]), for: home.key)
    var data = WidgetData.read(from: store)
    #expect(data.placeOutEntry(at: now) == PlacedOut(key: home.key, date: DayDate("2026-11-07")!))
    // Min egen bock gör att knappen försvinner och widgeten visar Utställt, också utan hushåll.
    try store.markPlacedOut(PlacedOut(key: home.key, date: DayDate("2026-11-07")!), today: DayDate("2026-11-06")!)
    data = WidgetData.read(from: store)
    #expect(data.placeOutEntry(at: now) == nil)
    #expect(data.placedOut(at: now))
}

@Test func widgetensKnappInteLängreBort() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setAddresses([home])
    try store.setSchedule(schedule([event("2026-11-09", ["rest"])]), for: home.key)
    #expect(WidgetData.read(from: store).placeOutEntry(at: now) == nil)
}

// MARK: Kalender

@Test func kalenderlänken() {
    #expect(CalendarLink.webcal(URL(string: "https://sopor.hardyson.se/api/v1/adress/x/y.ics")) == URL(string: "webcal://sopor.hardyson.se/api/v1/adress/x/y.ics"))
    #expect(CalendarLink.webcal(nil) == nil)
    #expect(CalendarLink.webcal(URL(string: "mailto:a@b.se")) == nil)
    let links = SourceLink.links(for: nil, kommunInfo: URL(string: "https://example.com/a"), calendar: URL(string: "webcal://example.com/a.ics"))
    #expect(links.first?.kind == .calendar)
    #expect(links.first?.title == "Lägg till i Kalender")
    #expect(links.first?.webLink == nil)
    #expect(SourceLink.links(for: nil, kommunInfo: nil).allSatisfy { $0.kind != .calendar })
}

@Test func kontrollensVärde() {
    #expect(lock([event("2026-11-07", ["rest"])]).controlValue == "I morgon")
    #expect(lock([event("2026-11-06", ["rest"])]).controlValue == "I dag")
    #expect(lock([event("2026-11-19", ["rest"])]).controlValue == "Tors 19 nov")
    #expect(lock([event("2026-11-07", ["rest"])], placedOut: true).controlValue == "Utställt")
    #expect(LockScreenContent.make(content: .noAddress, info: [:], placedOut: false).controlValue == "Öppna appen")
}
