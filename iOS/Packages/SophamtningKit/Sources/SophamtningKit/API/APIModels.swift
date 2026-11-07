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
    /// Områdets tömningar kring datumet i `/omraden?tomning=`. `nil` när anropet saknar datum.
    public let pickups: Pickups?
    /// Områdets detaljer från `/omraden`. `nil` för adresser, i äldre svar och när fältet är trasigt.
    public let area: AreaDetails?

    public init(id: String, street: String, locality: String, kommun: String, source: String, detail: String?, selection: String, notice: String?, areasUrl: URL?, url: URL, pickups: Pickups? = nil, area: AreaDetails? = nil) {
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
        self.pickups = pickups
        self.area = area
    }

    public var isArea: Bool { selection == "area" }
}

/// Det som webbens områdessida visar för ett område. Varje del kan saknas eller vara trasig, och då är den tom.
public struct AreaDetails: Codable, Hashable, Sendable {
    /// "Måndag, udda vecka".
    public let day: String
    /// "Område 1", eller `nil`.
    public let label: String?
    /// Platserna i området, i källans ordning.
    public let places: [String]
    /// Platser i området som har en annan dag, som meningar.
    public let otherDays: [String]
    /// Det som sökningen matchar på. Visas inte.
    public let searchTerms: [String]

    public init(day: String, label: String?, places: [String], otherDays: [String] = [], searchTerms: [String] = []) {
        self.day = day
        self.label = label
        self.places = places
        self.otherDays = otherDays
        self.searchTerms = searchTerms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = ((try? c.decodeIfPresent(String.self, forKey: .day)) ?? nil) ?? ""
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil
        places = ((try? c.decodeIfPresent([String].self, forKey: .places)) ?? nil) ?? []
        otherDays = ((try? c.decodeIfPresent([String].self, forKey: .otherDays)) ?? nil) ?? []
        searchTerms = ((try? c.decodeIfPresent([String].self, forKey: .searchTerms)) ?? nil) ?? []
    }
}

/// En källa som svarade i `/omraden`, med varför man väljer område och vart man vänder sig.
public struct AreaSource: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// "Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område."
    public let explanation: String?
    /// "Osäker? Fråga Avesta Vatten på 0226-64 55 00."
    public let help: String?

    public init(id: String, name: String, explanation: String?, help: String?) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.help = help
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        explanation = (try? c.decodeIfPresent(String.self, forKey: .explanation)) ?? nil
        help = (try? c.decodeIfPresent(String.self, forKey: .help)) ?? nil
    }
}

/// Tömningarna för ett område kring ett angivet datum.
public struct Pickups: Codable, Hashable, Sendable {
    /// Högst två, med angivet datum sist.
    public let previous: [DayDate]
    /// Räknas från angivet datum och kan alltså ha passerat. `nil` när schemat inte har fler datum.
    public let next: DayDate?

    public init(previous: [DayDate], next: DayDate?) {
        self.previous = previous
        self.next = next
    }
}

public struct SearchResponse: Codable, Hashable, Sendable {
    public let addresses: [SearchHit]
    /// Källor som inte svarade. En delvis sökning behåller ändå träffarna.
    public let failed: [String]
    /// Bara med `tomning`. `true`: datumet ligger inom schemat. `false`: utanför schemat.
    /// `nil`: kunde inte bedömas, eller anropet hade inget datum.
    public let dateCovered: Bool?
    /// Källorna som svarade i `/omraden`. Tom i `/sok`, i äldre svar och när fältet är trasigt.
    public let sources: [AreaSource]

    public init(addresses: [SearchHit], failed: [String], dateCovered: Bool? = nil, sources: [AreaSource] = []) {
        self.addresses = addresses
        self.failed = failed
        self.dateCovered = dateCovered
        self.sources = sources
    }
}

