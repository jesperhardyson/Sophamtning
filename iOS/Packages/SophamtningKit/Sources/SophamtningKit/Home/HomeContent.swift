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
        /// Schemat saknas och det senaste försöket misslyckades. Det är ett tekniskt fel, inte att adressen saknas.
        case failed
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
            if case .upcoming(let pickup) = status {
                parts.append(pickup.fractions.map(\.info.name).joined(separator: ", "))
            }
            return parts.joined(separator: ", ")
        }
    }

    public let primary: Entry?
    public let others: [Entry]

    public static func make(addresses: [SavedAddress], schedules: [AddressKey: CachedSchedule], settings: ReminderSettings, now: Date) -> HomeContent {
        let today = StockholmClock.today(now: now)
        let primaryAddress = addresses.first(where: \.isPrimary) ?? addresses.first
        let primary = primaryAddress.map { address in
            entry(address, schedule: schedules[address.key], settings: settings, today: today, now: now, withReminder: true)
        }
        let others = addresses
            .filter { $0.key != primaryAddress?.key }
            .map { entry($0, schedule: schedules[$0.key], settings: settings, today: today, now: now, withReminder: false) }
        return HomeContent(primary: primary, others: others)
    }

    private static func entry(_ address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, today: DayDate, now: Date, withReminder: Bool) -> Entry {
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
                reminder = reminderText(address: address, settings: settings, pickup: pickup)
            }
        case .noUpcoming:
            summary = "Inga kommande hämtningar"
        case .loading:
            summary = "Hämtar schema…"
        case .failed:
            summary = "Kunde inte hämta schemat"
        }
        return Entry(
            key: address.key,
            title: address.displayName,
            subtitle: "\(address.street), \(address.locality)",
            status: status,
            refreshFailed: refreshFailed,
            reminderText: reminder,
            summary: summary
        )
    }

    private static func status(of schedule: CachedSchedule?, today: DayDate) -> Status {
        guard let schedule else { return .loading }
        guard let response = schedule.response else {
            return schedule.lastError != nil ? .failed : .loading
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

    /// Påminnelsen gäller kvällen före nästa hämtning, i svensk tid.
    private static func reminderText(address: SavedAddress, settings: ReminderSettings, pickup: Pickup) -> String {
        guard address.notificationsOn || settings.liveActivityOn else { return "Påminn mig kvällen före" }
        let evening = pickup.date.adding(days: -1)
        let time = String(format: "%02d:%02d", settings.reminderMinutes / 60, settings.reminderMinutes % 60)
        return "Påminnelse \(SwedishFormat.weekdayName(evening)) kl. \(time)"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
