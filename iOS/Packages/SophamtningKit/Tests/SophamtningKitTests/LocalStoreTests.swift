import Testing
import Foundation
import SophamtningKit

/// En tillfällig katalog som städas när testet är klart.
private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-test-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private func tempStore() -> (LocalStore, URL, TempDir) {
    let temp = TempDir()
    return (LocalStore(directory: temp.url), temp.url, temp)
}

private let testKey = AddressKey(source: "orebro", id: "storgatan-21_örebro-75130")

extension SavedAddress {
    /// Testhjälpare, inte produktionskod.
    static func fixture(key: AddressKey = testKey, isPrimary: Bool = false) -> SavedAddress {
        SavedAddress(
            key: key,
            url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/storgatan-21_%C3%B6rebro-75130")!,
            street: "Storgatan 21",
            locality: "Örebro",
            kommun: "Örebro",
            detail: nil,
            selection: "address",
            displayName: "Storgatan 21, Örebro",
            isPrimary: isPrimary,
            addedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private func fixtureResponse() throws -> AddressResponse {
    let url = Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(AddressResponse.self, from: Data(contentsOf: url))
}

@Test func spararOchLaserAdress() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let saved = SavedAddress.fixture(isPrimary: true)
    try store.setAddresses([saved])
    #expect(store.addresses() == [saved])
    #expect(Array(store.addresses().first!.key.id.utf8) == Array("storgatan-21_örebro-75130".utf8))
}

@Test func filnamnInnehallerBaraHex() {
    #expect(testKey.fileName.count == 64)
    #expect(testKey.fileName.allSatisfy { $0.isHexDigit })
}

@Test func filnamnArKantSha256OchSkiljerGranser() {
    let key = AddressKey(source: "orebro", id: "storgatan-21_örebro-75130")
    #expect(key.fileName == "28f0462e0be6d48847a301fd2b7389cfa572904da8d74853d5e86ebbf1105832")
    #expect(AddressKey(source: "a", id: "bc").fileName != AddressKey(source: "ab", id: "c").fileName)
}

@Test func skrivfelKastas() throws {
    let (_, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    let file = temp.url.appendingPathComponent("en-fil")
    try Data("x".utf8).write(to: file)
    let store = LocalStore(directory: file.appendingPathComponent("under"))
    #expect(throws: (any Error).self) { try store.setAddresses([SavedAddress.fixture()]) }
    #expect(throws: (any Error).self) { try store.setSchedule(CachedSchedule(), for: testKey) }
}

@Test func taBortSaknatSchemaArInteFel() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    try store.removeSchedule(for: testKey)
}

@Test func skadadFilBehandlasSomSaknad() throws {
    let (store, dir, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    try store.setSchedule(CachedSchedule(response: fixtureResponse(), fetchedAt: Date(), lastAttemptAt: nil, lastError: nil), for: testKey)
    let file = dir.appendingPathComponent("schedules/\(testKey.fileName).json")
    try Data("{".utf8).write(to: file)
    #expect(store.schedule(for: testKey) == nil)
    for name in ["addresses.json", "settings.json", "placed-out.json", "sources.json"] {
        try Data("{".utf8).write(to: dir.appendingPathComponent(name))
    }
    #expect(store.addresses().isEmpty)
    #expect(store.settings() == ReminderSettings())
    #expect(store.placedOut().isEmpty)
    #expect(store.sources() == nil)
}

@Test func standardinstallningarArAvstangda() {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    #expect(store.settings().liveActivityOn == false)
    #expect(store.settings().reminderMinutes == 1080)
    #expect(SavedAddress.fixture().notificationsOn == false)
}

@Test(arguments: [(899, false), (900, true), (915, true), (916, false), (1380, true), (1395, false)])
func giltigaPaminnelsetider(m: Int, ok: Bool) {
    #expect(ReminderSettings.isValid(minutes: m, for: .eveningBefore) == ok)
}

@Test func spararOchTarBortSchema() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let schedule = try CachedSchedule(response: fixtureResponse(), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), lastAttemptAt: nil, lastError: .sourceUnavailable)
    try store.setSchedule(schedule, for: testKey)
    #expect(store.schedule(for: testKey) == schedule)
    try store.removeSchedule(for: testKey)
    #expect(store.schedule(for: testKey) == nil)
}

@Test func spararInstallningarUtplaceradeOchKallor() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let settings = ReminderSettings(reminderMinutes: 960, liveActivityOn: true)
    try store.setSettings(settings)
    #expect(store.settings() == settings)
    let placed = [PlacedOut(key: testKey, date: DayDate("2026-11-09")!)]
    try store.setPlacedOut(placed)
    #expect(store.placedOut() == placed)
    let sources = CachedSources(response: SourcesResponse(sources: [], fractions: [:]), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    try store.setSources(sources)
    #expect(store.sources() == sources)
}

@Test func tvaLagerDelarFiler() throws {
    let (a, dir, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let b = LocalStore(directory: dir)
    try a.setAddresses([SavedAddress.fixture()])
    #expect(b.addresses().count == 1)
}

@Test func lagringenSkiljerSaknadFranOlasbarFil() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sophamtning-state-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LocalStore(directory: dir)
    if case .missing = store.addressesState() {} else { Issue.record("saknad adressfil ska vara missing") }
    if case .missing = store.settingsState() {} else { Issue.record("saknad inställningsfil ska vara missing") }
    if case .missing = store.scheduleState(for: testKey) {} else { Issue.record("saknat schema ska vara missing") }

    try store.setAddresses([.fixture(isPrimary: true)])
    try store.setSettings(ReminderSettings())
    try store.setSchedule(CachedSchedule(), for: testKey)
    if case .value(let list) = store.addressesState() { #expect(list.count == 1) } else { Issue.record("adresser ska gå att läsa") }
    if case .value = store.settingsState() {} else { Issue.record("inställningar ska gå att läsa") }
    if case .value = store.scheduleState(for: testKey) {} else { Issue.record("schema ska gå att läsa") }

    try Data("skräp".utf8).write(to: dir.appendingPathComponent("addresses.json"))
    try Data("skräp".utf8).write(to: dir.appendingPathComponent("settings.json"))
    try Data("skräp".utf8).write(to: dir.appendingPathComponent("schedules/\(testKey.fileName).json"))
    if case .unreadable = store.addressesState() {} else { Issue.record("skadad adressfil ska vara unreadable") }
    if case .unreadable = store.settingsState() {} else { Issue.record("skadad inställningsfil ska vara unreadable") }
    if case .unreadable = store.scheduleState(for: testKey) {} else { Issue.record("skadat schema ska vara unreadable") }
    // De gamla anropen läser en skadad fil som saknad, som förut.
    #expect(store.addresses().isEmpty)
}

@Test func lagringenSkiljerOtillgangligFranSkadadFil() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sophamtning-unavailable-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LocalStore(directory: dir)
    try store.setAddresses([.fixture(isPrimary: true)])
    let file = dir.appendingPathComponent("addresses.json")

    // Läsningen misslyckas men innehållet är helt: otillgänglig, inte skadad.
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
    if case .unavailable = store.addressesState() {} else { Issue.record("en fil som inte går att läsa ska vara unavailable") }

    // Läsningen går bra men innehållet går inte att tolka: skadad.
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    try Data("skräp".utf8).write(to: file)
    if case .unreadable = store.addressesState() {} else { Issue.record("ett innehåll som inte går att tolka ska vara unreadable") }
}

// MARK: Hushåll

@Test func hushalletSparasOchLasesTillbaka() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let state = HouseholdState(
        role: .owner,
        myId: "jag",
        participants: [HouseholdParticipant(id: "jag", name: "Jesper", isOwner: true)],
        addresses: [HouseholdAddress(address: .fixture(), addedBy: "jag")],
        marks: [HouseholdMark(placedOut: PlacedOut(key: testKey, date: DayDate("2026-11-09")!), by: "jag", at: Date(timeIntervalSince1970: 1_800_000_000), isPending: false)],
        status: .quotaExceeded(ownerName: "Jesper")
    )
    try store.setHouseholdState(state)
    guard case .value(let read) = store.householdState() else {
        Issue.record("Hushållet gick inte att läsa")
        return
    }
    #expect(read == state)
}

