import Foundation

/// Hemskärmens innehåll, räknat från sparade adresser och scheman och given tid.
/// Allt räknas lokalt: dagar, datum och påminnelsetext kommer aldrig från sparade `next`-fält.
public struct HomeContent: Equatable, Sendable {
    /// Valets namn på huvudkortet, i adressvyn och i snabbmenyn: "Påminn mig kvällen före" eller "Påminn mig samma morgon".
    public static func reminderTitle(timing: ReminderTiming) -> String { timing.toggleTitle }
    /// VoiceOvers åtgärd för samma val, på huvudkortet och raderna.
    public static func reminderActionTitle(isOn: Bool, timing: ReminderTiming) -> String { timing.actionTitle(isOn: isOn) }

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
        /// "Påminn mig kvällen före" eller "Påminn mig samma morgon", eller "Notiser är avstängda i iOS".
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
        init(text: String, isOn: Bool, isDenied: Bool, isWanted: Bool, timing: ReminderTiming) {
            self.isOn = isOn
            self.isDenied = isDenied
            // Inbjudan betyder att varken notis eller Live Activity är på.
            line = text == timing.toggleTitle ? nil : text
            showsDeniedNotice = isDenied && isWanted
            title = isDenied ? RowReminder.denied.text : timing.toggleTitle
            // Inbjudan är redan rubriken, och "Påminnelser på" säger bara det reglaget redan visar.
            if text == timing.toggleTitle || text == "Påminnelser på" {
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
    public static func make(addresses: [SavedAddress], schedules: [AddressKey: CachedSchedule], settings: ReminderSettings, now: Date, remindersAllowed: Bool = true, remindersDenied: Bool = false, liveActivity: ExistingActivity? = nil, liveActivitiesEnabled: Bool = true, liveActivityError: String? = nil, missedReminder: String? = nil, reserveAt: Date? = nil, household: HouseholdState = .empty, ownPlacedOut: Set<PlacedOut> = []) -> HomeContent {
        let today = StockholmClock.today(now: now)
        let primaryAddress = addresses.first(where: \.isPrimary) ?? addresses.first
        let primary = primaryAddress.map { address in
            entry(address, schedule: schedules[address.key], settings: settings, today: today, now: now, asRow: false, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt, household: household, ownPlacedOut: ownPlacedOut)
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
                return entry(address, schedule: schedule, settings: notificationsOnly, today: today, now: now, asRow: true, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: nil, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: nil, missedReminder: missed, reserveAt: nil, household: household, ownPlacedOut: ownPlacedOut)
            }
        return HomeContent(primary: primary, others: others)
    }

    private static func entry(_ address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, today: DayDate, now: Date, asRow: Bool, remindersAllowed: Bool, remindersDenied: Bool, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?, household: HouseholdState, ownPlacedOut: Set<PlacedOut>) -> Entry {
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
            let text = { reminderText(notifications: notifications, settings: settings, events: schedule?.response?.events ?? [], today: today, now: now, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt) }
            if !asRow {
                primaryReminder = PrimaryReminder(text: text(), isOn: notifications, isDenied: remindersDenied, isWanted: address.notificationsOn, timing: settings.timing)
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
            household: HouseholdLine.make(household: household, key: address.key, nextPickup: nextPickup, today: today, ownPlacedOut: ownPlacedOut)
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
    private static func reminderText(notifications: Bool, settings: ReminderSettings, events: [PickupEvent], today: DayDate, now: Date, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?) -> String {
        if settings.liveActivityOn, let liveActivity {
            guard liveActivity.isPending else { return "Live Activity visas nu" }
            // En tid som redan passerat lovas inte, även om aktiviteten står kvar som väntande.
            if liveActivity.start > now {
                let day = StockholmClock.today(now: liveActivity.start)
                let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: liveActivity.start)
                let time = SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                // Notis och Live Activity startar vid samma tid. Står bara aktiviteten ser det ut som att notisen är av.
                let what = notifications ? "Notis och Live Activity" : "Live Activity"
                return "\(what) \(SwedishFormat.weekdayName(day)) kl. \(time)"
            }
        }
        // Felet visas även med notiser på. Annars kan kortet lova en senare tömning när nästa står utan påminnelse.
        if settings.liveActivityOn, let liveActivityError { return liveActivityError }
        guard notifications || settings.liveActivityOn else { return settings.timing.toggleTitle }
        guard notifications else {
            return liveActivitiesEnabled ? "Ingen Live Activity planerad" : "Live Activities är avstängda"
        }
        // En reservnotis som ligger framför är den påminnelse som gäller just nu.
        if let reserveAt { return "Reservpåminnelse kl. \(AddressDetail.clock(of: reserveAt))" }
        if let missedReminder { return missedReminder }
        for event in ScheduleLogic.upcoming(events, today: today) {
            guard ReminderTime.date(forPickup: event.date, settings: settings) > now else { continue }
            let day = ReminderTime.reminderDay(forPickup: event.date, timing: settings.timing)
            return "Påminnelse \(SwedishFormat.weekdayName(day)) kl. \(SwedishFormat.clock(minutes: settings.activeMinutes))"
        }
        return "Påminnelser på"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
