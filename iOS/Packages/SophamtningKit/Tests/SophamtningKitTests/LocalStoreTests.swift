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
    #expect(ReminderSettings.isValid(minutes: m) == ok)
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