@Test func saknadHushallsfilArMissing() {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    guard case .missing = store.householdState() else {
        Issue.record("Väntade .missing")
        return
    }
}

@Test func hushallsinstallningarSparasOchLases() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    #expect(store.householdPreferences() == HouseholdPreferences())
    let preferences = HouseholdPreferences(silenceWhenOthersPlaceOut: false, notifyWhenOthersPlaceOut: true, receivedKeys: [testKey])
    try store.setHouseholdPreferences(preferences)
    #expect(store.householdPreferences() == preferences)
}

@Test func unmarkTarBortBaraDenBocken() throws {
    let (store, _, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    let first = PlacedOut(key: testKey, date: DayDate("2026-11-09")!)
    let second = PlacedOut(key: testKey, date: DayDate("2026-11-10")!)
    try store.setPlacedOut([first, second])
    try store.unmarkPlacedOut(first)
    #expect(store.placedOut() == [second])
}

@Test func raDataSkrivsLasesOchTasBort() throws {
    let (store, _, temp) = tempStore()
    _ = temp
    guard case .missing = store.rawData(named: "household-engine-private.data") else {
        Issue.record("En fil som saknas ska läsas som saknad")
        return
    }
    try store.setRawData(Data([1, 2, 3]), named: "household-engine-private.data")
    guard case .value(let data) = store.rawData(named: "household-engine-private.data") else {
        Issue.record("Datan ska gå att läsa")
        return
    }
    #expect(data == Data([1, 2, 3]))
    try store.removeRawData(named: "household-engine-private.data")
    try store.removeRawData(named: "household-engine-private.data")
    guard case .missing = store.rawData(named: "household-engine-private.data") else {
        Issue.record("Filen ska vara borttagen")
        return
    }
}

@Test func installningarUtanForslagsfaltetLasesSomForut() throws {
    // Inställningar sparade före fältet `reminderOfferShown` ska läsas som de är, inte som skadade.
    let (store, dir, temp) = tempStore()
    defer { withExtendedLifetime(temp) {} }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(#"{"reminderMinutes":960,"liveActivityOn":true}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
    let settings = store.settings()
    #expect(settings.reminderMinutes == 960)
    #expect(settings.liveActivityOn)
    #expect(settings.reminderOfferShown == false)
}
