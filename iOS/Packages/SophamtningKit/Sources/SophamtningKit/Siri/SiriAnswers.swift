import Foundation

/// Adressen en fråga till Siri gäller.
public enum SiriAddress: Equatable, Sendable {
    case address(SavedAddress)
    /// Inga adresser är sparade.
    case none
    /// Den valda adressen är inte sparad längre, till exempel borttagen efter att genvägen skapades.
    case removed
}

/// Kortet Siri visar under svaret: kalenderbladet, dagar kvar och kärlen den dagen.
public struct SiriCard: Equatable, Sendable {
    public let date: DayDate
    /// "Om 13 dagar", "I morgon", eller med "Ca" först för ett beräknat datum.
    public let title: String
    public let fractions: [String]
    /// Fraktionernas namn och ikoner ur schemat. Okända id:n får reservvärden av `ScheduleLogic.displayInfo`.
    public let info: [String: FractionInfo]

    public init(date: DayDate, title: String, fractions: [String], info: [String: FractionInfo]) {
        self.date = date
        self.title = title
        self.fractions = fractions
        self.info = info
    }
}

public struct SiriAnswer: Equatable, Sendable {
    public let text: String
    public let card: SiriCard?
}

/// Vad Ställ ut kärlen ska göra: markera en tömning, eller bara svara.
public enum SiriPlaceOut: Equatable, Sendable {
    case placeOut(PlacedOut, name: String)
    case answer(String)
}

/// Siris svar, räknade från sparade adresser, schema och bockar och given tid. Samma regler som hemskärmen och widgeten:
/// bara det sparade schemat används, och ett tekniskt fel låter aldrig som att adressen saknas.
public enum SiriAnswers {
    public static let unreadable = "Sophämtning kan inte läsa schemat just nu. Lås upp telefonen och försök igen."
    public static let saveFailed = "Det gick inte att spara att kärlen är utställda. Försök igen i appen."

    public static func placedOutDone(name: String) -> String {
        "Klart. Kärlen för \(name) är utställda."
    }

    /// Adressens id för Siri och Genvägar: filnamnet, som bara jämförs och aldrig tolkas.
    public static func id(for address: SavedAddress) -> String {
        address.key.fileName
    }

    /// Utan id gäller huvudadressen, annars den första.
    public static func select(id: String?, in addresses: [SavedAddress]) -> SiriAddress {
        guard let id else {
            return (addresses.first(where: \.isPrimary) ?? addresses.first).map { .address($0) } ?? .none
        }
        return addresses.first { Self.id(for: $0) == id }.map { .address($0) } ?? .removed
    }

    public static func nextPickup(_ selected: SiriAddress, schedule: CachedSchedule?, placedOut: Set<PlacedOut>, now: Date) -> SiriAnswer {
        switch pickup(selected, schedule: schedule, now: now) {
        case .answer(let text):
            return SiriAnswer(text: text, card: nil)
        case .pickup(let address, let next):
            var text = "\(address.displayName): \(joined(next.names)) töms \(when(next))."
            if placedOut.contains(PlacedOut(key: address.key, date: next.date)) { text += " Kärlen är utställda." }
            let title = SwedishFormat.estimated(SwedishFormat.relative(days: next.days), next.estimated)
            let card = SiriCard(date: next.date, title: title.prefix(1).uppercased() + title.dropFirst(), fractions: next.fractions, info: next.info)
            return SiriAnswer(text: text, card: card)
        }
    }

    /// Ställ ut kärlen går när nästa tömning är i dag eller i morgon, som knappen Ställ ut kärlen.
    public static func placeOut(_ selected: SiriAddress, schedule: CachedSchedule?, placedOut: Set<PlacedOut>, now: Date) -> SiriPlaceOut {
        switch pickup(selected, schedule: schedule, now: now) {
        case .answer(let text):
            return .answer(text)
        case .pickup(let address, let next):
            let entry = PlacedOut(key: address.key, date: next.date)
            guard (0...1).contains(next.days) else {
                let date = SwedishFormat.estimated(SwedishFormat.longDate(next.date, capitalized: false), next.estimated)
                return .answer("Nästa tömning för \(address.displayName) är \(date). Kärlen kan markeras som utställda dagen före och samma dag.")
            }
            if placedOut.contains(entry) { return .answer("Kärlen för \(address.displayName) är redan utställda.") }
            return .placeOut(entry, name: address.displayName)
        }
    }

    // MARK: Gemensamt

    private struct Next {
        let date: DayDate
        let days: Int
        let estimated: Bool
        let fractions: [String]
        let names: [String]
        let info: [String: FractionInfo]
    }

