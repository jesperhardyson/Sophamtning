import Foundation

/// Hemskärmens innehåll, räknat från sparade adresser och scheman och given tid.
/// Allt räknas lokalt: dagar, datum och påminnelsetext kommer aldrig från sparade `next`-fält.
public struct HomeContent: Equatable, Sendable {
    public struct FractionItem: Equatable, Sendable, Identifiable {
        public let id: String
        public let info: FractionInfo
    }

    /// Nästa hämtning för en adress.
    public struct Pickup: Equatable, Sendable {
        public let date: DayDate
        public let daysUntil: Int
        public let estimated: Bool
        public let fractions: [FractionItem]
        /// "Om 3 dagar", "I morgon" eller "I dag", med "Ca" först när datumet är uppskattat.
        public let headline: String
        /// "Måndag 9 november", med "Ca" först när datumet är uppskattat.
        public let longDate: String
    }

    public enum Status: Equatable, Sendable {
        case upcoming(Pickup)
        /// Schemat finns men har inga hämtningar från och med i dag.
        case noUpcoming
        /// Schemat har inte hämtats än.
        case loading
        /// Schemat saknas och det senaste försöket misslyckades. Bara `notFound` betyder att adressen inte finns
        /// längre, alla andra fel är tekniska.
        case failed(APIError)
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public let key: AddressKey
        public let title: String
        public let subtitle: String
        public let status: Status
        /// Senaste försöket att uppdatera misslyckades, men ett äldre schema visas.
        public let refreshFailed: Bool
        /// Bara för huvudkortet. `nil` när det inte finns någon kommande hämtning.
        public let reminderText: String?
        /// Raden under adressen: "Ons 18 nov · om 12 dagar" eller en statustext.
        public let summary: String

        public var id: AddressKey { key }

        /// Alla fraktioner som text, så att VoiceOver kan läsa dem även när raden bara visar ikoner.
        public var accessibilityLabel: String {
            var parts = [title, subtitle, summary]
            if refreshFailed { parts.append("Kunde inte uppdateras, visar senast hämtade schema") }
            if case .upcoming(let pickup) = status {
                parts.append(pickup.fractions.map(\.info.name).joined(separator: ", "))
            }
            return parts.joined(separator: ", ")
        }
    }

    public let primary: Entry?
    public let others: [Entry]

    public static func make(addresses: [SavedAddress], schedules: [AddressKey: CachedSchedule], settings: ReminderSettings, now: Date, remindersAllowed: Bool = true, liveActivity: ExistingActivity? = nil, liveActivitiesEnabled: Bool = true) -> HomeContent {
        let today = StockholmClock.today(now: now)
        let primaryAddress = addresses.first(where: \.isPrimary) ?? addresses.first
        let primary = primaryAddress.map { address in
            entry(address, schedule: schedules[address.key], settings: settings, today: today, now: now, withReminder: true, remindersAllowed: remindersAllowed, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled)
        }
        let others = addresses
            .filter { $0.key != primaryAddress?.key }
            .map { entry($0, schedule: schedules[$0.key], settings: settings, today: today, now: now, withReminder: false, remindersAllowed: remindersAllowed, liveActivity: nil, liveActivitiesEnabled: liveActivitiesEnabled) }
        return HomeContent(primary: primary, others: others)
    }

    private static func entry(_ address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, today: DayDate, now: Date, withReminder: Bool, remindersAllowed: Bool, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool) -> Entry {
        let status = status(of: schedule, today: today)
        let refreshFailed = schedule?.response != nil && schedule?.lastError != nil
        var reminder: String?
        let summary: String
        switch status {
        case .upcoming(let pickup):
            summary = SwedishFormat.estimated(
                "\(SwedishFormat.shortDate(pickup.date)) · \(SwedishFormat.relative(days: pickup.daysUntil))",
                pickup.estimated
            )
            if withReminder {
                reminder = reminderText(notifications: address.notificationsOn && remindersAllowed, settings: settings, events: schedule?.response?.events ?? [], today: today, now: now, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled)
            }
        case .noUpcoming:
            summary = "Inga kommande hämtningar"
        case .loading:
            summary = "Hämtar schema…"
        case .failed(let error):
            summary = error == .notFound ? "Adressen hittas inte längre" : "Kunde inte hämta schemat"
        }
        return Entry(
            key: address.key,
            title: address.displayName,
            subtitle: [address.street, address.locality].filter { !$0.isEmpty }.joined(separator: ", "),
            status: status,
            refreshFailed: refreshFailed,
            reminderText: reminder,
            summary: summary
        )
    }

    private static func status(of schedule: CachedSchedule?, today: DayDate) -> Status {
        guard let schedule else { return .loading }
        guard let response = schedule.response else {
            return schedule.lastError.map { .failed($0) } ?? .loading
        }
        guard let event = ScheduleLogic.nextPickup(response.events, today: today) else { return .noUpcoming }
        let daysUntil = today.days(until: event.date)
        let headline = SwedishFormat.estimated(SwedishFormat.relative(days: daysUntil), event.estimated)
        let longDate = SwedishFormat.estimated(SwedishFormat.longDate(event.date, capitalized: !event.estimated), event.estimated)
        return .upcoming(Pickup(
            date: event.date,
            daysUntil: daysUntil,
            estimated: event.estimated,
            fractions: event.fractions.map {
                FractionItem(id: $0, info: ScheduleLogic.displayInfo(for: $0, in: response.fractions))
            },
            headline: capitalized(headline),
            longDate: capitalized(longDate)
        ))
    }

    /// Påminnelsen gäller kvällen före en hämtning, i svensk tid. Har kvällen före nästa hämtning redan
    /// passerat räknas den från nästa hämtning efter den. Finns ingen sådan visas en neutral text.
    /// Texten ska vara sann: en tid för Live Activity lovas bara när en aktivitet finns hos systemet.
    private static func reminderText(notifications: Bool, settings: ReminderSettings, events: [PickupEvent], today: DayDate, now: Date, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool) -> String {
        if settings.liveActivityOn, let liveActivity {
            guard liveActivity.isPending else { return "Live Activity visas nu" }
            let day = StockholmClock.today(now: liveActivity.start)
            let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: liveActivity.start)
            let time = SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return "Live Activity \(SwedishFormat.weekdayName(day)) kl. \(time)"
        }
        guard notifications || settings.liveActivityOn else { return "Påminn mig kvällen före" }
        guard notifications else { return liveActivitiesEnabled ? "Live Activity på" : "Live Activities är avstängda" }
        for event in ScheduleLogic.upcoming(events, today: today) {
            let evening = event.date.adding(days: -1)
            guard StockholmClock.date(on: evening, minutes: settings.reminderMinutes) > now else { continue }
            let time = String(format: "%02d:%02d", settings.reminderMinutes / 60, settings.reminderMinutes % 60)
            return "Påminnelse \(SwedishFormat.weekdayName(evening)) kl. \(time)"
        }
        return "Påminnelser på"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
