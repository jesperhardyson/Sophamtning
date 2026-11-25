import Foundation
import Testing
@testable import SophamtningKit

/// Bjuda in, gå med, ta bort och avsluta genom modellen, mot brevlådan i minnet.
@MainActor
private final class Person {
    let model: AppModel
    let sync: RelayHouseholdSync
    let store: LocalStore

    init(_ server: FakeRelayServer, name: String? = nil) async {
        store = LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        sync = RelayHouseholdSync(transport: server, credentials: InMemoryCredentialStore(), store: store, deviceId: { "enhet" })
        model = AppModel(api: NoAPI(), store: store, household: sync)
        model.startHousehold()
        if let name { _ = await model.setHouseholdName(name) }
    }

    /// Väntar tills modellen har fått läget.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }

    func settle() async { try? await Task.sleep(for: .milliseconds(60)) }
}

private struct NoAPI: SoporAPI {
    func address(url: URL) async throws -> AddressResponse { throw APIError.network }
    func search(query: String, source: String?) async throws -> SearchResponse { throw APIError.network }
    func areas(place: String) async throws -> SearchResponse { throw APIError.network }
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse { throw APIError.network }
    func sources() async throws -> SourcesResponse { throw APIError.network }
}

@Test @MainActor func inbjudanGerLank() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    #expect(!jesper.model.canManageMembers)
    let first = try #require(await jesper.model.inviteURL())
    #expect(HouseholdInviteLink(url: first) != nil)
    await jesper.until { jesper.model.inHousehold }
    #expect(jesper.model.canManageMembers)
    #expect(jesper.model.household.participants.map(\.name) == ["Jesper"])
    // En till inbjudan gäller samma hushåll.
    let second = try #require(await jesper.model.inviteURL())
    #expect(first != second)
    #expect(server.inner.withLock { $0.households.count } == 1)
}

@Test @MainActor func inbjudanKraverNamn() async {
    let server = FakeRelayServer()
    let jesper = await Person(server)
    #expect(await jesper.model.inviteURL() == nil)
    #expect(server.requests.isEmpty)
}

@Test @MainActor func inbjudanUtanNatGerFel() async {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    server.mode = .offline
    #expect(await jesper.model.inviteURL() == nil)
    #expect(jesper.model.householdNotice == "Hushållet kunde inte uppdateras just nu")
    #expect(!jesper.model.inHousehold)
}

@Test @MainActor func gaMedViaLankOppnarArket() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await sofie.model.receiveInvite(link)
    await sofie.until { sofie.model.householdSheetRequested }
    #expect(sofie.model.householdNotice == "Du är med i Jespers hushåll. Adresser som delas visas på hemskärmen.")
    #expect(sofie.model.household.participants.map(\.name) == ["Jesper", "Sofie"])
    #expect(sofie.model.householdMembersText == nil)
    #expect(!sofie.model.canManageMembers)
    await jesper.model.fetchHouseholdChanges()
    await jesper.until { jesper.model.householdMembersText == "Sofie gick med i hushållet" }
}

@Test @MainActor func agareUtanNamnGerValkomstUtanNamn() {
    #expect(HouseholdTexts.welcome(ownerName: HouseholdTexts.unknownName) == "Du är med i hushållet. Adresser som delas visas på hemskärmen.")
}

@Test @MainActor func lankTillSammaHushallFragarInte() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await jesper.until { jesper.model.inHousehold }
    await jesper.model.receiveInvite(link)
    #expect(jesper.model.pendingInvite == nil)
    #expect(jesper.model.householdNotice == nil)
    #expect(server.requests.last?.contains("changes") == true)
}

@Test @MainActor func inbjudanNarJagArMedFragarForst() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let kim = await Person(server, name: "Kim")
    let sofie = await Person(server, name: "Sofie")
    let first = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    let second = try #require(await kim.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await sofie.model.receiveInvite(first)
    await sofie.until { sofie.model.inHousehold }
    await sofie.model.receiveInvite(second)
    #expect(sofie.model.pendingInvite == second)
    await sofie.model.answerInvite(leaveFirst: false)
    #expect(sofie.model.pendingInvite == nil)
    #expect(sofie.sync.isCurrent(first))

    await sofie.model.receiveInvite(second)
    await sofie.model.answerInvite(leaveFirst: true)
    await sofie.until { sofie.model.household.participants.map(\.name) == ["Kim", "Sofie"] }
    #expect(sofie.sync.isCurrent(second))

    // Går det inte att lämna accepteras ingenting.
    await sofie.model.receiveInvite(first)
    server.mode = .offline
    await sofie.model.answerInvite(leaveFirst: true)
    #expect(sofie.sync.isCurrent(second))
    #expect(sofie.model.householdNotice == "Hushållet kunde inte uppdateras just nu")
}

