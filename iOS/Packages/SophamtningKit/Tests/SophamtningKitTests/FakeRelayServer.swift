import Foundation
import Synchronization
@testable import SophamtningKit

/// Brevlådan i minnet, med samma regler som `Server/src/household.ts` för det som appen märker.
final class FakeRelayServer: RelayTransport {
    enum Mode: Sendable, Equatable { case normal, offline, status(Int) }

    struct Participant { var id: String, secret: String, isOwner: Bool, name: String? = nil, removed = false }
    struct Household {
        var id: String
        var seq = 1
        var ended = false
        var participants: [Participant] = []
        var records: [(wire: RecordWire, seq: Int)] = []
        var deletions: [(name: String, seq: Int)] = []
        var invites: [String: (purpose: String, expires: Date)] = [:]
        var migrationInvited = false
        var createdAt: Date
        var prunedSeq = 0
        var devices: [String: String] = [:]
    }

    struct Inner {
        var mode: Mode = .normal
        /// Sökvägar som svarar med en annan status, till exempel för att avbryta mitt i ett flöde.
        var failing: [String: Int] = [:]
        var migration = false
        var households: [String: Household] = [:]
        var requests: [String] = []
        var bodies: [String] = []
        var listeners: [(household: String, continuation: AsyncStream<Int>.Continuation)] = []
        var counter: UInt8 = 0
        var now = Date(timeIntervalSince1970: 1_795_000_000)
    }

    let inner = Mutex(Inner())

    var mode: Mode {
        get { inner.withLock { $0.mode } }
        set { inner.withLock { $0.mode = newValue } }
    }

    var requests: [String] { inner.withLock { $0.requests } }

    func change(_ body: (inout Inner) -> Void) { inner.withLock { body(&$0) } }

    func household(_ id: String) -> Household? { inner.withLock { $0.households[id] } }

    /// Allt servern har tagit emot som text, för att pröva att inget läsbart skickas.
    var everything: String { inner.withLock { ($0.requests + $0.bodies).joined(separator: "\n") } }

