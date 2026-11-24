import Foundation

/// Felkoderna i protokollet. Bara `removed` och `ended` får ta bort hushållet i appen.
public enum RelayErrorCode: String, Codable, Sendable {
    case removed, ended, full, conflict
    case inviteInvalid = "invite_invalid"
    case notFound = "not_found"
}

// MARK: Klartext

/// Vem som skrev en post innan hushållet flyttades från iCloud, och när.
struct LegacyOrigin: Hashable, Codable, Sendable {
    var by: String
    var at: Date

    init(by: String, at: Date) {
        self.by = by
        self.at = at
    }

    private enum CodingKeys: String, CodingKey { case by, at }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        by = try container.decode(String.self, forKey: .by)
        let text = try container.decode(String.self, forKey: .at)
        guard let date = RelayDate.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: .at, in: container, debugDescription: "Ogiltig tid")
        }
        at = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(by, forKey: .by)
        try container.encode(RelayDate.format(at), forKey: .at)
    }
}

struct AddressPlaintext: Hashable, Codable, Sendable {
    var address: SavedAddress
    var legacy: LegacyOrigin?
}

struct MarkPlaintext: Hashable, Codable, Sendable {
    var source: String
    var id: String
    var date: DayDate
    var legacy: LegacyOrigin?

    var placedOut: PlacedOut { PlacedOut(key: AddressKey(source: source, id: id), date: date) }
}

struct NamePlaintext: Hashable, Codable, Sendable {
    var name: String
    var legacyIds: [String]?
}

// MARK: Servern

struct RecordWire: Hashable, Codable, Sendable {
    var name: String
    var kind: String
    var data: String
    var by: String
    var at: String
    var expiresAt: String?
}

struct ParticipantWire: Hashable, Codable, Sendable {
    var id: String
    var isOwner: Bool
    var joinedAt: String
    var name: String?
}

struct ChangesWire: Hashable, Codable, Sendable {
    var seq: Int
    var full: Bool
    var participants: [ParticipantWire]
    var records: [RecordWire]
    var deleted: [String]
}

struct CreatedWire: Codable, Sendable {
    var householdId: String
    var participantId: String
    var participantSecret: String
}

struct JoinedWire: Codable, Sendable {
    var participantId: String
    var participantSecret: String
}

struct InviteWire: Codable, Sendable {
    var inviteToken: String
    var expiresAt: String
}

struct ErrorWire: Codable, Sendable {
    var error: String
    var record: RecordWire?
}

struct ConfigWire: Codable, Sendable {
    var migration: Bool
}

/// Tidpunkter som ISO 8601 i UTC, med eller utan bråkdelar av sekunder.
enum RelayDate {
    static func parse(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
