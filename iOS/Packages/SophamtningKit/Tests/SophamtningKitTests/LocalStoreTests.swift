import Testing
import Foundation
import SophamtningKit

private func tempStore() -> (LocalStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-test-\(UUID().uuidString)", isDirectory: true)
    return (LocalStore(directory: dir), dir)
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

@Test func spararOchLaserAdress() {
    let (store, _) = tempStore()
    let saved = SavedAddress.fixture(isPrimary: true)
    store.setAddresses([saved])
    #expect(store.addresses() == [saved])
    #expect(store.addresses().first?.key.id == "storgatan-21_örebro-75130")
}

@Test func filnamnInnehallerBaraHex() {
    #expect(testKey.fileName.count == 64)
    #expect(testKey.fileName.allSatisfy { $0.isHexDigit })
}

@Test func skadadFilBehandlasSomSaknad() throws {
    let (store, dir) = tempStore()
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
    let (store, _) = tempStore()
    #expect(store.settings().liveActivityOn == false)
    #expect(store.settings().reminderMinutes == 1080)
    #expect(SavedAddress.fixture().notificationsOn == false)
}

@Test(arguments: [(899, false), (900, true), (915, true), (916, false), (1380, true), (1395, false)])
func giltigaPaminnelsetider(m: Int, ok: Bool) {
    #expect(ReminderSettings.isValid(minutes: m) == ok)
}

@Test func spararOchTarBortSchema() throws {
    let (store, _) = tempStore()
    let schedule = try CachedSchedule(response: fixtureResponse(), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), lastAttemptAt: nil, lastError: .sourceUnavailable)
    store.setSchedule(schedule, for: testKey)
    #expect(store.schedule(for: testKey) == schedule)
    store.removeSchedule(for: testKey)
    #expect(store.schedule(for: testKey) == nil)
}

@Test func spararInstallningarUtplaceradeOchKallor() throws {
    let (store, _) = tempStore()
    let settings = ReminderSettings(reminderMinutes: 960, liveActivityOn: true)
    store.setSettings(settings)
    #expect(store.settings() == settings)
    let placed = [PlacedOut(key: testKey, date: DayDate("2026-11-09")!)]
    store.setPlacedOut(placed)
    #expect(store.placedOut() == placed)
    let sources = CachedSources(response: SourcesResponse(sources: [], fractions: [:]), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    store.setSources(sources)
    #expect(store.sources() == sources)
}

@Test func tvaLagerDelarFiler() {
    let (a, dir) = tempStore()
    let b = LocalStore(directory: dir)
    a.setAddresses([SavedAddress.fixture()])
    #expect(b.addresses().count == 1)
}
