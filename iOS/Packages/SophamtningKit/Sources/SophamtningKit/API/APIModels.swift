import Foundation

/// En träff i sökresultatet: en adress eller ett område.
public struct SearchHit: Codable, Hashable, Sendable {
    public let id: String
    public let street: String
    public let locality: String
    public let kommun: String
    public let source: String
    public let detail: String?
    /// "address" eller "area". Äldre svar saknar fältet, och då är det en adress.
    public let selection: String
    public let notice: String?
    public let areasUrl: URL?
    /// Adressens schema i API:t. Procentkodad och får inte kodas om.
    public let url: URL

    public init(id: String, street: String, locality: String, kommun: String, source: String, detail: String?, selection: String, notice: String?, areasUrl: URL?, url: URL) {
        self.id = id
        self.street = street
        self.locality = locality
        self.kommun = kommun
        self.source = source
        self.detail = detail
        self.selection = selection
        self.notice = notice
        self.areasUrl = areasUrl
        self.url = url
    }

    public var isArea: Bool { selection == "area" }
}

public struct SearchResponse: Codable, Hashable, Sendable {
    public let addresses: [SearchHit]
    /// Källor som inte svarade. En delvis sökning behåller ändå träffarna.
    public let failed: [String]

    public init(addresses: [SearchHit], failed: [String]) {
        self.addresses = addresses
        self.failed = failed
    }
}

/// Adressen i ett schemasvar.
public struct Address: Codable, Hashable, Sendable {
    public let id: String
    public let street: String
    public let locality: String
    public let kommun: String
    public let source: String
    public let detail: String?
    public let selection: String
    public let notice: String?

    public init(id: String, street: String, locality: String, kommun: String, source: String, detail: String?, selection: String, notice: String?) {
        self.id = id
        self.street = street
        self.locality = locality
        self.kommun = kommun
        self.source = source
        self.detail = detail
        self.selection = selection
        self.notice = notice
    }
}

/// Nästa hämtning för en fraktion. API:ts `daysUntil`, `isToday`, `isTomorrow` och `text`
/// avkodas inte, eftersom de blir fel så fort dagen byts.
public struct NextPickup: Codable, Hashable, Sendable {
    public let fraction: String
    public let name: String
    public let color: String
    public let date: DayDate
    public let estimated: Bool
    public let warning: String?

    public init(fraction: String, name: String, color: String, date: DayDate, estimated: Bool, warning: String?) {
        self.fraction = fraction
        self.name = name
        self.color = color
        self.date = date
        self.estimated = estimated
        self.warning = warning
    }
}

public struct Deviation: Codable, Hashable, Sendable {
    public let originalDate: DayDate?
    public let reason: String

    public init(originalDate: DayDate?, reason: String) {
        self.originalDate = originalDate
        self.reason = reason
    }
}

public struct PickupEvent: Codable, Hashable, Sendable {
    public let date: DayDate
    /// Fraktions-id. Mängden är öppen, så ett id kan saknas i `fractions`.
    public let fractions: [String]
    public let estimated: Bool
    public let deviation: Deviation?
    public let warning: String?
    public let labels: [String: String]

    public init(date: DayDate, fractions: [String], estimated: Bool, deviation: Deviation?, warning: String?, labels: [String: String]) {
        self.date = date
        self.fractions = fractions
        self.estimated = estimated
        self.deviation = deviation
        self.warning = warning
        self.labels = labels
    }
}

public struct Bin: Codable, Hashable, Sendable {
    public let fraction: String
    public let sizeLiters: Int?
    public let pickupsPerYear: Int?
    public let frequencyText: String?

    public init(fraction: String, sizeLiters: Int?, pickupsPerYear: Int?, frequencyText: String?) {
        self.fraction = fraction
        self.sizeLiters = sizeLiters
        self.pickupsPerYear = pickupsPerYear
        self.frequencyText = frequencyText
    }
}

public struct FractionInfo: Codable, Hashable, Sendable {
    public let name: String
    public let short: String
    public let color: String
    public let icon: String

    public init(name: String, short: String, color: String, icon: String) {
        self.name = name
        self.short = short
        self.color = color
        self.icon = icon
    }
}

public struct Links: Codable, Hashable, Sendable {
    public let ics: URL
    public let web: URL

    public init(ics: URL, web: URL) {
        self.ics = ics
        self.web = web
    }
}

public struct AddressResponse: Codable, Hashable, Sendable {
    public let today: DayDate
    public let address: Address
    public let next: [NextPickup]
    public let summary: String
    public let events: [PickupEvent]
    public let bins: [Bin]
    public let fractions: [String: FractionInfo]
    public let links: Links
    public let updatedAt: DayDate

    public init(today: DayDate, address: Address, next: [NextPickup], summary: String, events: [PickupEvent], bins: [Bin], fractions: [String: FractionInfo], links: Links, updatedAt: DayDate) {
        self.today = today
        self.address = address
        self.next = next
        self.summary = summary
        self.events = events
        self.bins = bins
        self.fractions = fractions
        self.links = links
        self.updatedAt = updatedAt
    }
}

public struct Kommun: Codable, Hashable, Sendable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct Source: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let kommuner: [Kommun]
    public let testData: Bool

    public init(id: String, name: String, url: URL, kommuner: [Kommun], testData: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.kommuner = kommuner
        self.testData = testData
    }
}

public struct SourcesResponse: Codable, Hashable, Sendable {
    public let sources: [Source]
    public let fractions: [String: FractionInfo]

    public init(sources: [Source], fractions: [String: FractionInfo]) {
        self.sources = sources
        self.fractions = fractions
    }
}

extension SearchHit {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        street = try c.decode(String.self, forKey: .street)
        locality = try c.decode(String.self, forKey: .locality)
        kommun = try c.decode(String.self, forKey: .kommun)
        source = try c.decode(String.self, forKey: .source)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? "address"
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        areasUrl = try c.decodeIfPresent(URL.self, forKey: .areasUrl)
        url = try c.decode(URL.self, forKey: .url)
    }
}

extension Address {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        street = try c.decode(String.self, forKey: .street)
        locality = try c.decode(String.self, forKey: .locality)
        kommun = try c.decode(String.self, forKey: .kommun)
        source = try c.decode(String.self, forKey: .source)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? "address"
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
    }
}

extension PickupEvent {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(DayDate.self, forKey: .date)
        fractions = try c.decode([String].self, forKey: .fractions)
        estimated = try c.decode(Bool.self, forKey: .estimated)
        deviation = try c.decodeIfPresent(Deviation.self, forKey: .deviation)
        warning = try c.decodeIfPresent(String.self, forKey: .warning)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
    }
}
