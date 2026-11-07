import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-placedout-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private let key = AddressKey(source: "kallor", id: "hem")
private let today = DayDate("2026-11-08")!

private func entry(_ offset: Int) -> PlacedOut {
    PlacedOut(key: key, date: today.adding(days: offset))
}

@Test func enPostLaggsTillUtanAttAndraOvriga() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.markPlacedOut(entry(1), today: today)
    try store.markPlacedOut(entry(2), today: today)
    try store.markPlacedOut(entry(1), today: today)
    #expect(Set(store.placedOut()) == [entry(1), entry(2)])
    #expect(store.placedOut().count == 2)
}

@Test func samtidigaSkrivningarTapparIngenPost() async throws {
    // Varje skrivning har sin egen `LocalStore`, som appen och intenten. Utan samordning försvinner poster här.
    let temp = TempDir()
    let count = 60
    let url = temp.url
    DispatchQueue.concurrentPerform(iterations: count) { index in
        try? LocalStore(directory: url).markPlacedOut(PlacedOut(key: key, date: today.adding(days: index + 1)), today: today)
    }
    let saved = LocalStore(directory: temp.url).placedOut()
    #expect(saved.count == count)
    #expect(Set(saved).count == count)
}

@Test func samtidigRensningOchSkrivningTapparIngenPost() async throws {
    let temp = TempDir()
    let url = temp.url
    let old = (1...20).map { entry(-$0) }
    try LocalStore(directory: url).setPlacedOut(old)
    DispatchQueue.concurrentPerform(iterations: 40) { index in
        let store = LocalStore(directory: url)
        if index.isMultiple(of: 2) {
            try? store.markPlacedOut(PlacedOut(key: key, date: today.adding(days: index + 1)), today: today)
        } else {
            try? store.prunePlacedOut(today: today)
        }
    }
    let saved = Set(LocalStore(directory: temp.url).placedOut())
    #expect(saved.count == 20)
    #expect(saved.allSatisfy { $0.date > today })
}

@Test func passeradePosterRensas() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setPlacedOut([entry(-1), entry(0), entry(1)])
    try store.prunePlacedOut(today: today)
    // Dagens post är kvar: tömningen är inte över förrän dagen har passerat.
    #expect(Set(store.placedOut()) == [entry(0), entry(1)])
}

@Test func enNyPostRensarPasserade() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setPlacedOut([entry(-3)])
    try store.markPlacedOut(entry(1), today: today)
    #expect(store.placedOut() == [entry(1)])
}

@Test func rensningUtanFilSkapasIngenFil() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.prunePlacedOut(today: today)
    #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("placed-out.json").path))
}

@Test func skadadFilErsattsAvNyPost() throws {
    // Utställt ska gå att spara även efter att filen skadats. Det som går förlorat är bara att en tömning kan startas igen.
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    try Data("inte json".utf8).write(to: temp.url.appendingPathComponent("placed-out.json"))
    guard case .unreadable = store.placedOutState() else {
        Issue.record("Skadad fil ska ge unreadable")
        return
    }
    try store.markPlacedOut(entry(1), today: today)
    #expect(store.placedOut() == [entry(1)])
}

@Test func skrivfelVidUtstalltKastas() throws {
    let temp = TempDir()
    // En fil där katalogen skulle ligga, så att skrivningen inte går.
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    let blocked = temp.url.appendingPathComponent("blockerad")
    try Data().write(to: blocked)
    #expect(throws: (any Error).self) { try LocalStore(directory: blocked).markPlacedOut(entry(1), today: today) }
}

/// Fejk för notiscentret: noterar vilka identifierare som tas bort, och kan misslyckas.
private actor FakeCenter {
    private(set) var cancelled: [String] = []
    private let failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    struct Failed: Error {}
    func cancel(_ id: String) throws {
        cancelled.append(id)
        if failing { throw Failed() }
    }
}

@Test func utstalltAvslutarAktivitetenSpararOchTarBortNotisen() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let ended = EndedFlag()
    let center = FakeCenter()
    let saved = await PlacedOutAction.perform(store: store, entry: entry(1), today: today, end: { await ended.set() }, cancelReminder: { try await center.cancel($0) })
    #expect(saved)
    #expect(await ended.value)
    #expect(store.placedOut() == [entry(1)])
    // Adressens och datumets notis, med samma identifierare som planeraren ger.
    #expect(await center.cancelled == ["\(key.fileName)-\(entry(1).date.iso)"])
    #expect(await center.cancelled == [PlannedNotification.identifier(key: key, date: entry(1).date)])
}

@Test func utstalltAvslutarAktivitetenAvenVidSkrivfel() async throws {
    let temp = TempDir()
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    let blocked = temp.url.appendingPathComponent("blockerad")
    try Data().write(to: blocked)
    let ended = EndedFlag()
    let center = FakeCenter()
    // Skrivfelet kastas inte utanför.
    let saved = await PlacedOutAction.perform(store: LocalStore(directory: blocked), entry: entry(1), today: today, end: { await ended.set() }, cancelReminder: { try await center.cancel($0) })
    #expect(!saved)
    #expect(await ended.value)
    // Notisen tas bort ändå: användaren har sagt att det är utställt.
    #expect(await center.cancelled.count == 1)
}

@Test func utstalltAvslutarAktivitetenAvenNarNotisenInteGarAttTaBort() async throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    let ended = EndedFlag()
    let center = FakeCenter(failing: true)
    let saved = await PlacedOutAction.perform(store: store, entry: entry(1), today: today, end: { await ended.set() }, cancelReminder: { try await center.cancel($0) })
    // Felet kastas inte, aktiviteten är avslutad och valet sparat. Följden är bara en extra påminnelse.
    #expect(saved)
    #expect(await ended.value)
    #expect(store.placedOut() == [entry(1)])
    #expect(await center.cancelled.count == 1)
}

@Test func visadeSparasRensasOchTomsPaBegaran() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.markShown([entry(-1), entry(1)], today: today)
    #expect(store.shownActivities() == [entry(1)])
    try store.markShown([entry(1), entry(2)], today: today)
    #expect(Set(store.shownActivities()) == [entry(1), entry(2)])
    #expect(store.shownActivities().count == 2)
    try store.clearShown()
    #expect(store.shownActivities().isEmpty)
    // Filerna är skilda åt: en visad är inte utställd.
    #expect(store.placedOut().isEmpty)
}

private actor EndedFlag {
    var value = false
    func set() { value = true }
}
