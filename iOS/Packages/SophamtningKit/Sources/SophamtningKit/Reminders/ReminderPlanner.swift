import Foundation

/// En adress med sitt sparade schema, som indata till planeraren.
public struct PlannerAddress: Sendable {
    public let address: SavedAddress
    public let schedule: CachedSchedule?

    public init(address: SavedAddress, schedule: CachedSchedule?) {
        self.address = address
        self.schedule = schedule
    }
}

public struct PlannerInput: Sendable {
    public let addresses: [PlannerAddress]
    public let settings: ReminderSettings
    public let placedOut: Set<PlacedOut>
    public let now: Date
    public let liveActivitiesAllowed: Bool

    public init(addresses: [PlannerAddress], settings: ReminderSettings, placedOut: Set<PlacedOut>, now: Date, liveActivitiesAllowed: Bool) {
        self.addresses = addresses
        self.settings = settings
        self.placedOut = placedOut
        self.now = now
        self.liveActivitiesAllowed = liveActivitiesAllowed
    }
}

public struct PlannedNotification: Equatable, Sendable {
    /// `"<key.fileName>-<iso-datum>"`.
    public let identifier: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let key: AddressKey
    public let pickupDate: DayDate

    public init(identifier: String, fireDate: Date, title: String, body: String, key: AddressKey, pickupDate: DayDate) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.key = key
        self.pickupDate = pickupDate
    }
}

public struct ActivityFraction: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let short: String
    public let color: String
    public let icon: String

    public init(id: String, name: String, short: String, color: String, icon: String) {
        self.id = id
        self.name = name
        self.short = short
        self.color = color
        self.icon = icon
    }
}

/// Innehållet i Live Activityn. Texterna får inte säga "i morgon", eftersom innehållet inte uppdateras under natten.
public struct PickupActivityContent: Codable, Hashable, Sendable {
    public let addressName: String
    /// Till exempel "Måndag 9 november". "ca" läggs till av vyerna när `estimated` är sant.
    public let dateText: String
    /// Till exempel "Mån 9 nov".
    public let shortDateText: String
    public let fractions: [ActivityFraction]
    public let estimated: Bool

    public init(addressName: String, dateText: String, shortDateText: String, fractions: [ActivityFraction], estimated: Bool) {
        self.addressName = addressName
        self.dateText = dateText
        self.shortDateText = shortDateText
        self.fractions = fractions
        self.estimated = estimated
    }
}

public struct PlannedLiveActivity: Equatable, Sendable {
    public let key: AddressKey
    public let pickupDate: DayDate
    /// Kvällen före tömningen, på påminnelsetiden.
    public let start: Date
    /// Sant när starttiden har passerat men tömningen fortfarande är i morgon.
    public let startsImmediately: Bool
    public let content: PickupActivityContent

    public init(key: AddressKey, pickupDate: DayDate, start: Date, startsImmediately: Bool, content: PickupActivityContent) {
        self.key = key
        self.pickupDate = pickupDate
        self.start = start
        self.startsImmediately = startsImmediately
        self.content = content
    }
}

public struct ReminderPlan: Equatable, Sendable {
    public let notifications: [PlannedNotification]
    public let liveActivity: PlannedLiveActivity?

    public init(notifications: [PlannedNotification], liveActivity: PlannedLiveActivity?) {
        self.notifications = notifications
        self.liveActivity = liveActivity
    }

    public static let empty = ReminderPlan(notifications: [], liveActivity: nil)
}

/// Beräknar önskat läge för notiser och Live Activity. Ren funktion: ingen sidoeffekt, och telefonens tidszon läses aldrig.
public enum ReminderPlanner {
    /// Taket håller appen under iOS gräns för väntande notiser.
    static let maxNotifications = 60

    /// En tömningsdag, med händelser samma dag ihopslagna.
    private struct Pickup {
        let date: DayDate
        let fractions: [String]
        let estimated: Bool
        let warning: String?
    }

