import Foundation

/// En ändring som väntar på att skickas. Ordningen behålls, så att Ångra efter ett tryck också skickas efter det.
enum RelayPendingChange: Hashable, Codable, Sendable {
    case share(SavedAddress, legacy: LegacyOrigin?)
    case unshare(AddressKey)
    case mark(PlacedOut, at: Date, legacy: LegacyOrigin?)
    case unmark(PlacedOut)
    case name(String, legacyId: String?)

    /// Postens namn innan det blir en HMAC. `nil` för mitt namn, som inte är en post.
    var logicalName: String? {
        switch self {
        case .share(let address, _): address.key.relayLogicalName
        case .unshare(let key): key.relayLogicalName
        case .mark(let placedOut, _, _): placedOut.relayLogicalName
        case .unmark(let placedOut): placedOut.relayLogicalName
        case .name: nil
        }
    }
}

extension RelayPendingChange {
    /// En ny post, som servern svarar på med posten.
    var isRecord: Bool {
        switch self {
        case .share, .mark: true
        case .unshare, .unmark, .name: false
        }
    }
}

extension AddressKey {
    var relayLogicalName: String { fileName }
}

extension PlacedOut {
    var relayLogicalName: String { "\(key.fileName)-\(date.iso)" }
}

/// Kön på disk, `household-relay-pending.json`. Den hör till ett hushåll och slängs när det byts.
struct RelayPendingQueue: Hashable, Codable, Sendable {
    static let fileName = "household-relay-pending.json"

    struct Item: Hashable, Codable, Sendable {
        var id: UUID
        var change: RelayPendingChange
    }

    var householdId: String
    var items: [Item] = []

    mutating func append(_ change: RelayPendingChange) {
        // Bara mitt senaste namn behöver skickas.
        if case .name(_, let legacyId) = change {
            var kept = legacyId
            items.removeAll { item in
                guard case .name(_, let earlier) = item.change else { return false }
                kept = kept ?? earlier
                return true
            }
            if case .name(let name, _) = change { items.append(Item(id: UUID(), change: .name(name, legacyId: kept))) }
            return
        }
        items.append(Item(id: UUID(), change: change))
    }
}

/// Kopian av hushållet på disk, `household-relay.json`.
struct RelayCache: Hashable, Codable, Sendable {
    static let fileName = "household-relay.json"

    struct Stored: Hashable, Codable, Sendable {
        var wire: RecordWire
        /// Innehållet, som det senast gick att läsa. `nil` när posten aldrig har gått att läsa.
        var content: Content?
    }

    enum Content: Hashable, Codable, Sendable {
        case address(AddressPlaintext)
        case mark(MarkPlaintext)
    }

    var householdId: String
    var myId: String
    var seq = 0
    /// En hämtning av allt har lyckats. Innan dess skickas bara lägen med fel.
    var complete = false
    var participants: [HouseholdParticipant] = []
    var myName: String?
    var records: [String: Stored] = [:]

    var role: HouseholdRole {
        guard let me = participants.first(where: { $0.id == myId }) else { return .none }
        return me.isOwner ? .owner : .member
    }

    // MARK: Ändringar från servern

    mutating func apply(_ changes: ChangesWire, crypto: HouseholdCrypto) {
        let known = records
        if changes.full { records = [:] }
        for wire in changes.records { store(wire, known: known[wire.name], crypto: crypto) }
        for name in changes.deleted { records[name] = nil }
        let before = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        participants = changes.participants.map { wire in
            let plain = wire.name.flatMap { try? crypto.openName($0, participantId: wire.id) }.flatMap { try? JSONDecoder().decode(NamePlaintext.self, from: $0) }
            if wire.id == myId, let plain { myName = plain.name }
            // Ett namn som inte går att läsa behåller det som senast var känt.
            let name = plain?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? before[wire.id]?.name ?? ""
            return HouseholdParticipant(id: wire.id, name: name.isEmpty ? HouseholdTexts.unknownName : name, isOwner: wire.isOwner, legacyIds: plain?.legacyIds ?? before[wire.id]?.legacyIds ?? [])
        }
        seq = changes.seq
        complete = complete || changes.full
    }

