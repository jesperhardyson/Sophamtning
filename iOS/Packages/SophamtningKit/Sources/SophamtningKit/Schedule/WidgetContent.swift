import Foundation

/// Widgetens innehåll för huvudadressen, räknat från sparade adresser och schema och given tid.
/// Allt räknas lokalt: dagar och datum kommer aldrig från sparade `next`-fält, och lägena följer `HomeContent`.
public enum WidgetContent: Equatable, Sendable {
    /// Det finns inga sparade adresser.
    case noAddress
    /// Filerna går inte att läsa just nu (till exempel skyddad data före första upplåsningen) eller är skadade.
    /// Det är inte samma sak som att adressen saknas, så widgeten ber om en senare uppdatering.
    case unavailable
    /// Schemat har inte hämtats än.
    case noSchedule(name: String)
    /// Schemat saknas och det senaste försöket misslyckades av tekniska skäl.
    case failed(name: String)
    /// Schemat saknas och källan svarade att adressen inte finns (404).
    case notFound(name: String)
    /// Schemat finns men har inga hämtningar från och med i dag.
    case noUpcoming(name: String)
    /// Nästa hämtning. `relative` och `shortDate` gäller första datumet och har "ca" först när det är uppskattat.
    /// `fractions` är första kommande datum per fraktion, sorterat på datum.
    case pickup(name: String, relative: String, shortDate: String, fractions: [FractionPickup])

    /// Efter ett läge utan läsbara filer försöker widgeten igen inom så här lång tid.
    public static let unavailableRetryInterval: TimeInterval = 15 * 60

    public static func make(addresses: [SavedAddress], schedule: CachedSchedule?, now: Date) -> WidgetContent {
        guard let address = addresses.first(where: \.isPrimary) ?? addresses.first else { return .noAddress }
        let name = address.displayName
        let today = StockholmClock.today(now: now)
        // Samma sanning som hemskärmen: läget kommer från `HomeContent`.
        let schedules = schedule.map { [address.key: $0] } ?? [:]
        let status = HomeContent.make(addresses: [address], schedules: schedules, settings: ReminderSettings(), now: now).primary?.status
        switch status {
        case .upcoming(let pickup):
            guard let response = schedule?.response else { return .noSchedule(name: name) }
            let fractions = ScheduleLogic.nextByFraction(response.events, today: today)
            return .pickup(
                name: name,
                relative: SwedishFormat.estimated(SwedishFormat.relative(days: pickup.daysUntil), pickup.estimated),
                shortDate: SwedishFormat.estimated(
                    pickup.estimated ? SwedishFormat.shortDate(pickup.date).lowercased() : SwedishFormat.shortDate(pickup.date),
                    pickup.estimated
                ),
                fractions: fractions
            )
        case .noUpcoming: return .noUpcoming(name: name)
        case .failed(.notFound): return .notFound(name: name)
        case .failed: return .failed(name: name)
        case .loading, nil: return .noSchedule(name: name)
        }
    }

    /// "Schemat slutar 10 jan" när schemat tar slut inom 14 dagar, för huvudadressen. Bara när widgeten visar en kommande
    /// hämtning, och aldrig för live-källor. Räknas från `now`, så att raden försvinner av sig själv när dagarna går.
    public static func scheduleEnding(addresses: [SavedAddress], schedule: CachedSchedule?, now: Date) -> ScheduleEnding? {
        guard case .pickup = make(addresses: addresses, schedule: schedule, now: now) else { return nil }
        return ScheduleEnding.make(schedule?.response?.schedule, today: StockholmClock.today(now: now))
    }

    /// Raderna i den mellanstora widgeten: bara kärlen som töms det datum som står på kalenderbladet, som i den lilla. Får de
    /// inte plats blir sista raden "+N till", så `hidden` gäller alltid samma tömning och aldrig ett senare datum.
    public static func mediumRows(_ fractions: [FractionPickup], maxRows: Int) -> (rows: [FractionPickup], hidden: Int) {
        guard let first = fractions.first else { return ([], 0) }
        let sameDay = fractions.filter { $0.date == first.date }
        let rows = sameDay.count > maxRows ? Array(sameDay.prefix(maxRows - 1)) : sameDay
        return (rows, sameDay.count - rows.count)
    }

    /// Datumet för ett senare kärl i widgetens VoiceOver: "mån 9 nov", eller "ca tors 12 nov" när det är uppskattat.
    public static func rowDate(_ pickup: FractionPickup) -> String {
        SwedishFormat.estimated(SwedishFormat.shortDate(pickup.date).lowercased(), pickup.estimated)
    }

