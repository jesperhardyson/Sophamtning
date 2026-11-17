import Testing
import Foundation
@testable import SophamtningKit

// MARK: Avkodning

private func fixtureJSON() throws -> [String: Any] {
    let url = try #require(Bundle.module.url(forResource: "adress", withExtension: "json", subdirectory: "Fixtures"))
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func decode(_ object: [String: Any]) throws -> AddressResponse {
    try JSONDecoder().decode(AddressResponse.self, from: JSONSerialization.data(withJSONObject: object))
}

private var rutter: [String: Any] { [
    "id": "nya-rutter-2026", "title": "Hämtrutterna läggs om", "text": "Schemat kan bli fel.",
    "url": NSNull(), "validFrom": "2026-11-17", "validTo": "2027-03-31",
] }

@Test func adressvaretMedMeddelanden() throws {
    var json = try fixtureJSON()
    var withUrl = rutter
    withUrl["id"] = "mer"
    withUrl["url"] = "https://www.avestavatten.se/rutter"
    json["messages"] = [rutter, withUrl]
    let response = try decode(json)
    #expect(response.messages.count == 2)
    let first = try #require(response.messages.first)
    #expect(first.id == "nya-rutter-2026")
    #expect(first.title == "Hämtrutterna läggs om")
    #expect(first.url == nil)
    #expect(first.validFrom == DayDate("2026-11-17"))
    #expect(first.validTo == DayDate("2027-03-31"))
    #expect(response.messages[1].url == URL(string: "https://www.avestavatten.se/rutter"))
}

@Test func adressvaretUtanMeddelandenGerTomLista() throws {
    var json = try fixtureJSON()
    json["messages"] = nil
    #expect(try decode(json).messages.isEmpty)
    json["messages"] = NSNull()
    #expect(try decode(json).messages.isEmpty)
    json["messages"] = "trasigt"
    let broken = try decode(json)
    #expect(broken.messages.isEmpty)
    // Resten av svaret är kvar.
    #expect(!broken.events.isEmpty)
}

@Test func ettTrasigtMeddelandeFallerInteDeAndra() throws {
    var json = try fixtureJSON()
    json["messages"] = [["id": "utan-datum", "title": "x", "text": "y"], rutter]
    #expect(try decode(json).messages.map(\.id) == ["nya-rutter-2026"])
}

@Test func sparatSchemaFranForeFaltetGarAttLasa() throws {
    var json = try fixtureJSON()
    json["messages"] = nil
    let old: [String: Any] = ["response": json, "fetchedAt": 0]
    let cached = try JSONDecoder().decode(CachedSchedule.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(cached.response?.messages == [])
}

// MARK: Vilka som gäller

private func message(_ id: String, from: String = "2026-11-17", to: String = "2027-03-31") -> SourceMessage {
    SourceMessage(id: id, title: "Rubrik \(id)", text: "Text", url: nil, validFrom: DayDate(from)!, validTo: DayDate(to)!)
}

@Test func gallerMellanForstaOchSistaDagen() {
    let m = message("a", from: "2026-11-17", to: "2026-11-30")
    let input = [(source: "avesta", messages: [m])]
    #expect(SourceMessages.active(in: input, today: DayDate("2026-11-16")!).isEmpty)
    #expect(SourceMessages.active(in: input, today: DayDate("2026-11-17")!).count == 1)
    #expect(SourceMessages.active(in: input, today: DayDate("2026-11-30")!).count == 1)
    #expect(SourceMessages.active(in: input, today: DayDate("2026-12-01")!).isEmpty)
}

@Test func sammaMeddelandeHosTvaAdresserBlirEtt() {
    let input = [(source: "avesta", messages: [message("a")]), (source: "avesta", messages: [message("a")])]
    #expect(SourceMessages.active(in: input, today: DayDate("2026-11-20")!).count == 1)
}

@Test func sammaIdHosTvaKallorBlirTva() {
    let input = [(source: "avesta", messages: [message("a")]), (source: "sater", messages: [message("a")])]
    let active = SourceMessages.active(in: input, today: DayDate("2026-11-20")!)
    #expect(active.map(\.source) == ["avesta", "sater"])
    #expect(Set(active.map(\.key)).count == 2)
}

@Test func ordnasEfterStartdagOchId() {
    let input = [(source: "avesta", messages: [message("b", from: "2026-11-10"), message("c", from: "2026-11-01"), message("a", from: "2026-11-10")])]
    #expect(SourceMessages.active(in: input, today: DayDate("2026-11-20")!).map(\.message.id) == ["c", "a", "b"])
}

// MARK: Minnet

@Test func minnetKodasMedKallanSomNyckel() throws {
    var memory = SourceMessageMemory()
    let key = SourceMessageKey(source: "avesta", id: "nya-rutter-2026")
    memory.markSeen([key])
    memory.dismiss(key)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: [String: [String]]])
    #expect(json == ["avesta": ["seen": ["nya-rutter-2026"], "dismissed": ["nya-rutter-2026"]]])
    let back = try JSONDecoder().decode(SourceMessageMemory.self, from: JSONEncoder().encode(memory))
    #expect(back.isSeen(key))
    #expect(back.isDismissed(key))
    #expect(!back.isSeen(SourceMessageKey(source: "sater", id: "nya-rutter-2026")))
}

@Test func settOchStangtArSkilda() {
    var memory = SourceMessageMemory()
    let key = SourceMessageKey(source: "avesta", id: "a")
    memory.markSeen([key])
    memory.markSeen([key])
    #expect(memory.isSeen(key))
    #expect(!memory.isDismissed(key))
}

@Test func osedda() {
    var memory = SourceMessageMemory()
    let active = SourceMessages.active(in: [(source: "avesta", messages: [message("a"), message("b")])], today: DayDate("2026-11-20")!)
    memory.markSeen([active[0].key])
    #expect(SourceMessages.unseen(active, memory: memory).map(\.message.id) == ["b"])
}

@Test func minnetILagringen() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kallmeddelanden-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LocalStore(directory: dir)
    guard case .missing = store.sourceMessageMemoryState() else { Issue.record("ska saknas"); return }
    var memory = SourceMessageMemory()
    memory.markSeen([SourceMessageKey(source: "avesta", id: "a")])
    try store.setSourceMessageMemory(memory)
    guard case .value(let read) = store.sourceMessageMemoryState() else { Issue.record("ska gå att läsa"); return }
    #expect(read == memory)
    try Data("{trasig".utf8).write(to: dir.appendingPathComponent("source-messages.json"))
    guard case .unreadable = store.sourceMessageMemoryState() else { Issue.record("ska vara oläslig"); return }
}

// MARK: Inställningen

@Test func installningenArPaFranBorjanOchIGamlaFiler() throws {
    #expect(ReminderSettings().sourceMessagesOn)
    let old = #"{"eveningOn":true,"morningOn":false,"reminderMinutes":1080,"liveActivityOn":false}"#
    let settings = try JSONDecoder().decode(ReminderSettings.self, from: Data(old.utf8))
    #expect(settings.sourceMessagesOn)
    var off = ReminderSettings()
    off.sourceMessagesOn = false
    let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(off))
    #expect(!back.sourceMessagesOn)
}

@Test func textenUnderReglaget() {
    #expect(ReminderSettingsTexts.sourceMessagesFooter(authorized: true) == "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna.")
    #expect(ReminderSettingsTexts.sourceMessagesFooter(authorized: false) == "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna. Notiser är avstängda för appen i iOS.")
}