    mutating func store(_ wire: RecordWire, crypto: HouseholdCrypto) {
        store(wire, known: records[wire.name], crypto: crypto)
    }

    private mutating func store(_ wire: RecordWire, known: Stored?, crypto: HouseholdCrypto) {
        records[wire.name] = Stored(wire: wire, content: Self.content(of: wire, crypto: crypto) ?? known?.content)
    }

    /// Poster som inte gick att läsa förut, till exempel från en nyare version, prövas igen när appen startar.
    mutating func rereadUnreadable(crypto: HouseholdCrypto) {
        for (name, stored) in records where stored.content == nil {
            records[name]?.content = Self.content(of: stored.wire, crypto: crypto)
        }
    }

    private static func content(of wire: RecordWire, crypto: HouseholdCrypto) -> Content? {
        guard let kind = RelayRecordKind(rawValue: wire.kind), let plain = try? crypto.open(wire.data, name: wire.name, kind: kind) else { return nil }
        switch kind {
        case .address: return (try? JSONDecoder().decode(AddressPlaintext.self, from: plain)).map(Content.address)
        case .mark: return (try? JSONDecoder().decode(MarkPlaintext.self, from: plain)).map(Content.mark)
        }
    }

    // MARK: Läget

    /// Hushållet som det visas: kopian, med ändringarna som väntar ovanpå.
    func state(pending: [RelayPendingChange], status: HouseholdStatus) -> HouseholdState {
        var addresses: [AddressKey: HouseholdAddress] = [:]
        var marks: [PlacedOut: HouseholdMark] = [:]
        for stored in records.values {
            switch stored.content {
            case .address(let plain):
                addresses[plain.address.key] = HouseholdAddress(address: plain.address, addedBy: author(plain.legacy?.by ?? stored.wire.by))
            case .mark(let plain):
                let at = plain.legacy?.at ?? RelayDate.parse(stored.wire.at) ?? Date(timeIntervalSince1970: 0)
                marks[plain.placedOut] = HouseholdMark(placedOut: plain.placedOut, by: author(plain.legacy?.by ?? stored.wire.by), at: at, isPending: false)
            case nil:
                continue
            }
        }
        var people = participants
        var name = myName
        for change in pending {
            switch change {
            case .share(let address, let legacy):
                // Den första vinner, också innan servern har svarat.
                if addresses[address.key] == nil { addresses[address.key] = HouseholdAddress(address: address, addedBy: author(legacy?.by ?? myId)) }
            case .unshare(let key):
                addresses[key] = nil
            case .mark(let placedOut, let at, let legacy):
                if marks[placedOut] == nil { marks[placedOut] = HouseholdMark(placedOut: placedOut, by: author(legacy?.by ?? myId), at: legacy?.at ?? at, isPending: true) }
            case .unmark(let placedOut):
                marks[placedOut] = nil
            case .name(let mine, _):
                name = mine
                if let index = people.firstIndex(where: { $0.id == myId }) { people[index].name = mine }
            }
        }
        people.sort { lhs, rhs in
            if lhs.isOwner != rhs.isOwner { return lhs.isOwner }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        return HouseholdState(
            role: role,
            myId: myId,
            participants: people,
            addresses: addresses.values.sorted { ($0.address.addedAt, $0.address.key.fileName) < ($1.address.addedAt, $1.address.key.fileName) },
            marks: marks.values.sorted { ($0.placedOut.date.iso, $0.placedOut.key.fileName) < ($1.placedOut.date.iso, $1.placedOut.key.fileName) },
            status: status,
            myName: name
        )
    }

    /// Den som hade ett id i iCloud är nu en annan deltagare. Hittas ingen står id:t kvar, och visas som "någon".
    private func author(_ id: String) -> String {
        participants.first { $0.legacyIds.contains(id) }?.id ?? id
    }
}