@Test @MainActor func ogiltigInbjudanVisarText() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await jesper.until { jesper.model.canManageMembers }
    #expect(await jesper.model.revokeInvites())
    await sofie.model.receiveInvite(link)
    #expect(sofie.model.householdNotice == "Inbjudan gäller inte längre. Be om en ny.")
    #expect(sofie.model.householdSheetRequested)
    await sofie.settle()
    #expect(!sofie.model.inHousehold)
}

@Test @MainActor func fulltHushallVisarText() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    for _ in 0..<9 {
        let person = await Person(server, name: "X")
        await person.model.receiveInvite(link)
    }
    let sofie = await Person(server, name: "Sofie")
    await sofie.model.receiveInvite(link)
    #expect(sofie.model.householdNotice == "Hushållet är fullt.")
}

@Test @MainActor func taBortDeltagareForsvinnerUrListan() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await sofie.model.receiveInvite(link)
    await sofie.until { sofie.model.inHousehold }
    await jesper.model.fetchHouseholdChanges()
    await jesper.until { jesper.model.household.participants.count == 2 }
    jesper.model.clearMembersNotice()
    let id = try #require(sofie.model.household.myId)

    #expect(await !sofie.model.removeParticipant(id))
    #expect(await jesper.model.removeParticipant(id))
    await jesper.until { jesper.model.household.participants.map(\.name) == ["Jesper"] }
    await jesper.settle()
    // Den som själv tog bort någon behöver ingen rad om det.
    #expect(jesper.model.householdMembersText == nil)
    await sofie.model.fetchHouseholdChanges()
    await sofie.until { sofie.model.householdNotice == HouseholdTexts.leftNote }
}

@Test @MainActor func taBortUtanNatGerFel() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await sofie.model.receiveInvite(link)
    await jesper.model.fetchHouseholdChanges()
    await jesper.until { jesper.model.household.participants.count == 2 }
    server.mode = .offline
    #expect(await !jesper.model.removeParticipant(try #require(sofie.model.household.myId)))
    #expect(await !jesper.model.revokeInvites())
    #expect(jesper.model.household.participants.count == 2)
    #expect(jesper.model.householdNotice == "Hushållet kunde inte uppdateras just nu")
}

@Test @MainActor func medlemKanInteHanteraMedlemmar() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await sofie.model.receiveInvite(link)
    await sofie.until { sofie.model.inHousehold }
    #expect(!sofie.model.canManageMembers)
    #expect(await sofie.model.inviteURL() == nil)
    #expect(await !sofie.model.revokeInvites())
}

@Test @MainActor func utanMedlemskapFinnsIngenHantering() async {
    let store = LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let model = AppModel(api: NoAPI(), store: store)
    #expect(!model.canManageMembers)
    #expect(!model.invitesWithLink)
    #expect(await model.inviteURL() == nil)
}

@Test func texternaForMedlemmar() {
    #expect(HouseholdTexts.inviteMessage == "Gå med i mitt hushåll i Sophämtning")
    #expect(HouseholdTexts.inviteMore == "Bjud in fler")
    #expect(HouseholdTexts.revokeInvites == "Gör inbjudningar ogiltiga")
    #expect(HouseholdTexts.revokeInvitesFooter == "Länkar du har skickat gäller i 7 dagar.")
    #expect(HouseholdTexts.removeParticipant == "Ta bort ur hushållet")
    #expect(HouseholdTexts.inviteInvalid == "Inbjudan gäller inte längre. Be om en ny.")
    #expect(HouseholdTexts.householdFull == "Hushållet är fullt.")
    #expect(HouseholdTexts.removeConfirm(name: "Kim") == "Ta bort Kim ur hushållet?")
    #expect(HouseholdTexts.removeConfirmMessage(name: "Kim") == "Kim behåller adresserna som egna.")
    #expect(HouseholdTexts.intro == "Dela adresser med dem du bor med. Ni ser samma schema, och när någon ställer ut kärlen syns det för alla. Hushållet krypteras på era telefoner, och bara ni kan läsa det.")
}

