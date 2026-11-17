import Foundation

/// Ett meddelande hos en källa. `id` är bara unikt inom källan, så källan ingår i nyckeln.
public struct SourceMessageKey: Hashable, Sendable {
    public let source: String
    public let id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }
}

/// Ett meddelande som gäller i dag, med källan det hör till.
public struct ActiveSourceMessage: Hashable, Sendable, Identifiable {
    public let source: String
    public let message: SourceMessage

    public init(source: String, message: SourceMessage) {
        self.source = source
        self.message = message
    }

    public var key: SourceMessageKey { SourceMessageKey(source: source, id: message.id) }
    public var id: String { "\(source)/\(message.id)" }
}

public enum SourceMessages {
    /// Meddelandena som gäller `today`, från de sparade adressernas svar. Samma meddelande hos flera adresser blir ett.
    /// Ordningen är `validFrom` och sedan `id`, som i API:t, och källan när två källor har samma.
    /// Datumen räknas om här, eftersom ett sparat svar kan vara äldre än meddelandets sista dag.
    public static func active(in sources: [(source: String, messages: [SourceMessage])], today: DayDate) -> [ActiveSourceMessage] {
        var seen: Set<SourceMessageKey> = []
        var result: [ActiveSourceMessage] = []
        for (source, messages) in sources {
            for message in messages where message.validFrom <= today && today <= message.validTo {
                let item = ActiveSourceMessage(source: source, message: message)
                if seen.insert(item.key).inserted { result.append(item) }
            }
        }
        return result.sorted {
            ($0.message.validFrom, $0.message.id, $0.source) < ($1.message.validFrom, $1.message.id, $1.source)
        }
    }

    /// De som inte är sedda än, i samma ordning.
    public static func unseen(_ active: [ActiveSourceMessage], memory: SourceMessageMemory) -> [ActiveSourceMessage] {
        active.filter { !memory.isSeen($0.key) }
    }

    /// Identifieraren för notisen. `NotificationDiff.isOwn` känner inte igen den, så planeringen tar aldrig bort notisen.
    public static func notificationId(_ key: SourceMessageKey) -> String {
        "kalla.\(key.source).\(key.id)"
    }
}

/// Sedda och stängda meddelanden, sparade i `source-messages.json` som `{ "<källa>": { "seen": [], "dismissed": [] } }`.
/// Sett betyder att meddelandet inte ska ge någon notis. Stängt betyder att kortet inte visas. Inget tas bort, eftersom
/// ett `id` aldrig återanvänds och filen förblir liten.
public struct SourceMessageMemory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var seen: [String] = []
        var dismissed: [String] = []
    }

    private var sources: [String: Entry]

    public init() { sources = [:] }

    public init(from decoder: Decoder) throws {
        sources = try decoder.singleValueContainer().decode([String: Entry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sources)
    }

    public func isSeen(_ key: SourceMessageKey) -> Bool {
        sources[key.source]?.seen.contains(key.id) ?? false
    }

    public func isDismissed(_ key: SourceMessageKey) -> Bool {
        sources[key.source]?.dismissed.contains(key.id) ?? false
    }

    public mutating func markSeen(_ keys: [SourceMessageKey]) {
        for key in keys where !isSeen(key) {
            sources[key.source, default: Entry()].seen.append(key.id)
        }
    }

    public mutating func dismiss(_ key: SourceMessageKey) {
        guard !isDismissed(key) else { return }
        sources[key.source, default: Entry()].dismissed.append(key.id)
    }
}
