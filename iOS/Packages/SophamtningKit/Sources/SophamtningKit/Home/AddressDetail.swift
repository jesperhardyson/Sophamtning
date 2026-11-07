import Foundation

/// Adressvyns innehåll, räknat från den sparade adressen och schemat och given tid.
/// Som `HomeContent` räknas allt lokalt, och sparade `daysUntil`, `isToday` och `text` används aldrig.
public struct AddressDetail: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Schemat har inte hämtats än.
        case loading
        /// Det finns kommande hämtningar.
        case schedule
        /// Schemat finns men har inga hämtningar från och med i dag.
        case noUpcoming
        /// Inget sparat schema och hämtningen misslyckades.
        case unavailable
    }

    /// Meddelandet högst upp, vid fel.
    public enum Notice: Equatable, Sendable {
        /// Ett sparat schema visas fast det senaste försöket misslyckades. `fetched` är texten "Hämtat i går 18:40."
        case savedShown(fetched: String?)
        /// 502, nätfel eller timeout utan sparat schema. Det betyder inte att adressen saknas.
        case sourceUnavailable
        /// 404: källan känner inte längre igen adressen. Adressen behålls.
        case notFound
        /// 400: källan godtog inte förfrågan. Det är varken ett nätfel eller en adress som saknas, och samma anrop upprepas inte.
        case badRequest
        /// Schemat hämtades men gick inte att spara på telefonen.
        case storageFailed
    }

    /// Nästa hämtning per fraktion, med datum och dagar kvar.
    public struct Bin: Equatable, Sendable, Identifiable {
        public let id: String
        public let info: FractionInfo
        /// "Mån 9 nov", eller "ca tors 12 nov" när datumet är beräknat.
        public let dateText: String
        /// "om 3 dagar", "i övermorgon", "i morgon" eller "i dag".
        public let daysText: String

        /// Kortet för kärlet läses som en enhet: "Restavfall, om 3 dagar, Mån 9 nov".
        public var accessibilityLabel: String {
            [info.name, daysText, dateText].joined(separator: ", ")
        }
    }

    /// En dag i schemat. Flera fraktioner samma dag visas som chips.
    public struct Row: Equatable, Sendable, Identifiable {
        public let date: DayDate
        public let dateText: String
        /// Datumbrickan: "11" och "NOV".
        public let dayNumber: String
        public let month: String
        /// "om 5 dagar", "i övermorgon", "i morgon" eller "i dag", med "ca" först när datumet är beräknat. Räknat från i dag.
        public let daysText: String
        /// Kort form för raden: "om 5 d", "i morgon" eller "i dag", med "ca" först när datumet är beräknat.
        public let shortDaysText: String
        public let fractions: [HomeContent.FractionItem]
        /// "Flyttad från mån 16 nov", eller källans orsak när ursprungsdatumet saknas.
        public let deviation: String?
        public let warning: String?
        public var id: DayDate { date }

        var withoutWarning: Row {
            Row(date: date, dateText: dateText, dayNumber: dayNumber, month: month, daysText: daysText, shortDaysText: shortDaysText, fractions: fractions, deviation: deviation, warning: nil)
        }

        public var accessibilityLabel: String {
            (["\(dateText), \(daysText)", fractions.map(\.info.name).joined(separator: ", ")] + [deviation, warning].compactMap { $0 }).joined(separator: ". ")
        }
    }

    public let key: AddressKey
    public let title: String
    /// Adressen och platsen under rubriken, på var sin rad.
    public let lines: HomeContent.AddressLines
    public let mode: Mode
    public let notice: Notice?
    public let next: HomeContent.Pickup?
    /// Varning för nästa hämtning, som visas i en egen ruta.
    public let nextWarning: String?
    public let bins: [Bin]
    /// Hela det kommande schemat, en rad per datum.
    public let rows: [Row]

    /// Hur många datum som visas under "Kommande".
    public static let upcomingCount = 3

    /// De närmaste datumen under "Kommande". Det första kan vara samma dag som nästa tömning. Dess varning står då
    /// bara i rutan för nästa tömning (`nextWarning`), inte en gång till under raden. Avvikelsen står kvar.
    public var upcoming: [Row] {
        rows.prefix(Self.upcomingCount).map { row in
            row.date == next?.date ? row.withoutWarning : row
        }
    }

    /// Länken "Hela schemat" visas bara när det finns fler datum än under "Kommande".
    public var hasFullSchedule: Bool { rows.count > Self.upcomingCount }
    /// "Hämtat i dag 09:12", längst ned i kortet för källan, eller `nil` när schemat aldrig hämtats.
    public let fetchedText: String?
    /// Kommunens eller bolagets sida för adressen (`links.web`).
    public let webLink: URL?
    /// Raden under "Notis kvällen före".
    public let reminderText: String
    public let liveActivityText: String
    public let isPrimary: Bool
    /// "Tömning i morgon. Påminnelsen för i kväll har redan passerat." när notiser är på och tiden redan passerat.
    public let missedReminder: String?

    public static func make(address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, sourceName: String?, now: Date, remindersOn: Bool = false, reserveAt: Date? = nil) -> AddressDetail {
        let today = StockholmClock.today(now: now)
        var asPrimary = address
        asPrimary.isPrimary = true
        let entry = HomeContent.make(addresses: [asPrimary], schedules: schedule.map { [address.key: $0] } ?? [:], settings: settings, now: now).primary!
        let response = schedule?.response

        let mode: Mode
        var next: HomeContent.Pickup?
        switch entry.status {
        case .loading: mode = .loading
        case .noUpcoming: mode = .noUpcoming
        case .failed: mode = .unavailable
        case .upcoming(let pickup):
            mode = .schedule
            next = pickup
        }

        let fetched = fetchedText(at: schedule?.fetchedAt, sourceName: sourceName, now: now)
        let fetchedTime = fetchedTime(at: schedule?.fetchedAt, now: now)
        let notice: Notice?
        switch schedule?.lastError {
        case .notFound: notice = .notFound
        case .badRequest: notice = .badRequest
        // Ett misslyckat sparande markeras av modellen med `unexpected(0)`.
        case .unexpected(0): notice = .storageFailed
        case .some:
            notice = response == nil ? .sourceUnavailable : .savedShown(fetched: fetched)
        case nil: notice = nil
        }

        let scheduleRows = response.map { rows(in: $0, today: today) } ?? []
        let bins = response.map { response in
            ScheduleLogic.nextByFraction(response.events, today: today).map { pickup in
                Bin(
                    id: pickup.fraction,
                    info: ScheduleLogic.displayInfo(for: pickup.fraction, in: response.fractions),
                    dateText: dateText(pickup.date, estimated: pickup.estimated),
                    daysText: SwedishFormat.relative(days: pickup.daysUntil)
                )
            }
        } ?? []

        return AddressDetail(
            key: address.key,
            title: address.displayName,
            lines: entry.lines,
            mode: mode,
            notice: notice,
            next: next,
            nextWarning: scheduleRows.first(where: { $0.date == next?.date })?.warning,
            bins: bins,
            rows: scheduleRows,
            fetchedText: fetchedTime,
            webLink: response?.links.web,
            reminderText: reserveAt.map { reserveText($0) } ?? reminderText(events: response?.events ?? [], settings: settings, today: today, now: now),
            liveActivityText: liveActivityText(settings: settings),
            isPrimary: address.isPrimary,
            missedReminder: remindersOn ? missedReminder(events: response?.events ?? [], settings: settings, now: now) : nil
        )
    }

    /// Klockslaget för ett ögonblick i svensk tid, "18:45".
    static func clock(of date: Date) -> String {
        let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: date)
        return SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// "Söndag kl. 18:45 inför måndagens tömning, om aktiviteten inte syns." När det är reserven som gäller.
    static func reserveText(_ reserveAt: Date) -> String {
        let evening = StockholmClock.today(now: reserveAt)
        let weekday = SwedishFormat.weekdayName(evening)
        return "\(weekday.prefix(1).uppercased() + weekday.dropFirst()) kl. \(clock(of: reserveAt)) inför \(SwedishFormat.weekdayName(evening.adding(days: 1)))ens tömning, om aktiviteten inte syns."
    }

    /// Texten vid valet för Live Activity.
    public static func liveActivityText(settings: ReminderSettings) -> String {
        let time = SwedishFormat.clock(minutes: settings.reminderMinutes)
        return "Visas på låsskärmen från kl. \(time) kvällen före. Starten aviseras med ljud, och den försvinner senast efter 12 timmar. Öppna appen ibland, så att nästa tömning kommer med. Med notiser på får du också en reserv om du inte bekräftar."
    }

    /// Tömning i morgon men påminnelsetiden i dag har redan passerat, till exempel efter att tiden ändrats eller notisen slagits på sent.
    public static func missedReminder(events: [PickupEvent], settings: ReminderSettings, now: Date) -> String? {
        let today = StockholmClock.today(now: now)
        let minutes = ReminderSettings.isValid(minutes: settings.reminderMinutes) ? settings.reminderMinutes : 1080
        guard events.contains(where: { $0.date == today.adding(days: 1) && !$0.fractions.isEmpty }),
              StockholmClock.date(on: today, minutes: minutes) <= now
        else { return nil }
        return "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
    }

    /// "Mån 9 nov", eller "ca tors 12 nov" när datumet är beräknat.
    static func dateText(_ day: DayDate, estimated: Bool) -> String {
        let text = SwedishFormat.shortDate(day)
        return estimated ? "ca " + text.lowercased() : text
    }

    /// "Söndag kl. 18:00 inför måndagens tömning." Har kvällen före nästa hämtning passerat räknas nästa hämtning efter den.
    static func reminderText(events: [PickupEvent], settings: ReminderSettings, today: DayDate, now: Date) -> String {
        let time = SwedishFormat.clock(minutes: settings.reminderMinutes)
        for event in ScheduleLogic.upcoming(events, today: today) where !event.fractions.isEmpty {
            let evening = event.date.adding(days: -1)
            guard StockholmClock.date(on: evening, minutes: settings.reminderMinutes) > now else { continue }
            let weekday = SwedishFormat.weekdayName(evening)
            return "\(weekday.prefix(1).uppercased() + weekday.dropFirst()) kl. \(time) inför \(SwedishFormat.weekdayName(event.date))ens tömning."
        }
        return "Kvällen före varje tömning kl. \(time)."
    }

    /// "Hämtat i dag 09:12 från Avesta Vatten och Avfall.", i rutan när ett sparat schema visas efter ett fel.
    static func fetchedText(at fetchedAt: Date?, sourceName: String?, now: Date) -> String? {
        guard let time = fetchedTime(at: fetchedAt, now: now) else { return nil }
        let source = sourceName.map { " från \($0)" } ?? ""
        return "\(time)\(source)."
    }

    /// "Hämtat i dag 09:12", "Hämtat i går 18:40" eller "Hämtat 1 nov 07:00", i svensk tid.
    static func fetchedTime(at fetchedAt: Date?, now: Date) -> String? {
        guard let fetchedAt else { return nil }
        let day = StockholmClock.today(now: fetchedAt)
        let today = StockholmClock.today(now: now)
        let when: String
        switch day.days(until: today) {
        case 0: when = "i dag"
        case 1: when = "i går"
        default: when = SwedishFormat.dayMonth(day)
        }
        let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: fetchedAt)
        let clock = SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return "Hämtat \(when) \(clock)"
    }

    /// Kommande dagar, en rad per datum. Två händelser samma dag slås ihop, så att ingen fraktion eller varning tappas.
    private static func rows(in response: AddressResponse, today: DayDate) -> [Row] {
        var order: [DayDate] = []
        var merged: [DayDate: (fractions: [String], estimated: Bool, deviation: Deviation?, warnings: [String])] = [:]
        for event in ScheduleLogic.upcoming(response.events, today: today) {
            let warning = event.warning?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if var existing = merged[event.date] {
                for id in event.fractions where !existing.fractions.contains(id) { existing.fractions.append(id) }
                existing.estimated = existing.estimated || event.estimated
                existing.deviation = existing.deviation ?? event.deviation
                if let warning, !existing.warnings.contains(warning) { existing.warnings.append(warning) }
                merged[event.date] = existing
            } else {
                order.append(event.date)
                var fractions: [String] = []
                for id in event.fractions where !fractions.contains(id) { fractions.append(id) }
                merged[event.date] = (fractions, event.estimated, event.deviation, warning.map { [$0] } ?? [])
            }
        }
        return order.compactMap { date in
            guard let entry = merged[date], !entry.fractions.isEmpty else { return nil }
            return Row(
                date: date,
                dateText: dateText(date, estimated: entry.estimated),
                dayNumber: SwedishFormat.dayNumber(date),
                month: SwedishFormat.monthUppercased(date),
                daysText: SwedishFormat.estimated(SwedishFormat.relative(days: today.days(until: date)), entry.estimated),
                shortDaysText: SwedishFormat.estimated(shortRelative(days: today.days(until: date)), entry.estimated),
                fractions: entry.fractions.map { HomeContent.FractionItem(id: $0, info: ScheduleLogic.displayInfo(for: $0, in: response.fractions)) },
                deviation: entry.deviation.flatMap { deviationText($0) },
                warning: entry.warnings.isEmpty ? nil : entry.warnings.joined(separator: " ")
            )
        }
    }

    /// "om 5 d", "i morgon" eller "i dag". Talet och d hålls ihop med hårt mellanslag, så att de aldrig hamnar på olika
    /// rader.
    private static func shortRelative(days: Int) -> String {
        days > 1 ? "om \(days)\u{00A0}d" : SwedishFormat.relative(days: days)
    }

    private static func deviationText(_ deviation: Deviation) -> String? {
        if let original = deviation.originalDate {
            return "Flyttad från " + SwedishFormat.shortDate(original).lowercased()
        }
        return deviation.reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
