import Foundation

/// Hemskärmens innehåll, räknat från sparade adresser och scheman och given tid.
/// Allt räknas lokalt: dagar, datum och påminnelsetext kommer aldrig från sparade `next`-fält.
public struct HomeContent: Equatable, Sendable {
    /// Reglagets namn på huvudkortet, i adressvyn och i snabbmenyn.
    public static func reminderTitle() -> String { "Påminn mig" }
    /// VoiceOvers åtgärd för samma reglage, på huvudkortet och raderna.
    public static func reminderActionTitle(isOn: Bool) -> String { isOn ? "Stäng av påminnelse" : "Slå på påminnelse" }

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
        /// "Om 3 dagar", "I övermorgon", "I morgon" eller "I dag", med "Ca" först när datumet är uppskattat.
        public let headline: String
        /// "Måndag 9 november", med "Ca" först när datumet är uppskattat.
        public let longDate: String

        /// Datum, dagar kvar och kärlen i ett: "Nästa tömning. Om 3 dagar. Måndag 9 november. Restavfall, Matavfall".
        public var accessibilityLabel: String {
            ["Nästa tömning", headline, longDate, fractions.map(\.info.name).joined(separator: ", ")].joined(separator: ". ")
        }
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

    /// Påminnelsen på en rad under "Fler adresser". Notis av ger ingen rad alls.
    public enum RowReminder: Equatable, Sendable {
        /// Notis på och tillåten: "Påminnelse tisdag kl. 18:45", eller "Påminnelser på" utan senare tömning.
        case scheduled(String)
        /// Notis på för adressen, men notiser är inte tillåtna i iOS.
        case denied
        /// Kvällens påminnelse har redan passerat, med samma text som huvudkortet.
        case missed(String)

        public var text: String {
            switch self {
            case .scheduled(let text), .missed(let text): text
            case .denied: "Notiser är avstängda i iOS"
            }
        }
    }

    /// Påminnelsen för huvudadressen. Kortet visar `line` i sin fot, eller rutan om nekade notiser.
    public struct PrimaryReminder: Equatable, Sendable {
        /// Påminnelsen är på och tillåten i iOS.
        public let isOn: Bool
        /// iOS har nekat notiser. Reglaget är av, och en knapp öppnar Inställningar.
        public let isDenied: Bool
        /// "Påminn mig", eller "Notiser är avstängda i iOS".
        public let title: String
        /// Raden under: när påminnelsen kommer ("Söndag kl. 18:00"), eller en väntande Live Activity ("Live Activity söndag
        /// kl. 17:30", och "Notis och Live Activity söndag kl. 17:30" när notisen också är på).
        public let detail: String?
        /// Raden i huvudkortets fot: "Påminnelse söndag kl. 18:00", "Live Activity söndag kl. 17:30". `nil` när
        /// påminnelsen är av, eftersom kortet inte har något reglage.
        public let line: String?
        /// Påminnelsen är på för adressen men iOS nekar notiser. Kortet visar då en ruta med Öppna Inställningar. Är
        /// påminnelsen av visas ingen ruta, eftersom inget har slutat fungera.
        public let showsDeniedNotice: Bool

        public init(isOn: Bool, isDenied: Bool, title: String, detail: String?, line: String? = nil, showsDeniedNotice: Bool = false) {
            self.isOn = isOn
            self.isDenied = isDenied
            self.title = title
            self.detail = detail
            self.line = line
            self.showsDeniedNotice = showsDeniedNotice
        }

        /// Byggs av huvudkortets text för påminnelsen. Inbjudan blir rubriken, och "Påminnelse söndag kl. 18:00" blir
        /// "Söndag kl. 18:00" under den.
        init(text: String, isOn: Bool, isDenied: Bool, isWanted: Bool) {
            self.isOn = isOn
            self.isDenied = isDenied
            // Inbjudan betyder att varken notis eller Live Activity är på.
            line = text == HomeContent.reminderTitle() ? nil : text
            showsDeniedNotice = isDenied && isWanted
            title = isDenied ? RowReminder.denied.text : HomeContent.reminderTitle()
            // Inbjudan är redan rubriken, och "Påminnelser på" säger bara det reglaget redan visar.
            if text == HomeContent.reminderTitle() || text == "Påminnelser på" {
                detail = nil
            } else if text.hasPrefix("Påminnelse ") {
                let rest = text.dropFirst("Påminnelse ".count)
                detail = rest.prefix(1).uppercased() + rest.dropFirst()
            } else {
                detail = text
            }
        }
    }