    /// Tidslinjens poster: `now` och sedan varje svensk midnatt, `days` stycken. Widgeten byter dag då och räknar om allt.
    public static func timelineDates(from now: Date, days: Int) -> [Date] {
        let today = StockholmClock.today(now: now)
        return [now] + (0..<max(days, 0)).map { StockholmClock.date(on: today.adding(days: $0 + 1), minutes: 0) }
    }
}

/// Det widgeten läser från lagringen, en enda läsning per tidslinje. Skriver aldrig något.
public struct WidgetData: Equatable, Sendable {
    private enum Source: Equatable, Sendable {
        case unavailable
        case loaded(addresses: [SavedAddress], schedule: CachedSchedule?)
    }

    private let source: Source
    /// Hushållet från `household.json`, för "Utställt". Går filen inte att läsa visas ingen bock.
    private var household: HouseholdState = .empty

    /// Fraktionernas namn och ikoner ur det sparade schemat. Okända id:n får reservvärden av `ScheduleLogic.displayInfo`.
    public var fractionInfo: [String: FractionInfo] {
        if case .loaded(_, let schedule?) = source { return schedule.response?.fractions ?? [:] }
        return [:]
    }

    public static func read(from store: LocalStore) -> WidgetData {
        let addresses: [SavedAddress]
        switch store.addressesState() {
        case .missing: return WidgetData(source: .loaded(addresses: [], schedule: nil))
        case .value(let saved): addresses = saved
        // En fil som inte går att läsa eller tolka är inte "inga adresser".
        case .unavailable, .unreadable: return WidgetData(source: .unavailable)
        }
        guard let address = addresses.first(where: \.isPrimary) ?? addresses.first else {
            return WidgetData(source: .loaded(addresses: addresses, schedule: nil))
        }
        switch store.scheduleState(for: address.key) {
        case .missing: return WidgetData(source: .loaded(addresses: addresses, schedule: nil))
        case .value(let schedule):
            var data = WidgetData(source: .loaded(addresses: addresses, schedule: schedule))
            if case .value(let household) = store.householdState() { data.household = household }
            return data
        case .unavailable, .unreadable: return WidgetData(source: .unavailable)
        }
    }

    public func content(at now: Date) -> WidgetContent {
        switch source {
        case .unavailable: .unavailable
        case .loaded(let addresses, let schedule): WidgetContent.make(addresses: addresses, schedule: schedule, now: now)
        }
    }

    /// Raden om att schemat tar slut, eller `nil`.
    public func scheduleEnding(at now: Date) -> ScheduleEnding? {
        switch source {
        case .unavailable: nil
        case .loaded(let addresses, let schedule): WidgetContent.scheduleEnding(addresses: addresses, schedule: schedule, now: now)
        }
    }

    /// Sant när någon i hushållet har ställt ut kärlen för huvudadressens nästa tömning.
    public func placedOut(at now: Date) -> Bool { placedOutMark(at: now) != nil }

    /// Vem som ställde ut, "av Sofie" eller "av dig", eller `nil` utan bock.
    public func placedOutBy(at now: Date) -> String? {
        placedOutMark(at: now).map { HouseholdTexts.placedOutBy($0, participants: household.participants, myId: household.myId) }
    }

    private func placedOutMark(at now: Date) -> HouseholdMark? {
        guard case .loaded(let addresses, let schedule?) = source,
              household.role != .none, household.status != .removed,
              let address = addresses.first(where: \.isPrimary) ?? addresses.first,
              let events = schedule.response?.events,
              let next = ScheduleLogic.nextPickup(events, today: StockholmClock.today(now: now))?.date
        else { return nil }
        return HouseholdLogic.currentMark(for: address.key, nextPickup: next, in: household.marks)
    }

    /// Visningsinfo för en fraktion, med samma reservvärden som appen.
    public func info(for id: String) -> FractionInfo {
        ScheduleLogic.displayInfo(for: id, in: fractionInfo)
    }

    /// När widgeten ska läsa om själv: inom 15 minuter när filerna inte gick att läsa, annars `nil`
    /// (då laddas den om vid midnatt och när appen sparar något).
    public func reloadDate(after now: Date) -> Date? {
        source == .unavailable ? now.addingTimeInterval(WidgetContent.unavailableRetryInterval) : nil
    }
}
