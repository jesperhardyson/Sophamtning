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

    /// Raden om hur långt schemat gäller, nära de kommande tömningarna.
    public struct SchedulePeriodLine: Equatable, Sendable {
        /// "Schemat gäller till 10 januari 2027."
        public let text: String
        /// Källans förklaring i mindre text, som källan skrev den, eller `nil`.
        public let reason: String?

        public init(text: String, reason: String?) {
            self.text = text
            self.reason = reason
        }
    }

    /// Meddelandet när schemat inte har några hämtningar från och med i dag.
    public struct NoUpcomingMessage: Equatable, Sendable {
        public let title: String
        public let message: String

        public init(title: String, message: String) {
            self.title = title
            self.message = message
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

        public var accessibilityLabel: String {
            (["\(dateText), \(daysText)", fractions.map(\.info.name).joined(separator: ", ")] + [deviation, warning].compactMap { $0 }).joined(separator: ". ")
        }
    }

    public let key: AddressKey
    public let title: String
    /// Adressen och platsen under rubriken, på var sin rad. Rubriken är adressens namn.
    public let lines: HomeContent.AddressLines
    /// Namnet, adressen och platsen, för Hela schemat, där rubriken inte är adressens namn.
    public let namedLines: HomeContent.AddressLines
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

    /// De närmaste datumen under "Kommande", efter nästa tömning. Nästa tömning står redan i kortet ovanför, med sin
    /// varning (`nextWarning`) och avvikelse (`nextDeviation`). Tom när det inte finns fler datum.
    public var upcoming: [Row] {
        Array(rows.filter { $0.date != next?.date }.prefix(Self.upcomingCount))
    }

    /// Länken "Hela schemat" visas bara när det finns fler datum än de som redan står på sidan: nästa tömning och
    /// raderna under "Kommande".
    public var hasFullSchedule: Bool { rows.count > Self.upcomingCount + (next == nil ? 0 : 1) }

    /// "Flyttad från sön 8 nov" för nästa tömning, som står i kortet eftersom raden inte finns under "Kommande".
    public var nextDeviation: String? {
        rows.first { $0.date == next?.date }?.deviation
    }
    /// "Schemat gäller till 10 januari 2027." med källans orsak. `nil` för live-källor och när perioden har passerat.
    public let schedulePeriod: SchedulePeriodLine?
    /// Rutan när schemat tar slut inom 14 dagar. Bara med kommande hämtningar: utan dem säger meddelandet nedan hur långt
    /// schemat gäller. `nil` för live-källor och efter att perioden har passerat.
    public let scheduleEnding: ScheduleEnding?
    /// Rutan "Vissa gator har en annan hämtdag" för ett område med avvikande gator. `nil` när raderna saknas.
    public let otherDays: OtherDaysNote?
    /// Meddelandet i läget `noUpcoming`. Har källans period passerat säger det att nästa period inte är publicerad än.
    public let noUpcomingMessage: NoUpcomingMessage
    /// "Hämtat i dag 09:12", längst ned i kortet för källan, eller `nil` när schemat aldrig hämtats.
    public let fetchedText: String?
    /// Kommunens eller bolagets sida för adressen (`links.web`).
    public let webLink: URL?
    /// Raden under reglaget "Påminn mig".
    public let reminderText: String
    public let liveActivityText: String
    public let isPrimary: Bool
    /// Delen Påminnelser visas när det finns hämtningar. Utan hämtningar visas den bara när en påminnelse redan är på
    /// (notisen för adressen, eller Live Activity för huvudadressen), så att den går att stänga av.
    public let showsReminders: Bool
    /// "Tömning i morgon. Påminnelsen för i kväll har redan passerat." när notiser är på och tiden redan passerat.
    public let missedReminder: String?
    /// Hushållets rad, för varje läge. `nil` utan hushåll.
    public let household: HouseholdLine?

    public static func make(address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, sourceName: String?, now: Date, remindersOn: Bool = false, reserveAt: Date? = nil, household: HouseholdState = .empty, ownPlacedOut: Set<PlacedOut> = [], silencedPickups: Set<PlacedOut> = []) -> AddressDetail {
        let today = StockholmClock.today(now: now)
        var asPrimary = address
        asPrimary.isPrimary = true
        // Live Activity gäller bara huvudadressen, så den ger knappen Ställ ut kärlen bara där.
        var entrySettings = settings
        entrySettings.liveActivityOn = settings.liveActivityOn && address.isPrimary
        let entry = HomeContent.make(addresses: [asPrimary], schedules: schedule.map { [address.key: $0] } ?? [:], settings: entrySettings, now: now, household: household, ownPlacedOut: ownPlacedOut, silencedPickups: silencedPickups).primary!
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

        let liveActivityOn = settings.liveActivityOn && address.isPrimary
        let showsReminders = mode == .schedule || (mode == .noUpcoming && (address.notificationsOn || liveActivityOn))
        // Utan hämtningar står samma rad under båda reglagen, eftersom det inte finns någon tid att visa.
        let nothingToRemind = mode == .noUpcoming ? Self.nothingToRemindText : nil

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
            namedLines: HomeContent.namedLines(for: address),
            mode: mode,
            notice: notice,
            next: next,
            nextWarning: scheduleRows.first(where: { $0.date == next?.date })?.warning,
            bins: bins,
            rows: scheduleRows,
            schedulePeriod: periodLine(response?.schedule, mode: mode, today: today),
            scheduleEnding: mode == .schedule ? ScheduleEnding.make(response?.schedule, today: today) : nil,
            otherDays: OtherDaysNote.make(response?.address.area),
            noUpcomingMessage: noUpcomingMessage(response?.schedule, today: today, afterError: notice != nil, sourceName: sourceName),
            fetchedText: fetchedTime,
            webLink: response?.links.web,
            reminderText: nothingToRemind ?? rowText(events: response?.events ?? [], settings: settings, now: now, reserveAt: reserveAt, skipping: HomeContent.skippedDays(for: address.key, ownPlacedOut: ownPlacedOut, silencedPickups: silencedPickups)),
            liveActivityText: nothingToRemind ?? liveActivityText(settings: settings),
            isPrimary: address.isPrimary,
            showsReminders: showsReminders,
            missedReminder: remindersOn ? missedReminder(events: response?.events ?? [], settings: settings, now: now) : nil,
            household: entry.household
        )
    }

    /// Raden under reglagen när adressen inte har några kommande hämtningar.
    static let nothingToRemindText = "Inga hämtningar att påminna om just nu."

    /// Raden visas när källan anger en period som inte har passerat och det finns kommande hämtningar. Utan kommande
    /// hämtningar står perioden i meddelandet i stället, så att texterna inte motsäger varandra. Live-källor har ingen
    /// period.
    static func periodLine(_ period: SchedulePeriod?, mode: Mode, today: DayDate) -> SchedulePeriodLine? {
        guard let period, period.until >= today, mode == .schedule else { return nil }
        return SchedulePeriodLine(text: "Schemat gäller till \(SwedishFormat.dayMonthYear(period.until)).", reason: period.reason?.trimmedNonEmpty)
    }

    /// Utan kommande hämtningar. Gäller perioden fortfarande finns inga fler hämtningar i det publicerade schemat. Har den
    /// passerat har källan inte publicerat nästa period än. Källans orsak står med. Det säger aldrig att adressen saknas.
    /// Visas ett sparat schema efter ett fel (`afterError`) kan nästa period finnas hos källan utan att ha kommit fram,
    /// så då står bara vad det senast hämtade schemat säger, aldrig att något saknas hos källan. En live-källa har ingen
    /// period, och ett tomt svar från den betyder oftast att adressen saknar abonnemang, så texten hänvisar till källan.
    static func noUpcomingMessage(_ period: SchedulePeriod?, today: DayDate, afterError: Bool = false, sourceName: String? = nil) -> NoUpcomingMessage {
        let title = "Inga kommande hämtningar"
        guard let period else {
            let message = afterError
                ? "Det senast hämtade schemat har inga fler hämtningar."
                : "Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta \(sourceName?.trimmedNonEmpty ?? "den som ansvarar för hämtningen")."
            return NoUpcomingMessage(title: title, message: message)
        }
        let until = SwedishFormat.dayMonthYear(period.until)
        let base: String
        if period.until >= today {
            base = "Inga fler hämtningar i schemat, som gäller till \(until)."
        } else if afterError {
            base = "Det senast hämtade schemat gällde till \(until)."
        } else {
            base = "Schemat gällde till \(until), och källan har inte publicerat nästa period än."
        }
        let reason = period.reason?.trimmedNonEmpty
        return NoUpcomingMessage(title: title, message: [base, reason].compactMap { part in part }.joined(separator: " "))
    }

    /// Klockslaget för ett ögonblick i svensk tid, "18:45".
    static func clock(of date: Date) -> String {
        let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: date)
        return SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// "Söndag kl. 18:45 inför måndagens tömning, om aktiviteten inte syns." eller "Måndag kl. 06:45, samma dag som
    /// tömningen, om aktiviteten inte syns." När det är reserven som gäller.
    /// Tömningsdagen räknas från reservens klockslag, inte från det som är valt nu: en notis från det andra valet kan stå kvar
    /// efter ett byte.
    static func reserveText(_ reserveAt: Date) -> String {
        let day = StockholmClock.today(now: reserveAt)
        let pickup = ReminderTime.pickupDay(forReminderAt: reserveAt)
        let timing: ReminderTiming = pickup == day ? .sameMorning : .eveningBefore
        return "\(when(day: day, pickup: pickup, time: clock(of: reserveAt), timing: timing)), om aktiviteten inte syns."
    }

    /// "Söndag kl. 18:00 inför måndagens tömning" eller "Måndag kl. 06:00, samma dag som tömningen".
    private static func when(day: DayDate, pickup: DayDate, time: String, timing: ReminderTiming) -> String {
        let weekday = SwedishFormat.weekdayName(day)
        let start = "\(weekday.prefix(1).uppercased() + weekday.dropFirst()) kl. \(time)"
        switch timing {
        case .eveningBefore: return "\(start) inför \(SwedishFormat.weekdayName(pickup))ens tömning"
        case .sameMorning: return "\(start), samma dag som tömningen"
        }
    }

    /// Texten vid valet för Live Activity: en mening. Resten står i `liveActivityDetails()`.
    /// Det som står bakom knappen Mer om Live Activity, en mening per rad.
    public static func liveActivityDetails() -> [String] {
        [
            "Starten aviseras med ljud.",
            "Den försvinner senast efter 12 timmar.",
            "Öppna appen ibland, så att nästa tömning kommer med.",
            "Med notis vid samma tid får du en reserv om du inte bekräftar.",
        ]
    }

    /// Hela tiden aktiviteten syns, högst 12 timmar från starten: "Visas på låsskärmen kl. 21:00 dagen före till 09:00." eller
    /// "Visas på låsskärmen kl. 06:00–18:00 samma dag."
    public static func liveActivityText(settings: ReminderSettings) -> String {
        let start = settings.liveActivityStartMinutes
        let from = SwedishFormat.clock(minutes: start)
        let to = SwedishFormat.clock(minutes: (start + 12 * 60) % (24 * 60))
        switch settings.liveActivityTiming {
        case .eveningBefore: return "Visas på låsskärmen kl. \(from) dagen före till \(to)."
        case .sameMorning: return "Visas på låsskärmen kl. \(from)–\(to) samma dag."
        }
    }

    /// Påminnelsetiden i dag har redan passerat för tömningen den gäller, i morgon med kvällen före och i dag med samma
    /// morgon. Till exempel efter att tiden ändrats eller notisen slagits på sent.
    public static func missedReminder(events: [PickupEvent], settings: ReminderSettings, now: Date) -> String? {
        let today = StockholmClock.today(now: now)
        // Det senast påslagna valet avgör: kvällens tid kan ha passerat utan att något är missat, när morgonen kommer.
        let timing = settings.latestTiming
        let pickup = ReminderTime.pickupDay(remindedOn: today, timing: timing)
        guard events.contains(where: { $0.date == pickup && !$0.fractions.isEmpty }),
              ReminderTime.date(forPickup: pickup, timing: timing, settings: settings) <= now
        else { return nil }
        return timing.missedText
    }

    /// "Mån 9 nov", eller "ca tors 12 nov" när datumet är beräknat.
    static func dateText(_ day: DayDate, estimated: Bool) -> String {
        let text = SwedishFormat.shortDate(day)
        return estimated ? "ca " + text.lowercased() : text
    }

    /// Raden under reglaget: reservnotisen när den är nästa påminnelse, annars nästa påminnelse. Reserven ersätter notisen för
    /// aktivitetens val, så den gäller när det är nästa, när den kommer före nästa eller när ingen annan finns. En tidigare
    /// notis för det andra valet kommer annars först och är det som raden ska visa, som på hemkortet.
    static func rowText(events: [PickupEvent], settings: ReminderSettings, now: Date, reserveAt: Date?, skipping: Set<DayDate>) -> String {
        if let reserveAt {
            let next = ReminderTime.next(events: events, settings: settings, now: now, skipping: skipping)
            if next == nil || next?.timing == settings.liveActivityTiming || reserveAt <= next!.date { return reserveText(reserveAt) }
        }
        return reminderText(events: events, settings: settings, now: now, skipping: skipping)
    }

    /// "Söndag kl. 18:00 inför måndagens tömning." eller "Måndag kl. 06:00, samma dag som tömningen." Det är nästa påminnelse
    /// av de påslagna valen. Finns ingen kommande tömning står texten för varje påslaget val.
    static func reminderText(events: [PickupEvent], settings: ReminderSettings, now: Date, skipping: Set<DayDate> = []) -> String {
        if let next = ReminderTime.next(events: events, settings: settings, now: now, skipping: skipping) {
            let day = StockholmClock.today(now: next.date)
            return "\(when(day: day, pickup: next.pickup, time: clock(of: next.date), timing: next.timing))."
        }
        return settings.enabledTimings.map { timing in
            let time = SwedishFormat.clock(minutes: settings.minutes(for: timing))
            switch timing {
            case .eveningBefore: return "Kvällen före varje tömning kl. \(time)."
            case .sameMorning: return "Samma morgon som varje tömning kl. \(time)."
            }
        }.joined(separator: " ")
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
            let warning = event.warning?.trimmedNonEmpty
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
        return deviation.reason.trimmedNonEmpty
    }
}
