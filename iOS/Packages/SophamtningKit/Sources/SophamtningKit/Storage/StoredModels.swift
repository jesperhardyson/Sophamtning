import Foundation
import CryptoKit

/// Nyckeln till en sparad adress. Id:t sparas som API:t levererade det och tolkas aldrig.
public struct AddressKey: Hashable, Codable, Sendable {
    public let source: String
    public let id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }

    /// SHA-256 av `source + "\0" + id` som hexadecimal text. Säkert som filnamn oavsett tecknen i id:t.
    public var fileName: String {
        let digest = SHA256.hash(data: Data((source + "\u{0}" + id).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct SavedAddress: Hashable, Codable, Sendable {
    public var key: AddressKey
    /// Adressens schema i API:t. Procentkodad och får inte kodas om.
    public var url: URL
    public var street: String
    public var locality: String
    public var kommun: String
    public var detail: String?
    public var selection: String
    public var displayName: String
    public var isPrimary: Bool
    public var notificationsOn: Bool
    public var addedAt: Date

    public init(key: AddressKey, url: URL, street: String, locality: String, kommun: String, detail: String?, selection: String, displayName: String, isPrimary: Bool, notificationsOn: Bool = false, addedAt: Date) {
        self.key = key
        self.url = url
        self.street = street
        self.locality = locality
        self.kommun = kommun
        self.detail = detail
        self.selection = selection
        self.displayName = displayName
        self.isPrimary = isPrimary
        self.notificationsOn = notificationsOn
        self.addedAt = addedAt
    }
}

/// Ett av valen för när en påminnelse kommer: kvällen före tömningen eller samma morgon.
public enum ReminderTiming: String, Codable, Sendable, CaseIterable {
    case eveningBefore, sameMorning

    /// Förvald tid i minuter efter midnatt: 18:00 eller 06:00.
    public var defaultMinutes: Int {
        switch self {
        case .eveningBefore: 1080
        case .sameMorning: 360
        }
    }

    /// Giltiga tider: 15:00–23:00 eller 05:00–09:00.
    var range: ClosedRange<Int> {
        switch self {
        case .eveningBefore: 900...1380
        case .sameMorning: 300...540
        }
    }

    /// Alla giltiga tider i ordning, i steg om 15 minuter.
    public var times: [Int] { Array(stride(from: range.lowerBound, through: range.upperBound, by: 15)) }
}

public struct ReminderSettings: Hashable, Codable, Sendable {
    /// Påminnelse kvällen före tömningen. På från början.
    public var eveningOn: Bool
    /// Påminnelse samma morgon som tömningen. Av från början. Minst ett av valen är alltid på.
    public var morningOn: Bool
    /// Kvällstiden, i minuter efter midnatt i Europe/Stockholm. 1080 är 18:00.
    public var reminderMinutes: Int
    /// Morgontiden, i minuter efter midnatt i Europe/Stockholm. 360 är 06:00. Båda sparas, så en avstängd tid finns kvar.
    public var morningMinutes: Int
    /// Vilket val Live Activity följer. Tiden för valet gäller också när notiserna för det är av.
    public var liveActivityTiming: ReminderTiming
    public var liveActivityOn: Bool
    /// Förslaget om påminnelse efter första adressen har visats och besvarats, eller en påminnelse har slagits på.
    public var reminderOfferShown: Bool

    public init(eveningOn: Bool = true, morningOn: Bool = false, reminderMinutes: Int = 1080, morningMinutes: Int = 360, liveActivityTiming: ReminderTiming = .eveningBefore, liveActivityOn: Bool = false, reminderOfferShown: Bool = false) {
        self.eveningOn = eveningOn
        self.morningOn = morningOn
        self.reminderMinutes = reminderMinutes
        self.morningMinutes = morningMinutes
        self.liveActivityTiming = liveActivityTiming
        self.liveActivityOn = liveActivityOn
        self.reminderOfferShown = reminderOfferShown
    }

    private enum CodingKeys: String, CodingKey {
        case eveningOn, morningOn, reminderMinutes, morningMinutes, liveActivityTiming, liveActivityOn, reminderOfferShown
        /// Det gamla enda valet. Läses men skrivs aldrig.
        case timing
    }

    /// Inställningar sparade före `reminderOfferShown` läses som att förslaget inte har visats. Sparade med det gamla enda valet
    /// (`timing`) läses valet som det enda påslagna och som Live Activity-val. Saknas det, eller är det okänt, till exempel från en
    /// senare version, läses det som kvällen före, så att inställningarna inte blir oläsliga. Är båda valen av blir kvällen på.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminderMinutes = try container.decode(Int.self, forKey: .reminderMinutes)
        liveActivityOn = try container.decode(Bool.self, forKey: .liveActivityOn)
        reminderOfferShown = try container.decodeIfPresent(Bool.self, forKey: .reminderOfferShown) ?? false
        morningMinutes = try container.decodeIfPresent(Int.self, forKey: .morningMinutes) ?? ReminderTiming.sameMorning.defaultMinutes
        let old = (try container.decodeIfPresent(String.self, forKey: .timing)).flatMap(ReminderTiming.init(rawValue:)) ?? .eveningBefore
        let evening = try container.decodeIfPresent(Bool.self, forKey: .eveningOn)
        let morning = try container.decodeIfPresent(Bool.self, forKey: .morningOn)
        if evening == nil && morning == nil {
            eveningOn = old == .eveningBefore
            morningOn = old == .sameMorning
        } else {
            eveningOn = evening ?? false
            morningOn = morning ?? false
        }
        if !eveningOn && !morningOn { eveningOn = true }
        liveActivityTiming = try container.decodeIfPresent(ReminderTiming.self, forKey: .liveActivityTiming) ?? old
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eveningOn, forKey: .eveningOn)
        try container.encode(morningOn, forKey: .morningOn)
        try container.encode(reminderMinutes, forKey: .reminderMinutes)
        try container.encode(morningMinutes, forKey: .morningMinutes)
        try container.encode(liveActivityTiming, forKey: .liveActivityTiming)
        try container.encode(liveActivityOn, forKey: .liveActivityOn)
        try container.encode(reminderOfferShown, forKey: .reminderOfferShown)
    }

    /// Giltigt är det valdas tider i steg om 15 minuter.
    public static func isValid(minutes: Int, for timing: ReminderTiming) -> Bool {
        timing.range.contains(minutes) && minutes % 15 == 0
    }

    /// Den sparade tiden för valet. En ogiltig sparad tid ger förvalet, så att en påminnelse aldrig hamnar på ett orimligt klockslag.
    public func minutes(for timing: ReminderTiming) -> Int {
        let minutes = timing == .eveningBefore ? reminderMinutes : morningMinutes
        return Self.isValid(minutes: minutes, for: timing) ? minutes : timing.defaultMinutes
    }

    public func isEnabled(_ timing: ReminderTiming) -> Bool {
        timing == .eveningBefore ? eveningOn : morningOn
    }

    /// Påslagna val i ordningen kväll, morgon. Aldrig tom: är båda av räknas kvällen.
    public var enabledTimings: [ReminderTiming] {
        let timings = ReminderTiming.allCases.filter(isEnabled)
        return timings.isEmpty ? [.eveningBefore] : timings
    }

    /// Värdet på raden Påminnelse i inställningarna.
    public var settingsValue: String {
        let timings = enabledTimings
        if timings.count == 2 {
            return "\(SwedishFormat.clock(minutes: minutes(for: .eveningBefore))) och \(SwedishFormat.clock(minutes: minutes(for: .sameMorning)))"
        }
        let timing = timings[0]
        let label = timing == .eveningBefore ? "Kvällen före" : "Samma morgon"
        return "\(label), \(SwedishFormat.clock(minutes: minutes(for: timing)))"
    }
}

public struct CachedSchedule: Equatable, Codable, Sendable {
    public var response: AddressResponse?
    public var fetchedAt: Date?
    public var lastAttemptAt: Date?
    public var lastError: APIError?

    public init(response: AddressResponse? = nil, fetchedAt: Date? = nil, lastAttemptAt: Date? = nil, lastError: APIError? = nil) {
        self.response = response
        self.fetchedAt = fetchedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }
}

/// Att soporna ställts ut för en adress och ett hämtdatum.
public struct PlacedOut: Hashable, Codable, Sendable {
    public var key: AddressKey
    public var date: DayDate

    public init(key: AddressKey, date: DayDate) {
        self.key = key
        self.date = date
    }
}

public struct CachedSources: Hashable, Codable, Sendable {
    public var response: SourcesResponse
    public var fetchedAt: Date
    /// Appens version och bygge när listan hämtades. En ny version hämtar listan direkt, så att fält som
    /// versionen visar för första gången syns utan att vänta ett dygn. `nil` i listor sparade före fältet.
    public var appVersion: String?

    public init(response: SourcesResponse, fetchedAt: Date, appVersion: String? = nil) {
        self.response = response
        self.fetchedAt = fetchedAt
        self.appVersion = appVersion
    }
}
