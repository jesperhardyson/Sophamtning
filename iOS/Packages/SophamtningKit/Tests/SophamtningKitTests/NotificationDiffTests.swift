import Testing
import Foundation
import SophamtningKit

private let key = AddressKey(source: "orebro", id: "1")

private func planned(_ id: String, at seconds: TimeInterval, body: String = "Text") -> PlannedNotification {
    PlannedNotification(identifier: id, fireDate: Date(timeIntervalSince1970: seconds), title: "Ställ ut kärlen", body: body, key: key, pickupDate: DayDate("2026-11-09")!)
}

@Test func ingenSkillnadGerIngaAndringar() {
    let desired = [planned("a", at: 100), planned("b", at: 200)]
    let result = NotificationDiff.diff(desired: desired, pendingIds: ["a", "b"], pendingFireDates: ["a": Date(timeIntervalSince1970: 100), "b": Date(timeIntervalSince1970: 200)])
    #expect(result.add.isEmpty)
    #expect(result.removeIds.isEmpty)
}

@Test func borttagenPlanTarBortVantande() {
    let result = NotificationDiff.diff(desired: [], pendingIds: ["b", "a"], pendingFireDates: [:])
    #expect(result.add.isEmpty)
    #expect(result.removeIds == ["a", "b"])
}

@Test func andradTidErsatterNotisen() {
    let result = NotificationDiff.diff(desired: [planned("a", at: 500)], pendingIds: ["a"], pendingFireDates: ["a": Date(timeIntervalSince1970: 100)])
    #expect(result.add.map(\.identifier) == ["a"])
    #expect(result.removeIds == ["a"])
}

@Test func nyPlanLaggsTill() {
    let result = NotificationDiff.diff(desired: [planned("a", at: 100), planned("b", at: 200)], pendingIds: ["a"], pendingFireDates: ["a": Date(timeIntervalSince1970: 100)])
    #expect(result.add.map(\.identifier) == ["b"])
    #expect(result.removeIds.isEmpty)
}

@Test func vantandeUtanKantTidErsattsEftersomTidenOkandIKontrollen() {
    let result = NotificationDiff.diff(desired: [planned("a", at: 100)], pendingIds: ["a"], pendingFireDates: [:])
    #expect(result.add.map(\.identifier) == ["a"])
    #expect(result.removeIds == ["a"])
}

@Test func andradTextErsatterNotisen() {
    let result = NotificationDiff.diff(
        desired: [planned("a", at: 100, body: "Nytt namn")],
        pendingIds: ["a"],
        pendingFireDates: ["a": Date(timeIntervalSince1970: 100)],
        pendingBodies: ["a": "Gammalt namn"]
    )
    #expect(result.add.map(\.identifier) == ["a"])
    #expect(result.removeIds == ["a"])
}

@Test func bladdraEnSekundTraffarInteSomAndring() {
    let result = NotificationDiff.diff(desired: [planned("a", at: 100.4)], pendingIds: ["a"], pendingFireDates: ["a": Date(timeIntervalSince1970: 100)])
    #expect(result.add.isEmpty && result.removeIds.isEmpty)
}

@Test func baraEgnaIdentifierareKannsIgen() {
    let own = "\(key.fileName)-2026-11-09"
    #expect(NotificationDiff.isOwn(identifier: own))
    #expect(!NotificationDiff.isOwn(identifier: "annan-notis"))
    #expect(!NotificationDiff.isOwn(identifier: "\(key.fileName)-inte-ett-datum"))
    #expect(!NotificationDiff.isOwn(identifier: "abc-2026-11-09"))
    #expect(!NotificationDiff.isOwn(identifier: ""))
}

@Test func behalletNotisSomLiggerFramforTasInteBort() {
    let now = Date(timeIntervalSince1970: 1000)
    let result = NotificationDiff.diff(desired: [], pendingIds: ["a", "b"], pendingFireDates: ["a": Date(timeIntervalSince1970: 2000), "b": Date(timeIntervalSince1970: 2000)], retain: ["a"], now: now)
    // Bara den som ska stå kvar behålls. Den andra tas bort som vanligt.
    #expect(result.removeIds == ["b"])
    #expect(result.add.isEmpty)
}

@Test func behalletNotisMedPasseradTidEllerOkandTidTasBort() {
    let now = Date(timeIntervalSince1970: 1000)
    let result = NotificationDiff.diff(desired: [], pendingIds: ["a", "b"], pendingFireDates: ["a": Date(timeIntervalSince1970: 900)], retain: ["a", "b"], now: now)
    #expect(result.removeIds == ["a", "b"])
}

@Test func behalletNotisErsattsNarPlanenHarEnNyTid() {
    let now = Date(timeIntervalSince1970: 1000)
    let result = NotificationDiff.diff(desired: [planned("a", at: 3000)], pendingIds: ["a"], pendingFireDates: ["a": Date(timeIntervalSince1970: 2000)], retain: ["a"], now: now)
    #expect(result.add.map(\.identifier) == ["a"])
    #expect(result.removeIds == ["a"])
}
