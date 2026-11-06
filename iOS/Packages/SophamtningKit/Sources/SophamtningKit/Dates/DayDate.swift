import Foundation

/// Ett kalenderdatum utan klockslag, kodat som "YYYY-MM-DD".
public struct DayDate: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Tolkar exakt "YYYY-MM-DD". Ogiltiga datum ger `nil`.
    public init?(_ iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let candidate = DayDate(year: year, month: month, day: day)
        // Kalendern rullar över ogiltiga datum (30 februari), så ett lyckat varv tillbaka krävs.
        guard let date = candidate.noon, StockholmClock.today(now: date) == candidate else { return nil }
        self = candidate
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func adding(days: Int) -> DayDate {
        StockholmClock.today(now: StockholmClock.calendar.date(byAdding: .day, value: days, to: noon!)!)
    }

    /// Antal dagar från detta datum till `other`. Negativt om `other` ligger före.
    public func days(until other: DayDate) -> Int {
        StockholmClock.calendar.dateComponents([.day], from: noon!, to: other.noon!).day!
    }

    public static func < (lhs: DayDate, rhs: DayDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = DayDate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ogiltigt datum: \(text)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    /// Klockan 12 svensk tid. Mitt på dagen kan en omställning aldrig flytta datumet.
    private var noon: Date? {
        StockholmClock.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}
