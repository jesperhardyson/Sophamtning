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

public struct ReminderSettings: Hashable, Codable, Sendable {
    /// Minuter efter midnatt i Europe/Stockholm. 1080 är 18:00.
    public var reminderMinutes: Int
    public var liveActivityOn: Bool
    /// Förslaget om påminnelse efter första adressen har visats och besvarats, eller en påminnelse har slagits på.
    public var reminderOfferShown: Bool

    public init(reminderMinutes: Int = 1080, liveActivityOn: Bool = false, reminderOfferShown: Bool = false) {
        self.reminderMinutes = reminderMinutes
        self.liveActivityOn = liveActivityOn
        self.reminderOfferShown = reminderOfferShown
    }

    private enum CodingKeys: String, CodingKey {
        case reminderMinutes, liveActivityOn, reminderOfferShown
    }

    /// Inställningar sparade före `reminderOfferShown` saknar fältet och läses som att förslaget inte har visats.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminderMinutes = try container.decode(Int.self, forKey: .reminderMinutes)
        liveActivityOn = try container.decode(Bool.self, forKey: .liveActivityOn)
        reminderOfferShown = try container.decodeIfPresent(Bool.self, forKey: .reminderOfferShown) ?? false
    }

    /// Giltigt är 15:00 till 23:00 i steg om 15 minuter.
    public static func isValid(minutes: Int) -> Bool {
        (900...1380).contains(minutes) && minutes % 15 == 0
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