@Test func minnetHanterarMedlemmar() async throws {
    let sync = InMemoryHouseholdSync(state: .empty)
    try await sync.create(myName: "Alex")
    let url = try await sync.invite()
    #expect(sync.isCurrent(try #require(HouseholdInviteLink(url: url))))
    #expect(sync.managesMembers)
    sync.simulateRemote { $0.participants.append(HouseholdParticipant(id: "kim", name: "Kim", isOwner: false)) }
    try await sync.remove(participantId: "kim")
    var iterator = sync.states().makeAsyncIterator()
    let state = await iterator.next()
    #expect(state?.participants.map(\.name) == ["Alex"])
    #expect(state?.role == .owner)
    try await sync.end()
    let other = HouseholdInviteLink(householdId: Data(repeating: 9, count: 16).base64URL, inviteToken: "t", householdKey: Data(repeating: 1, count: 32))
    #expect(!sync.isCurrent(other))
    try await sync.join(other, myName: "Alex")
    #expect(sync.isCurrent(other))
}

// MARK: Efter granskningen

@Test @MainActor func utgangenLankGorInteAttJagForlorarHushallet() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let kim = await Person(server, name: "Kim")
    _ = await jesper.model.inviteURL()
    await jesper.until { jesper.model.canManageMembers }
    let link = try #require(await kim.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await kim.until { kim.model.canManageMembers }
    #expect(await kim.model.revokeInvites())
    await jesper.model.receiveInvite(link)
    #expect(jesper.model.pendingInvite != nil)
    await jesper.model.answerInvite(leaveFirst: true)
    await jesper.settle()
    #expect(jesper.model.householdNotice == HouseholdTexts.inviteInvalid)
    #expect(jesper.model.canManageMembers)
    #expect(server.inner.withLock { $0.households.values.allSatisfy { !$0.ended } })
}

@Test @MainActor func fraganSagerAttAgarensHushallAvslutas() {
    #expect(HouseholdTexts.leaveFirst(isOwner: false) == "Du är redan med i ett hushåll. Lämna det för att gå med i det här?")
    #expect(HouseholdTexts.leaveFirst(isOwner: true) == "Du äger redan ett hushåll. Går du med i det här avslutas ditt för alla.")
    #expect(HouseholdTexts.leaveFirstAction(isOwner: false) == "Lämna och gå med")
    #expect(HouseholdTexts.leaveFirstAction(isOwner: true) == "Avsluta och gå med")
}

@Test @MainActor func nyDeltagareAnmalsForstMedNamn() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    let sofie = await Person(server, name: "Sofie")
    let link = try #require(await jesper.model.inviteURL().flatMap { HouseholdInviteLink(url: $0) })
    await jesper.until { jesper.model.canManageMembers }
    // Namnet kommer i ett eget anrop, som här inte kommer fram direkt.
    server.change { $0.failing["PUT"] = 500 }
    await sofie.model.receiveInvite(link)
    await jesper.model.fetchHouseholdChanges()
    await jesper.until { jesper.model.household.participants.count == 2 }
    await jesper.settle()
    #expect(jesper.model.householdMembersText == nil)
    server.change { $0.failing = [:] }
    await sofie.model.fetchHouseholdChanges()
    await jesper.model.fetchHouseholdChanges()
    await jesper.until { jesper.model.householdMembersText == "Sofie gick med i hushållet" }
}

@Test @MainActor func langtNamnKortasOchSkickasEnGang() async throws {
    let server = FakeRelayServer()
    let long = String(repeating: "Å\"", count: 300)
    let jesper = await Person(server, name: long)
    _ = await jesper.model.inviteURL()
    await jesper.until { jesper.model.inHousehold }
    for _ in 0..<5 { await jesper.model.fetchHouseholdChanges() }
    await jesper.settle()
    #expect(jesper.model.householdName.count <= 40)
    #expect(jesper.model.household.myName == jesper.model.householdName)
    #expect(server.requests.filter { $0.contains("/name") }.count == 1)
}

@Test @MainActor func nekatNamnSkickasInteOmOchOm() async throws {
    let server = FakeRelayServer()
    let jesper = await Person(server, name: "Jesper")
    _ = await jesper.model.inviteURL()
    await jesper.until { jesper.model.inHousehold }
    server.change { $0.failing["/name"] = 413 }
    _ = await jesper.model.setHouseholdName("Jeppe")
    for _ in 0..<5 { await jesper.model.fetchHouseholdChanges() }
    await jesper.settle()
    #expect(server.requests.filter { $0.contains("/name") }.count <= 3)
}
