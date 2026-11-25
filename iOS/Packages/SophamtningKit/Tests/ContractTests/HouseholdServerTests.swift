import Foundation
import SophamtningKit
import Synchronization
import Testing

/// Synken mot den riktiga brevlådan, lokalt. Körs bara för hand:
///
///     cd Server && npx wrangler dev --port 8799 --var LOCAL_ONLY_NO_JURISDICTION:1
///     HUSHALL_LOCAL=http://localhost:8799/v1 swift test --filter HouseholdServerTests
private let base = ProcessInfo.processInfo.environment["HUSHALL_LOCAL"]

private struct LocalTransport: RelayTransport {
    func send(_ request: RelayRequest) async throws -> RelayResponse {
        var urlRequest = URLRequest(url: URL(string: base! + request.path)!)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        return RelayResponse(status: (response as! HTTPURLResponse).statusCode, body: data)
    }

    func signals(householdId: String, authorization: String) -> AsyncStream<Int> {
        AsyncStream { continuation in
            var request = URLRequest(url: URL(string: base! + "/households/\(householdId)/socket")!)
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request)
            socket.resume()
            let task = Task {
                while case .string(let text)? = try? await socket.receive() {
                    let seq = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Int])?["seq"] ?? 0
                    continuation.yield(seq)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                socket.cancel()
            }
        }
    }
}

private final class MemoryStore: HouseholdCredentialStore {
    private let value = Mutex<HouseholdCredentials?>(nil)
    func load() throws -> HouseholdCredentials? { value.withLock { $0 } }
    func save(_ credentials: HouseholdCredentials) throws { value.withLock { $0 = credentials } }
    func delete() throws { value.withLock { $0 = nil } }
}

private func phone() -> RelayHouseholdSync {
    let store = LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(22)
    return RelayHouseholdSync(transport: LocalTransport(), credentials: MemoryStore(), store: store, deviceId: { String(id) })
}

private func state(_ sync: RelayHouseholdSync) async -> HouseholdState {
    var iterator = sync.states().makeAsyncIterator()
    return await iterator.next()!
}

@Test(.enabled(if: base != nil)) func hushalletMotDenRiktigaServern() async throws {
    let jesper = phone(), sofie = phone()
    let key = AddressKey(source: "avesta-vatten", id: "Övre Ågatan 3|12")
    let address = SavedAddress(
        key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adresser/avesta-vatten/%C3%96vre%203%7C12")!, street: "Övre Ågatan 3", locality: "Avesta",
        kommun: "Avesta", detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, addedAt: Date(timeIntervalSinceReferenceDate: 785_000_000)
    )
    let entry = PlacedOut(key: key, date: StockholmClock.today(now: Date()).adding(days: 2))

    try await jesper.create(myName: "Jesper")
    try await jesper.share(address)
    await jesper.registerDevice(token: String(repeating: "ab", count: 32), environment: "sandbox")
    let link = try #require(HouseholdInviteLink(url: try await jesper.invite()))
    try await sofie.join(link, myName: "Sofie")
    #expect(await state(sofie).addresses.map(\.address) == [address])
    #expect(await state(sofie).participants.map(\.name) == ["Jesper", "Sofie"])

    // Jesper ser bocken via signalen, utan att själv hämta.
    jesper.startSignals()
    try await Task.sleep(for: .milliseconds(300))
    try await sofie.mark(entry)
    for _ in 0..<100 where await state(jesper).marks.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
    #expect(await state(jesper).marks.map(\.placedOut) == [entry])
    #expect(await state(jesper).marks.map(\.isPending) == [false])
    jesper.stopSignals()

    // Den första vinner, och Ångra gäller båda.
    try await jesper.mark(entry)
    let sofieId = await state(sofie).myId
    #expect(await state(jesper).marks.map(\.by) == [sofieId])
    try await jesper.unmark(entry)
    await sofie.fetchChanges()
    #expect(await state(sofie).marks.isEmpty)

    // Ogiltig inbjudan, borttagen och avslutat.
    try await jesper.revokeInvites()
    await #expect(throws: HouseholdMembershipError.inviteInvalid) { try await phone().join(link, myName: nil) }
    try await jesper.remove(participantId: try #require(sofieId))
    await sofie.fetchChanges()
    #expect(await state(sofie).status == .removed)
    #expect(await state(jesper).participants.map(\.name) == ["Jesper"])
    try await jesper.end()
    #expect(await state(jesper) == .empty)
}