    func send(_ request: RelayRequest) async throws -> RelayResponse {
        await Task.yield()
        return try inner.withLock { inner in
            inner.requests.append("\(request.method) \(request.path)")
            inner.bodies.append(String(decoding: request.body ?? Data(), as: UTF8.self))
            switch inner.mode {
            case .offline: throw URLError(.notConnectedToInternet)
            case .status(let status): return RelayResponse(status: status, body: Data("<html>".utf8))
            case .normal: break
            }
            for (path, status) in inner.failing where "\(request.method) \(request.path)".contains(path) {
                return RelayResponse(status: status, body: Data(#"{"error":"x"}"#.utf8))
            }
            return Self.handle(request, &inner)
        }
    }

    func signals(householdId: String, authorization: String) -> AsyncStream<Int> {
        AsyncStream { continuation in
            inner.withLock { $0.listeners.append((householdId, continuation)) }
            continuation.yield(0)
        }
    }

    // MARK: Regler

    private static func handle(_ request: RelayRequest, _ inner: inout Inner) -> RelayResponse {
        let parts = request.path.split(separator: "?")[0].split(separator: "/").map(String.init)
        let query = request.path.split(separator: "?").dropFirst().first.map(String.init) ?? ""
        let body = (request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        if request.path == "/config" { return json(200, ["migration": inner.migration]) }
        guard parts.first == "households" else { return error(404, "not_found") }
        if parts.count == 1 {
            let id = random(16, &inner), participant = random(16, &inner), secret = random(32, &inner)
            inner.households[id] = Household(id: id, participants: [Participant(id: participant, secret: secret, isOwner: true)], createdAt: inner.now)
            return json(201, ["householdId": id, "participantId": participant, "participantSecret": secret])
        }
        let id = parts[1]
        guard var household = inner.households[id] else { return error(404, "not_found") }
        let route = "\(request.method) \(parts.dropFirst(2).first ?? "")"
        let before = household.seq
        let response = handle(route, Array(parts.dropFirst(3)), query, body, request, &household, &inner)
        inner.households[id] = household
        if household.seq != before {
            for listener in inner.listeners where listener.household == id { listener.continuation.yield(household.seq) }
        }
        return response
    }

    private static func handle(_ route: String, _ rest: [String], _ query: String, _ body: [String: Any], _ request: RelayRequest, _ household: inout Household, _ inner: inout Inner) -> RelayResponse {
        if route == "POST join" {
            guard !household.ended, let invite = household.invites[body["inviteToken"] as? String ?? ""], invite.expires > inner.now else { return error(404, "invite_invalid") }
            guard household.participants.filter({ !$0.removed }).count < 10 else { return error(409, "full") }
            let participant = random(16, &inner), secret = random(32, &inner)
            household.participants.append(Participant(id: participant, secret: secret, isOwner: false))
            household.seq += 1
            return json(201, ["participantId": participant, "participantSecret": secret])
        }
        if household.ended { return error(410, "ended") }
        let credentials = (request.headers["Authorization"] ?? "").dropFirst("Bearer ".count).split(separator: ".").map(String.init)
        guard credentials.count == 2, let index = household.participants.firstIndex(where: { $0.id == credentials[0] && $0.secret == credentials[1] }) else { return error(401, "unauthorized") }
        let me = household.participants[index]
        if me.removed { return error(403, "removed") }

        switch route {
        case "DELETE ":
            guard me.isOwner else { return error(403, "forbidden") }
            household.ended = true
            household.seq += 1
            return RelayResponse(status: 204)
        case "POST invites":
            guard me.isOwner else { return error(403, "forbidden") }
            let purpose = body["purpose"] as? String ?? ""
            if purpose == "migration" {
                guard !household.migrationInvited, inner.now.timeIntervalSince(household.createdAt) <= 86_400 else { return error(409, "migration_unavailable") }
                household.migrationInvited = true
            }
            let token = random(32, &inner)
            let expires = inner.now.addingTimeInterval(purpose == "migration" ? 90 * 86_400 : 7 * 86_400)
            household.invites[token] = (purpose, expires)
            return json(201, ["inviteToken": token, "expiresAt": RelayDate.format(expires)])
        case "DELETE invites":
            guard me.isOwner else { return error(403, "forbidden") }
            household.invites = household.invites.filter { $0.value.purpose != "invite" }
            return RelayResponse(status: 204)
        case "GET changes":
            let since = Int(query.replacingOccurrences(of: "since=", with: "")) ?? 0
            let full = since == 0 || since < household.prunedSeq || since > household.seq
            let from = full ? 0 : since
            let wire = ChangesWire(
                seq: household.seq, full: full,
                participants: household.participants.filter { !$0.removed }.map { ParticipantWire(id: $0.id, isOwner: $0.isOwner, joinedAt: RelayDate.format(inner.now), name: $0.name) },
                records: household.records.filter { $0.seq > from }.map(\.wire),
                deleted: full ? [] : household.deletions.filter { $0.seq > from }.map(\.name)
            )
            return RelayResponse(status: 200, body: try! JSONEncoder().encode(wire))
        case "PUT records":
            guard request.headers["If-None-Match"] == "*" else { return error(428, "precondition_required") }
            if let existing = household.records.first(where: { $0.wire.name == rest[0] }) {
                return RelayResponse(status: 409, body: try! JSONEncoder().encode(ErrorWire(error: "conflict", record: existing.wire)))
            }
            let data = body["data"] as? String ?? ""
            guard household.records.count < 200, data.utf8.count <= 8192 else { return error(413, "too_large") }
            household.seq += 1
            household.deletions.removeAll { $0.name == rest[0] }
            let wire = RecordWire(name: rest[0], kind: body["kind"] as! String, data: data, by: me.id, at: RelayDate.format(inner.now), expiresAt: body["expiresAt"] as? String)
            household.records.append((wire, household.seq))
            return RelayResponse(status: 201, body: try! JSONEncoder().encode(wire))
        case "DELETE records":
            guard household.records.contains(where: { $0.wire.name == rest[0] }) else { return RelayResponse(status: 204) }
            household.seq += 1
            household.records.removeAll { $0.wire.name == rest[0] }
            household.deletions.append((rest[0], household.seq))
            return RelayResponse(status: 204)
        case "PUT participants" where rest == ["me", "name"]:
            household.participants[index].name = body["data"] as? String
            household.seq += 1
            return RelayResponse(status: 204)
        case "PUT participants" where rest.count == 3 && rest[1] == "devices":
            household.devices[rest[2]] = "\(me.id) \(body["token"] as? String ?? "")"
            return RelayResponse(status: 204)
        case "DELETE participants":
            guard me.isOwner || rest[0] == me.id else { return error(403, "forbidden") }
            if me.isOwner, rest[0] == me.id { return error(409, "owner_cannot_leave") }
            if let target = household.participants.firstIndex(where: { $0.id == rest[0] && !$0.removed }) {
                household.participants[target].removed = true
                household.seq += 1
            }
            return RelayResponse(status: 204)
        default:
            return error(404, "not_found")
        }
    }

    private static func random(_ count: Int, _ inner: inout Inner) -> String {
        inner.counter += 1
        return Data(repeating: inner.counter, count: count).base64URL
    }

    private static func json(_ status: Int, _ body: [String: Any]) -> RelayResponse {
        RelayResponse(status: status, body: try! JSONSerialization.data(withJSONObject: body))
    }

    private static func error(_ status: Int, _ code: String) -> RelayResponse {
        json(status, ["error": code])
    }
}

final class InMemoryCredentialStore: HouseholdCredentialStore {
    private struct Failure: Error {}
    private let inner: Mutex<(value: HouseholdCredentials?, failing: Bool)>

    init(_ value: HouseholdCredentials? = nil) { inner = Mutex((value, false)) }

    var failing: Bool {
        get { inner.withLock { $0.failing } }
        set { inner.withLock { $0.failing = newValue } }
    }

    private func access<T>(_ body: (inout HouseholdCredentials?) -> T) throws -> T {
        try inner.withLock {
            if $0.failing { throw Failure() }
            return body(&$0.value)
        }
    }

    func load() throws -> HouseholdCredentials? { try access { $0 } }
    func save(_ credentials: HouseholdCredentials) throws { try access { $0 = credentials } }
    func delete() throws { try access { $0 = nil } }
}