    public static func plan(_ input: PlannerInput) -> ReminderPlan {
        let today = StockholmClock.today(now: input.now)

        // Samma adress två gånger ger samma identifierare, så första gäller.
        var seen = Set<AddressKey>()
        let entries = input.addresses.filter { seen.insert($0.address.key).inserted }

        let liveActivity = planLiveActivity(entries, input: input, today: today)

        var notifications: [PlannedNotification] = []
        for entry in entries where entry.address.notificationsOn {
            guard let response = entry.schedule?.response else { continue }
            for pickup in pickups(in: response, today: today) {
                if let live = liveActivity, live.key == entry.address.key, live.pickupDate == pickup.date { continue }
                let fireDate = StockholmClock.date(on: pickup.date.adding(days: -1), minutes: input.settings.reminderMinutes)
                guard fireDate > input.now else { continue }
                notifications.append(PlannedNotification(
                    identifier: "\(entry.address.key.fileName)-\(pickup.date.iso)",
                    fireDate: fireDate,
                    title: "Ställ ut kärlen",
                    body: body(addressName: entry.address.displayName, pickup: pickup, response: response),
                    key: entry.address.key,
                    pickupDate: pickup.date
                ))
            }
        }
        notifications.sort { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }

        return ReminderPlan(notifications: Array(notifications.prefix(maxNotifications)), liveActivity: liveActivity)
    }

    private static func planLiveActivity(_ entries: [PlannerAddress], input: PlannerInput, today: DayDate) -> PlannedLiveActivity? {
        guard input.settings.liveActivityOn, input.liveActivitiesAllowed,
              let primary = entries.first(where: { $0.address.isPrimary }),
              let response = primary.schedule?.response
        else { return nil }

        let key = primary.address.key
        // Utställda tömningar hoppas över, och nästa används i stället.
        guard let next = pickups(in: response, today: today).first(where: { !input.placedOut.contains(PlacedOut(key: key, date: $0.date)) }),
              next.date >= today.adding(days: 1)
        else { return nil }

        let start = StockholmClock.date(on: next.date.adding(days: -1), minutes: input.settings.reminderMinutes)
        let isTomorrow = next.date == today.adding(days: 1)
        return PlannedLiveActivity(
            key: key,
            pickupDate: next.date,
            start: start,
            startsImmediately: isTomorrow && input.now >= start,
            content: PickupActivityContent(
                addressName: primary.address.displayName,
                dateText: SwedishFormat.longDate(next.date, capitalized: true),
                shortDateText: SwedishFormat.shortDate(next.date),
                fractions: next.fractions.map { id in
                    let info = ScheduleLogic.displayInfo(for: id, in: response.fractions)
                    return ActivityFraction(id: id, name: info.name, short: info.short, color: info.color, icon: info.icon)
                },
                estimated: next.estimated
            )
        )
    }

    /// Kommande tömningar från och med `today`, en per datum, utan tomma fraktionslistor.
    private static func pickups(in response: AddressResponse, today: DayDate) -> [Pickup] {
        var byDate: [DayDate: Pickup] = [:]
        for event in ScheduleLogic.upcoming(response.events, today: today) where !event.fractions.isEmpty {
            guard let existing = byDate[event.date] else {
                byDate[event.date] = Pickup(date: event.date, fractions: unique(event.fractions), estimated: event.estimated, warning: cleaned(event.warning))
                continue
            }
            // Två händelser samma dag slås ihop, så att ingen fraktion eller varning tappas.
            let warnings = [existing.warning, cleaned(event.warning)].compactMap { $0 }
            byDate[event.date] = Pickup(
                date: event.date,
                fractions: unique(existing.fractions + event.fractions),
                estimated: existing.estimated || event.estimated,
                warning: warnings.isEmpty ? nil : unique(warnings).joined(separator: " ")
            )
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    private static func body(addressName: String, pickup: Pickup, response: AddressResponse) -> String {
        let names = pickup.fractions.map { ScheduleLogic.displayInfo(for: $0, in: response.fractions).name }
        let date = SwedishFormat.estimated(SwedishFormat.longDate(pickup.date, capitalized: false), pickup.estimated)
        var text = "\(addressName): \(joined(names)) töms \(date)."
        if let warning = pickup.warning { text += " \(warning)" }
        return text
    }

    /// "A", "A och B", "A, B och C".
    private static func joined(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " och " + last
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func cleaned(_ warning: String?) -> String? {
        guard let trimmed = warning?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