    /// Adressen och platsen på var sin rad: "Storgatan 12" och "Krylbo · Avesta kommun". Där adressens namn inte står
    /// i rubriken, som i Hela schemat, står namnet på en egen rad först.
    public struct AddressLines: Equatable, Sendable {
        /// Adressens namn, "Hemma". Tomt där namnet redan står i rubriken eller på kortet.
        public let name: String
        /// Gatan med nummer, eller områdets namn. Tom när adressen saknar gata eller när gatan bara upprepar namnet.
        public let address: String
        /// Orten och kommunen. Kommunen döljs när den bara upprepar orten.
        public let place: String

        public init(name: String = "", address: String, place: String) {
            self.name = name
            self.address = address
            self.place = place
        }

        /// Gatan och platsen på en rad, med komma emellan: "Storgatan 12, Krylbo · Avesta kommun". Namnet står inte med.
        public var singleLine: String {
            [address, place].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        /// "Hemma, Storgatan 12, Krylbo, Avesta kommun", utan mittpunkt och med vanliga mellanslag.
        public var accessibilityLabel: String {
            [name, address, place.replacingOccurrences(of: "\u{00A0}· ", with: ", ")]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public let key: AddressKey
        public let title: String
        /// Adressen och platsen på var sin rad.
        public let lines: AddressLines
        public let status: Status
        /// Senaste försöket att uppdatera misslyckades, men ett äldre schema visas.
        public let refreshFailed: Bool
        /// Huvudkortets reglage för påminnelsen. `nil` när det inte finns någon kommande hämtning, och alltid på raderna.
        public let reminder: PrimaryReminder?
        /// Radens påminnelse under "Fler adresser". Bara när notis är på för adressen och en hämtning kommer, och utan
        /// Live Activity, som bara gäller huvudadressen. Alltid `nil` på huvudkortet.
        public let rowReminder: RowReminder?
        /// "Schemat slutar 10 jan" när schemat tar slut inom 14 dagar. Bara med kommande hämtningar, och aldrig för
        /// live-källor.
        public let scheduleEnding: ScheduleEnding?
        /// Raden under adressen: "Ons 18 nov · om 12 dagar" eller en statustext.
        public let summary: String
        /// Hushållets rad, för varje status. `nil` utan hushåll.
        public let household: HouseholdLine?

        /// Hur raden under adressen visas: som ett datum, som en lugn statustext eller som en varning.
        public enum SummaryTone: Sendable { case date, neutral, warning }

        /// "Inga kommande hämtningar" och "Hämtar schema…" är neutrala, så att de inte ser ut som ett datum. Ett
        /// misslyckat försök utan sparat schema är en varning.
        public var summaryTone: SummaryTone {
            switch status {
            case .upcoming: .date
            case .noUpcoming, .loading: .neutral
            case .failed: .warning
            }
        }

        public var id: AddressKey { key }

        /// Raden under datumet på huvudkortet när nästa tömning är i dag. `nil` alla andra dagar.
        public var dayNote: String? {
            guard case .upcoming(let pickup) = status, pickup.daysUntil == 0 else { return nil }
            return pickup.estimated
                ? "Kärlen ska stå ute i dag, om tömningen kommer som beräknat."
                : "Kärlen ska stå ute i dag."
        }

        /// Alla fraktioner som text, så att VoiceOver kan läsa dem även när raden bara visar ikoner.
        public var accessibilityLabel: String {
            var parts = [title, lines.accessibilityLabel, summary]
            if refreshFailed { parts.append("Kunde inte uppdateras, visar senast hämtade schema") }
            if case .upcoming(let pickup) = status {
                parts.append(pickup.fractions.map(\.info.name).joined(separator: ", "))
            }
            if let scheduleEnding { parts.append(scheduleEnding.spokenText) }
            // De hårda mellanslagen gäller bara radbrytningen. VoiceOver och Röststyrning får vanliga mellanslag.
            return parts.joined(separator: ", ").replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    public let primary: Entry?
    public let others: [Entry]

    /// `remindersAllowed` är sant när iOS tillåter notiser, `remindersDenied` när iOS har nekat dem. Är frågan inte ställd än
    /// är båda falska, och raderna visar då det planerade läget.
    public static func make(addresses: [SavedAddress], schedules: [AddressKey: CachedSchedule], settings: ReminderSettings, now: Date, remindersAllowed: Bool = true, remindersDenied: Bool = false, liveActivity: ExistingActivity? = nil, liveActivitiesEnabled: Bool = true, liveActivityError: String? = nil, missedReminder: String? = nil, reserveAt: Date? = nil, household: HouseholdState = .empty, ownPlacedOut: Set<PlacedOut> = [], silencedPickups: Set<PlacedOut> = []) -> HomeContent {
        let today = StockholmClock.today(now: now)
        let primaryAddress = addresses.first(where: \.isPrimary) ?? addresses.first
        let primary = primaryAddress.map { address in
            entry(address, schedule: schedules[address.key], settings: settings, today: today, now: now, asRow: false, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt, household: household, ownPlacedOut: ownPlacedOut, silencedPickups: silencedPickups)
        }
        let others = addresses
            .filter { $0.key != primaryAddress?.key }
            .map { address in
                // Samma regel som huvudkortet, men utan Live Activity och reservnotis. "Påminnelsen har passerat" räknas
                // här, eftersom Utställt och väntande aktiviteter bara finns för huvudadressen.
                var notificationsOnly = settings
                notificationsOnly.liveActivityOn = false
                let schedule = schedules[address.key]
                let missed = address.notificationsOn && remindersAllowed
                    ? AddressDetail.missedReminder(events: schedule?.response?.events ?? [], settings: settings, now: now)
                    : nil
                return entry(address, schedule: schedule, settings: notificationsOnly, today: today, now: now, asRow: true, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: nil, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: nil, missedReminder: missed, reserveAt: nil, household: household, ownPlacedOut: ownPlacedOut, silencedPickups: silencedPickups)
            }
        return HomeContent(primary: primary, others: others)
    }

    private static func entry(_ address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, today: DayDate, now: Date, asRow: Bool, remindersAllowed: Bool, remindersDenied: Bool, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?, household: HouseholdState, ownPlacedOut: Set<PlacedOut>, silencedPickups: Set<PlacedOut>) -> Entry {
        let status = status(of: schedule, today: today)
        let refreshFailed = schedule?.response != nil && schedule?.lastError != nil
        var rowReminder: RowReminder?
        var primaryReminder: PrimaryReminder?
        var scheduleEnding: ScheduleEnding?
        let summary: String
        var nextPickup: DayDate?
        switch status {
        case .upcoming(let pickup):
            nextPickup = pickup.date
            // Raderna under Fler adresser visar ingen sådan rad, så VoiceOver ska inte läsa den heller.
            scheduleEnding = asRow ? nil : ScheduleEnding.make(schedule?.response?.schedule, today: today)
            // Hårt mellanslag före mittpunkten, så att den aldrig börjar en rad.
            summary = SwedishFormat.estimated(
                "\(SwedishFormat.shortDate(pickup.date))\u{00A0}· \(SwedishFormat.relative(days: pickup.daysUntil))",
                pickup.estimated
            )
            // Raden visar det planerade läget även när iOS inte har frågat än. Bara nekade notiser ger det nekade läget.
            let notifications = address.notificationsOn && (asRow ? !remindersDenied : remindersAllowed)
            let skipping = skippedDays(for: address.key, ownPlacedOut: ownPlacedOut, silencedPickups: silencedPickups)
            let text = { reminderText(notifications: notifications, settings: settings, events: schedule?.response?.events ?? [], skipping: skipping, today: today, now: now, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt) }
            if !asRow {
                primaryReminder = PrimaryReminder(text: text(), isOn: notifications, isDenied: remindersDenied, isWanted: address.notificationsOn)
            } else if address.notificationsOn {
                if remindersDenied {
                    rowReminder = .denied
                } else if let missedReminder {
                    rowReminder = .missed(missedReminder)
                } else {
                    rowReminder = .scheduled(text())
                }
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
            lines: lines(for: address),
            status: status,
            refreshFailed: refreshFailed,
            reminder: primaryReminder,
            rowReminder: rowReminder,
            scheduleEnding: scheduleEnding,
            summary: summary,
            household: HouseholdLine.make(household: household, key: address.key, nextPickup: nextPickup, today: today, ownPlacedOut: ownPlacedOut, remindersOn: address.notificationsOn || (address.isPrimary && settings.liveActivityOn))
        )
    }

    /// Gatan eller områdets namn på första raden, och orten och kommunens hela namn på den andra. Ett område har hela
    /// sitt namn som gata och ingen ort: "Kaplansgården, Jularbo m.fl." och "Avesta kommun". Kommunen utelämnas när den
    /// bara upprepar orten, också i genitiv. Hårt mellanslag mellan gatunamn och nummer och före mittpunkten, så att
    /// raderna aldrig bryts där. Är namnet detsamma som gatan, som för ett område som sparats med sitt namn, står gatan
    /// inte en gång till, bara platsen.
    public static func lines(for address: SavedAddress) -> AddressLines {
        let trimmed = address.street.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = address.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatsName = trimmed.compare(name, options: [.caseInsensitive]) == .orderedSame
        let street = repeatsName ? "" : trimmed.replacing(/\ (?=\d)/, with: "\u{00A0}")
        return AddressLines(address: street, place: localityAndKommun(locality: address.locality, kommun: address.kommun))
    }

    /// Som `lines(for:)`, med adressens namn på första raden. För vyer där rubriken inte är adressens namn, som Hela
    /// schemat. Regeln om gatan tar då bara bort dubbletten: är namnet detsamma som gatan står det en gång, som namn.
    /// Saknar adressen både namn och gata står gatan kvar, så att adressen alltid syns.
    public static func namedLines(for address: SavedAddress) -> AddressLines {
        let base = lines(for: address)
        let name = address.displayName.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\ (?=\d)/, with: "\u{00A0}")
        return AddressLines(name: name, address: base.address, place: base.place)
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

    /// Påminnelsen gäller kvällen före en hämtning eller samma morgon, i svensk tid. Har tiden för nästa hämtning redan
    /// passerat räknas den från nästa hämtning efter den. Finns ingen sådan visas en neutral text.
    /// Texten ska vara sann: en tid för Live Activity lovas bara när en aktivitet finns hos systemet.
    private static func reminderText(notifications: Bool, settings: ReminderSettings, events: [PickupEvent], skipping: Set<DayDate>, today: DayDate, now: Date, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?) -> String {
        if settings.liveActivityOn, let liveActivity {
            guard liveActivity.isPending else { return "Live Activity visas nu" }
            // En tid som redan passerat lovas inte, även om aktiviteten står kvar som väntande.
            if liveActivity.start > now {
                // Aktiviteten och notiserna för samma tömning nämns tillsammans. Står bara aktiviteten ser det ut som att
                // notisen är av.
                let notes = notifications ? notificationDates(for: liveActivity.pickupDate, settings: settings, skipping: skipping, now: now) : []
                return upcomingText(notifications: notes, activityStart: liveActivity.start)
            }
        }
        // Felet visas även med notiser på. Annars kan kortet lova en senare tömning när nästa står utan påminnelse.
        if settings.liveActivityOn, let liveActivityError { return liveActivityError }
        guard notifications || settings.liveActivityOn else { return reminderTitle() }
        guard notifications else {
            return liveActivitiesEnabled ? "Ingen Live Activity planerad" : "Live Activities är avstängda"
        }
        // En reservnotis som ligger framför är den påminnelse som gäller just nu.
        if let reserveAt { return "Reservpåminnelse kl. \(AddressDetail.clock(of: reserveAt))" }
        if let missedReminder { return missedReminder }
        if let next = ReminderTime.next(events: events, settings: settings, now: now, skipping: skipping) {
            return upcomingText(notifications: notificationDates(for: next.pickup, settings: settings, skipping: skipping, now: now), activityStart: nil)
        }
        return "Påminnelser på"
    }

    /// Notistiderna som är kvar för en tömning, i tidsordning: en per påslaget val.
    private static func notificationDates(for pickup: DayDate, settings: ReminderSettings, skipping: Set<DayDate>, now: Date) -> [Date] {
        guard !skipping.contains(pickup) else { return [] }
        return settings.enabledTimings
            .map { ReminderTime.date(forPickup: pickup, timing: $0, settings: settings) }
            .filter { $0 > now }
            .sorted()
    }

    /// Alla påminnelser som är kvar för samma tömning, i tidsordning. Bara notiser: "Påminnelse söndag kl. 15:00 och måndag
    /// kl. 06:00". Med en aktivitet får varje tid sitt slag: "Notis och Live Activity söndag kl. 15:00, notis måndag kl. 06:00".
    /// En notis inom en minut från starten räknas som samma tid, också när den har blivit reserv.
    private static func upcomingText(notifications: [Date], activityStart: Date?) -> String {
        guard let activityStart else {
            return "Påminnelse " + notifications.map(startText).joined(separator: " och ")
        }
        var moments: [(date: Date, label: String)] = []
        var activityPlaced = false
        for date in notifications {
            if !activityPlaced, abs(date.timeIntervalSince(activityStart)) < 60 {
                moments.append((activityStart, "notis och Live Activity"))
                activityPlaced = true
            } else {
                moments.append((date, "notis"))
            }
        }
        if !activityPlaced { moments.append((activityStart, "Live Activity")) }
        let text = moments.sorted { $0.date < $1.date }.map { "\($0.label) \(startText($0.date))" }.joined(separator: ", ")
        return capitalized(text)
    }

    /// Tömningarna för en adress som saknar påminnelser: mina egna utställda och de som hushållet har tystat. Samma mängd som
    /// planeraren får, så att texterna aldrig lovar en påminnelse som planeraren har tagit bort.
    static func skippedDays(for key: AddressKey, ownPlacedOut: Set<PlacedOut>, silencedPickups: Set<PlacedOut>) -> Set<DayDate> {
        Set(ownPlacedOut.union(silencedPickups).filter { $0.key == key }.map(\.date))
    }

    /// "tisdag kl. 18:00", i svensk tid.
    private static func startText(_ date: Date) -> String {
        "\(SwedishFormat.weekdayName(StockholmClock.today(now: date))) kl. \(AddressDetail.clock(of: date))"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
