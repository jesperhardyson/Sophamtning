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

    /// Reglaget för påminnelsen på huvudkortet, som i adressvyn: av, på eller nekat i iOS.
    public struct PrimaryReminder: Equatable, Sendable {
        /// Notis kvällen före är på och tillåten i iOS.
        public let isOn: Bool
        /// iOS har nekat notiser. Reglaget är av, och en knapp öppnar Inställningar.
        public let isDenied: Bool
        /// "Påminn mig kvällen före", eller "Notiser är avstängda i iOS".
        public let title: String
        /// Raden under: när påminnelsen kommer ("Söndag kl. 18:00"), eller Live Activity ("Live Activity söndag kl. 17:30").
        public let detail: String?

        public init(isOn: Bool, isDenied: Bool, title: String, detail: String?) {
            self.isOn = isOn
            self.isDenied = isDenied
            self.title = title
            self.detail = detail
        }

        static let offTitle = "Påminn mig kvällen före"

        /// Byggs av huvudkortets text för påminnelsen. Inbjudan blir rubriken, och "Påminnelse söndag kl. 18:00" blir
        /// "Söndag kl. 18:00" under den.
        init(text: String, isOn: Bool, isDenied: Bool) {
            self.isOn = isOn
            self.isDenied = isDenied
            title = isDenied ? RowReminder.denied.text : Self.offTitle
            if text == Self.offTitle {
                detail = nil
            } else if text.hasPrefix("Påminnelse ") {
                let rest = text.dropFirst("Påminnelse ".count)
                detail = rest.prefix(1).uppercased() + rest.dropFirst()
            } else {
                detail = text
            }
        }
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public let key: AddressKey
        public let title: String
        /// Platsen: gatan eller området, orten och kommunen. "Storgatan 12, Krylbo · Avesta kommun".
        public let subtitle: String
        public let status: Status
        /// Senaste försöket att uppdatera misslyckades, men ett äldre schema visas.
        public let refreshFailed: Bool
        /// Huvudkortets rad för påminnelse. `nil` när det inte finns någon kommande hämtning, och alltid på raderna.
        public let reminderText: String?
        /// Huvudkortets reglage för påminnelsen. `nil` när det inte finns någon kommande hämtning, och alltid på raderna.
        public let reminder: PrimaryReminder?
        /// Radens påminnelse under "Fler adresser". Bara när notis är på för adressen och en hämtning kommer, och utan
        /// Live Activity, som bara gäller huvudadressen. Alltid `nil` på huvudkortet.
        public let rowReminder: RowReminder?
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
            // De hårda mellanslagen gäller bara radbrytningen. VoiceOver och Röststyrning får vanliga mellanslag.
            return parts.joined(separator: ", ").replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    public let primary: Entry?
    public let others: [Entry]

    /// `remindersAllowed` är sant när iOS tillåter notiser, `remindersDenied` när iOS har nekat dem. Är frågan inte ställd än
    /// är båda falska, och raderna visar då det planerade läget.
    public static func make(addresses: [SavedAddress], schedules: [AddressKey: CachedSchedule], settings: ReminderSettings, now: Date, remindersAllowed: Bool = true, remindersDenied: Bool = false, liveActivity: ExistingActivity? = nil, liveActivitiesEnabled: Bool = true, liveActivityError: String? = nil, missedReminder: String? = nil, reserveAt: Date? = nil) -> HomeContent {
        let today = StockholmClock.today(now: now)
        let primaryAddress = addresses.first(where: \.isPrimary) ?? addresses.first
        let primary = primaryAddress.map { address in
            entry(address, schedule: schedules[address.key], settings: settings, today: today, now: now, asRow: false, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt)
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
                return entry(address, schedule: schedule, settings: notificationsOnly, today: today, now: now, asRow: true, remindersAllowed: remindersAllowed, remindersDenied: remindersDenied, liveActivity: nil, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: nil, missedReminder: missed, reserveAt: nil)
            }
        return HomeContent(primary: primary, others: others)
    }

    private static func entry(_ address: SavedAddress, schedule: CachedSchedule?, settings: ReminderSettings, today: DayDate, now: Date, asRow: Bool, remindersAllowed: Bool, remindersDenied: Bool, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?) -> Entry {
        let status = status(of: schedule, today: today)
        let refreshFailed = schedule?.response != nil && schedule?.lastError != nil
        var reminder: String?
        var rowReminder: RowReminder?
        var primaryReminder: PrimaryReminder?
        let summary: String
        switch status {
        case .upcoming(let pickup):
            // Hårt mellanslag före mittpunkten, så att den aldrig börjar en rad.
            summary = SwedishFormat.estimated(
                "\(SwedishFormat.shortDate(pickup.date))\u{00A0}· \(SwedishFormat.relative(days: pickup.daysUntil))",
                pickup.estimated
            )
            // Raden visar det planerade läget även när iOS inte har frågat än. Bara nekade notiser ger det nekade läget.
            let notifications = address.notificationsOn && (asRow ? !remindersDenied : remindersAllowed)
            let text = { reminderText(notifications: notifications, settings: settings, events: schedule?.response?.events ?? [], today: today, now: now, liveActivity: liveActivity, liveActivitiesEnabled: liveActivitiesEnabled, liveActivityError: liveActivityError, missedReminder: missedReminder, reserveAt: reserveAt) }
            if !asRow {
                let shown = text()
                reminder = shown
                primaryReminder = PrimaryReminder(text: shown, isOn: notifications, isDenied: remindersDenied)
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
            subtitle: subtitle(for: address),
            status: status,
            refreshFailed: refreshFailed,
            reminderText: reminder,
            reminder: primaryReminder,
            rowReminder: rowReminder,
            summary: summary
        )
    }

    /// Gatan eller områdets namn, orten och kommunens hela namn: "Storgatan 12, Krylbo · Avesta kommun". Kommunen utelämnas
    /// när den bara upprepar orten, också i genitiv: "Stationsgatan 12, Uppsala", "Storgatan 3, Säter".
    /// Hårda mellanslag mellan gatunamn och nummer och före mittpunkten, så att raden aldrig bryts där.
    public static func subtitle(for address: SavedAddress) -> String {
        let street = address.street.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/\ (?=\d)/, with: "\u{00A0}")
        let locality = address.locality.trimmingCharacters(in: .whitespacesAndNewlines)
        let kommun = kommunDisplayName(address.kommun)
        let place = [street, locality].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !kommun.isEmpty, !kommunRepeatsLocality(kommun, locality: locality) else { return place }
        return place.isEmpty ? kommun : "\(place)\u{00A0}· \(kommun)"
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
    private static func reminderText(notifications: Bool, settings: ReminderSettings, events: [PickupEvent], today: DayDate, now: Date, liveActivity: ExistingActivity?, liveActivitiesEnabled: Bool, liveActivityError: String?, missedReminder: String?, reserveAt: Date?) -> String {
        if settings.liveActivityOn, let liveActivity {
            guard liveActivity.isPending else { return "Live Activity visas nu" }
            // En tid som redan passerat lovas inte, även om aktiviteten står kvar som väntande.
            if liveActivity.start > now {
                let day = StockholmClock.today(now: liveActivity.start)
                let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: liveActivity.start)
                let time = SwedishFormat.clock(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                return "Live Activity \(SwedishFormat.weekdayName(day)) kl. \(time)"
            }
        }
        // Felet visas även med notiser på. Annars kan kortet lova en senare tömning när nästa står utan påminnelse.
        if settings.liveActivityOn, let liveActivityError { return liveActivityError }
        guard notifications || settings.liveActivityOn else { return "Påminn mig kvällen före" }
        guard notifications else {
            return liveActivitiesEnabled ? "Ingen Live Activity planerad" : "Live Activities är avstängda"
        }
        // En reservnotis som ligger framför är den påminnelse som gäller just nu.
        if let reserveAt { return "Reservpåminnelse kl. \(AddressDetail.clock(of: reserveAt))" }
        if let missedReminder { return missedReminder }
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
