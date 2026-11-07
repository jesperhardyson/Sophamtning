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
    /// Adress och datum för Live Activities som faktiskt finns hos systemet (väntande eller pågående). Saknar standardvärde med avsikt.
    public let existingActivities: Set<PlacedOut>
    /// Adress och datum där aktiviteten bevisligen syntes (pågående sedd eller lyckad direktstart). Då behövs ingen reservnotis. Saknar
    /// standardvärde med avsikt: glöms den skickas en onödig andra påminnelse.
    public let shownActivities: Set<PlacedOut>
    /// Aktiviteternas egna starttider, så att reserven räknas från den start som faktiskt gäller. Saknas en post används
    /// påminnelsetiden i inställningarna.
    public let activityStarts: [PlacedOut: Date]

    public init(addresses: [PlannerAddress], settings: ReminderSettings, placedOut: Set<PlacedOut>, now: Date, liveActivitiesAllowed: Bool, existingActivities: Set<PlacedOut>, shownActivities: Set<PlacedOut>, activityStarts: [PlacedOut: Date] = [:]) {
        self.addresses = addresses
        self.settings = settings
        self.placedOut = placedOut
        self.now = now
        self.liveActivitiesAllowed = liveActivitiesAllowed
        self.existingActivities = existingActivities
        self.shownActivities = shownActivities
        self.activityStarts = activityStarts
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

    /// Identifieraren för adressens notis ett visst datum. Reservnotisen har samma, så att den ersätter den vanliga.
    public static func identifier(key: AddressKey, date: DayDate) -> String {
        "\(key.fileName)-\(date.iso)"
    }

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
    public let warning: String?
    /// Sant när Utställt är tryckt. Aktiviteten visar då en bock i några sekunder innan den försvinner.
    public let placedOut: Bool

    /// Längsta varning. Allt innehåll måste rymmas inom systemets 4 KB, och höjden på låsskärmen är begränsad.
    static let maxWarningLength = 200

    public init(addressName: String, dateText: String, shortDateText: String, fractions: [ActivityFraction], estimated: Bool, warning: String?, placedOut: Bool = false) {
        self.addressName = addressName
        self.dateText = dateText
        self.shortDateText = shortDateText
        self.fractions = fractions
        self.estimated = estimated
        self.warning = warning.map { text in
            text.count > Self.maxWarningLength ? text.prefix(Self.maxWarningLength - 1) + "…" : text
        }
        self.placedOut = placedOut
    }

    private enum CodingKeys: String, CodingKey {
        case addressName, dateText, shortDateText, fractions, estimated, warning, placedOut
    }

    /// Äldre innehåll, till exempel en schemalagd aktivitet från en tidigare version, saknar `placedOut` och får `false`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addressName = try container.decode(String.self, forKey: .addressName)
        dateText = try container.decode(String.self, forKey: .dateText)
        shortDateText = try container.decode(String.self, forKey: .shortDateText)
        fractions = try container.decode([ActivityFraction].self, forKey: .fractions)
        estimated = try container.decode(Bool.self, forKey: .estimated)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        placedOut = try container.decodeIfPresent(Bool.self, forKey: .placedOut) ?? false
    }

    /// Samma innehåll med Utställt tryckt.
    public func markedPlacedOut() -> PickupActivityContent {
        PickupActivityContent(addressName: addressName, dateText: dateText, shortDateText: shortDateText, fractions: fractions, estimated: estimated, warning: warning, placedOut: true)
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
    static let maxAddressNameLength = 60
    static let defaultReminderMinutes = 1080

    /// Reservnotisen kommer så här många minuter efter aktivitetens start, om aktiviteten inte syntes eller bekräftades.
    static let fallbackDelayMinutes = 45
    /// Senaste klockslag för reservnotisen, i minuter efter midnatt: 23:45. Påminnelsetiden stannar vid 23:00, så starten är
    /// aldrig senare än taket.
    static let fallbackLatestMinutes = 23 * 60 + 45

    static let fallbackTitle = "Har du ställt ut kärlen?"
    static let ordinaryTitle = "Ställ ut kärlen"

    /// Reservnotisens tid för en aktivitet som startar `start`: 45 minuter senare, högst 23:45 samma dag i svensk tid.
    static func fallbackDate(start: Date) -> Date {
        let latest = StockholmClock.date(on: StockholmClock.today(now: start), minutes: fallbackLatestMinutes)
        return min(start.addingTimeInterval(TimeInterval(fallbackDelayMinutes * 60)), latest)
    }

    /// Ogiltig tid ger standardtiden, så att en påminnelse aldrig hamnar på ett orimligt klockslag.
    private static func effectiveMinutes(_ settings: ReminderSettings) -> Int {
        ReminderSettings.isValid(minutes: settings.reminderMinutes) ? settings.reminderMinutes : defaultReminderMinutes
    }

    /// En tömningsdag, med händelser samma dag ihopslagna.
    private struct Pickup {
        let date: DayDate
        let fractions: [String]
        let estimated: Bool
        let warning: String?
    }

    public static func plan(_ input: PlannerInput) -> ReminderPlan {
        let today = StockholmClock.today(now: input.now)

        let entries = input.addresses

        let liveActivity = planLiveActivity(entries, input: input, today: today)
        let activitiesActive = input.settings.liveActivityOn && input.liveActivitiesAllowed
        let minutes = effectiveMinutes(input.settings)

        var notifications: [PlannedNotification] = []
        for entry in entries where entry.address.notificationsOn {
            guard let response = entry.schedule?.response else { continue }
            for pickup in pickups(in: response, today: today) {
                let id = PlacedOut(key: entry.address.key, date: pickup.date)
                if input.placedOut.contains(id) { continue }
                var fireDate = StockholmClock.date(on: pickup.date.adding(days: -1), minutes: minutes)
                var title = ordinaryTitle
                // Aktiviteten aviserar själv, men bara om den faktiskt finns hos systemet. Syntes den redan behövs ingen påminnelse
                // till. Annars ersätts notisen av en reserv efter starten, med samma identifierare, så att den aldrig blir dubbel.
                if activitiesActive, input.existingActivities.contains(id) {
                    if input.shownActivities.contains(id) { continue }
                    fireDate = fallbackDate(start: input.activityStarts[id] ?? fireDate)
                    title = fallbackTitle
                }
                guard fireDate > input.now else { continue }
                notifications.append(PlannedNotification(
                    identifier: PlannedNotification.identifier(key: entry.address.key, date: pickup.date),
                    fireDate: fireDate,
                    title: title,
                    body: body(addressName: entry.address.displayName, pickup: pickup, response: response),
                    key: entry.address.key,
                    pickupDate: pickup.date
                ))
            }
        }
        notifications.sort { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }

        return ReminderPlan(notifications: Array(notifications.prefix(maxNotifications)), liveActivity: liveActivity)
    }

    /// Notiser som står kvar när deras tid ligger framför även om planen inte längre innehåller dem. Gäller tömningar där den
    /// ordinarie notistiden har passerat, tömningen finns kvar i schemat och den varken är utställd eller bevisat visad:
    /// en väntande notis där är reserven, och tas den bort står tömningen utan påminnelse. Planeraren skapar aldrig en ny.
    /// Adresser med notiser avstängda ingår inte, så avstängda val tar fortfarande bort sina notiser.
    public static func retainable(_ input: PlannerInput) -> [String: PlacedOut] {
        let today = StockholmClock.today(now: input.now)
        let minutes = effectiveMinutes(input.settings)
        var result: [String: PlacedOut] = [:]
        for entry in input.addresses where entry.address.notificationsOn {
            guard let response = entry.schedule?.response else { continue }
            for pickup in pickups(in: response, today: today) {
                let id = PlacedOut(key: entry.address.key, date: pickup.date)
                if input.placedOut.contains(id) || input.shownActivities.contains(id) { continue }
                let ordinary = StockholmClock.date(on: pickup.date.adding(days: -1), minutes: minutes)
                if ordinary <= input.now { result[PlannedNotification.identifier(key: id.key, date: id.date)] = id }
            }
        }
        return result
    }

    private static func planLiveActivity(_ entries: [PlannerAddress], input: PlannerInput, today: DayDate) -> PlannedLiveActivity? {
        guard input.settings.liveActivityOn, input.liveActivitiesAllowed,
              let primary = entries.first(where: { $0.address.isPrimary }),
              let response = primary.schedule?.response
        else { return nil }

        let key = primary.address.key
        // Första tömning efter i dag som inte är utställd. På tömningsdagen gäller alltså nästa tömning.
        guard let next = pickups(in: response, today: today).first(where: {
            $0.date > today && !input.placedOut.contains(PlacedOut(key: key, date: $0.date))
        }) else { return nil }

        let start = StockholmClock.date(on: next.date.adding(days: -1), minutes: effectiveMinutes(input.settings))
        let isTomorrow = next.date == today.adding(days: 1)
        return PlannedLiveActivity(
            key: key,
            pickupDate: next.date,
            start: start,
            startsImmediately: isTomorrow && input.now >= start,
            content: content(of: next, address: primary.address, response: response)
        )
    }

    /// Innehållet för huvudadressens tömning ett visst datum, för en aktivitet som redan pågår. `nil` utan sådan tömning.
    public static func activityContent(on date: DayDate, input: PlannerInput) -> PickupActivityContent? {
        guard let primary = input.addresses.first(where: { $0.address.isPrimary }),
              let response = primary.schedule?.response,
              let pickup = pickups(in: response, today: date).first(where: { $0.date == date })
        else { return nil }
        return content(of: pickup, address: primary.address, response: response)
    }

    private static func content(of pickup: Pickup, address: SavedAddress, response: AddressResponse) -> PickupActivityContent {
        PickupActivityContent(
            addressName: String(address.displayName.prefix(maxAddressNameLength)),
            dateText: SwedishFormat.longDate(pickup.date, capitalized: true),
            shortDateText: SwedishFormat.shortDate(pickup.date),
            fractions: pickup.fractions.map { id in
                let info = ScheduleLogic.displayInfo(for: id, in: response.fractions)
                return ActivityFraction(id: id, name: info.name, short: info.short, color: info.color, icon: info.icon)
            },
            estimated: pickup.estimated,
            warning: pickup.warning
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