extension SearchResponse {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addresses = try c.decode([SearchHit].self, forKey: .addresses)
        failed = try c.decode([String].self, forKey: .failed)
        dateCovered = try c.decodeIfPresent(Bool.self, forKey: .dateCovered)
        // En trasig källa tas bort, och ett trasigt fält ger inga källor. Det får aldrig fälla områdena.
        let raw = (try? c.decodeIfPresent([Lenient<AreaSource>].self, forKey: .sources)) ?? nil
        sources = (raw ?? []).compactMap { item in item.value }
    }
}

/// Ett värde som får vara trasigt. Används där en trasig del inte ska fälla en lista.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
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
    /// Kontaktuppgifter, eller `nil` när inget är känt. Saknas fältet, som i äldre svar, är det också `nil`.
    public let contact: SourceContact?

    public init(id: String, name: String, url: URL, kommuner: [Kommun], testData: Bool, contact: SourceContact? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.kommuner = kommuner
        self.testData = testData
        self.contact = contact
    }

    /// Kommunerna källan täcker, med hela namnen: "Avesta kommun, Hedemora kommun och Säters kommun".
    public var kommunerText: String {
        let names = kommuner.map { kommunDisplayName($0.name) }.filter { !$0.isEmpty }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " och " + names[names.count - 1]
    }
}

/// Källans kontaktuppgifter från `/kallor`. Varje del kan saknas. `checkedAt` och `checkedUrl` visas inte.
public struct SourceContact: Codable, Hashable, Sendable {
    public struct Phone: Codable, Hashable, Sendable {
        /// Numret att ringa, "+46187279400".
        public let number: String?
        /// Numret som det visas, "018-727 94 00".
        public let display: String?

        public init(number: String?, display: String?) {
            self.number = number
            self.display = display
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = (try? c.decodeIfPresent(String.self, forKey: .number)) ?? nil
            display = (try? c.decodeIfPresent(String.self, forKey: .display)) ?? nil
        }
    }

    public let phone: Phone?
    public let email: String?
    public let page: URL?
    public let checkedAt: DayDate?
    public let checkedUrl: URL?

    public init(phone: Phone? = nil, email: String? = nil, page: URL? = nil, checkedAt: DayDate? = nil, checkedUrl: URL? = nil) {
        self.phone = phone
        self.email = email
        self.page = page
        self.checkedAt = checkedAt
        self.checkedUrl = checkedUrl
    }

    /// En trasig del ger bara att den delen saknas. Den får aldrig fälla källan eller listan.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phone = (try? c.decodeIfPresent(Phone.self, forKey: .phone)) ?? nil
        email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? nil
        page = (try? c.decodeIfPresent(URL.self, forKey: .page)) ?? nil
        checkedAt = (try? c.decodeIfPresent(DayDate.self, forKey: .checkedAt)) ?? nil
        checkedUrl = (try? c.decodeIfPresent(URL.self, forKey: .checkedUrl)) ?? nil
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

extension Source {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        kommuner = try c.decode([Kommun].self, forKey: .kommuner)
        testData = try c.decode(Bool.self, forKey: .testData)
        // Saknas, `null` eller trasig: ingen kontakt. Källan visas ändå.
        contact = (try? c.decodeIfPresent(SourceContact.self, forKey: .contact)) ?? nil
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
        // Ett trasigt värde (tom sträng, fel typ) ger ingen länk. Det får inte fälla hela sökresultatet.
        areasUrl = (try? c.decodeIfPresent(String.self, forKey: .areasUrl)).flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        url = try c.decode(URL.self, forKey: .url)
        // Trasiga tömningsdatum ger en träff utan datum. De får inte fälla träffen.
        pickups = (try? c.decodeIfPresent(Pickups.self, forKey: .pickups)).flatMap { $0 }
        // Trasiga detaljer ger dagens visning med `detail`. De får inte fälla träffen.
        area = (try? c.decodeIfPresent(AreaDetails.self, forKey: .area)).flatMap { $0 }
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