    private enum Lookup {
        case pickup(SavedAddress, Next)
        case answer(String)
    }

    private static func pickup(_ selected: SiriAddress, schedule: CachedSchedule?, now: Date) -> Lookup {
        let address: SavedAddress
        switch selected {
        case .none: return .answer("Du har inte sparat någon adress i Sophämtning än.")
        case .removed: return .answer("Den adressen är inte sparad i Sophämtning längre.")
        case .address(let saved): address = saved
        }
        let name = address.displayName
        // Samma läge som widgeten och hemskärmen.
        switch WidgetContent.make(addresses: [address], schedule: schedule, now: now) {
        case .pickup(_, _, _, let fractions):
            let sameDay = WidgetContent.mediumRows(fractions, maxRows: .max).rows
            guard let first = sameDay.first else { return .answer(notFetched(name)) }
            let info = schedule?.response?.fractions ?? [:]
            let today = StockholmClock.today(now: now)
            return .pickup(address, Next(
                date: first.date,
                days: today.days(until: first.date),
                estimated: sameDay.contains(where: \.estimated),
                fractions: sameDay.map(\.fraction),
                names: sameDay.map { ScheduleLogic.displayInfo(for: $0.fraction, in: info).name },
                info: info
            ))
        case .noUpcoming: return .answer("Det finns inga kommande hämtningar för \(name).")
        case .notFound: return .answer("Källan hittar inte \(name) längre. Öppna Sophämtning och sök adressen igen.")
        case .noSchedule, .failed: return .answer(notFetched(name))
        case .unavailable: return .answer(unreadable)
        case .noAddress: return .answer("Du har inte sparat någon adress i Sophämtning än.")
        }
    }

    private static func notFetched(_ name: String) -> String {
        "Schemat för \(name) har inte hämtats än. Öppna Sophämtning så hämtas det."
    }

    /// "torsdag 19 november, om 13 dagar", "i morgon, lördag 7 november", med "ca" för ett beräknat datum.
    private static func when(_ next: Next) -> String {
        let date = SwedishFormat.longDate(next.date, capitalized: false)
        switch next.days {
        case 0, 1:
            return SwedishFormat.estimated("\(SwedishFormat.relative(days: next.days)), \(date)", next.estimated)
        default:
            let relative = next.estimated ? "om ca \(next.days) dagar" : SwedishFormat.relative(days: next.days)
            return "\(SwedishFormat.estimated(date, next.estimated)), \(relative)"
        }
    }

    /// "A", "A och B", "A, B och C".
    private static func joined(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " och " + last
    }
}

/// Det Siri läser från lagringen för en fråga: den valda adressen, dess schema och vilka tömningar som är utställda (mina och
/// hushållets). Skriver aldrig något.
public struct SiriData: Sendable {
    public let selected: SiriAddress
    public let schedule: CachedSchedule?
    public let placedOut: Set<PlacedOut>

    /// `nil` när filerna inte går att läsa, till exempel före första upplåsningen. Det är inte samma sak som att adressen saknas.
    public static func read(from store: LocalStore, addressId: String?) -> SiriData? {
        let addresses: [SavedAddress]
        switch store.addressesState() {
        case .missing: addresses = []
        case .value(let saved): addresses = saved
        case .unavailable, .unreadable: return nil
        }
        let selected = SiriAnswers.select(id: addressId, in: addresses)
        guard case .address(let address) = selected else { return SiriData(selected: selected, schedule: nil, placedOut: []) }
        let schedule: CachedSchedule?
        switch store.scheduleState(for: address.key) {
        case .missing: schedule = nil
        case .value(let saved): schedule = saved
        case .unavailable, .unreadable: return nil
        }
        var placedOut = Set(store.placedOut())
        if case .value(let household) = store.householdState() { placedOut.formUnion(household.marks.map(\.placedOut)) }
        return SiriData(selected: selected, schedule: schedule, placedOut: placedOut)
    }

    public func nextPickup(at now: Date) -> SiriAnswer {
        SiriAnswers.nextPickup(selected, schedule: schedule, placedOut: placedOut, now: now)
    }

    public func placeOut(at now: Date) -> SiriPlaceOut {
        SiriAnswers.placeOut(selected, schedule: schedule, placedOut: placedOut, now: now)
    }
}

/// Texterna om Siri i inställningarna.
public enum SiriTexts {
    public static let ownPhrase = "Vill du bara säga ”När töms soporna”? Öppna genvägarna nedan, lägg till genvägen och ge den det namn du vill säga. Appens namn kan också vara Sopor eller Soporna, till exempel ”När töms soporna i Sopor”."
}
