import Foundation

/// En Live Activity som finns hos systemet, väntande eller pågående.
public struct ExistingActivity: Equatable, Sendable {
    public let id: String
    public let key: AddressKey
    public let pickupDate: DayDate
    public let content: PickupActivityContent
    public let isPending: Bool
    /// Den planerade starten. En väntande aktivitet går inte att flytta, så en ändrad påminnelsetid kräver en ny.
    public let start: Date

    public init(id: String, key: AddressKey, pickupDate: DayDate, content: PickupActivityContent, isPending: Bool, start: Date) {
        self.id = id
        self.key = key
        self.pickupDate = pickupDate
        self.content = content
        self.isPending = isPending
        self.start = start
    }
}

public enum LiveActivityAction: Equatable, Sendable {
    case start(PlannedLiveActivity)
    case update(id: String, PickupActivityContent)
    case remove(id: String)
}

/// Jämför önskad aktivitet med de som finns, så att bara skillnaden ändras.
public enum LiveActivityDiff {
    /// Sekunder som räknas som samma start.
    static let startTolerance: TimeInterval = 1

    /// - Parameter primary: huvudadressen. `nil` betyder att den önskade aktivitetens adress gäller, och finns ingen sådan
    ///   finns ingen huvudadress. Behövs för att en pågående aktivitet ska leva kvar när ingen nästa tömning är planerad.
    public static func actions(desired: PlannedLiveActivity?, existing: [ExistingActivity], today: DayDate, enabled: Bool, primary: AddressKey? = nil) -> [LiveActivityAction] {
        guard enabled else { return existing.map { .remove(id: $0.id) } }
        let main = primary ?? desired?.key

        var removals: [String] = []
        var kept: ExistingActivity?
        // Pågående går före väntande, så att den som redan visas är den som blir kvar av en dubblett.
        let ordered = existing.filter { !$0.isPending } + existing.filter(\.isPending)
        for activity in ordered {
            if let desired, activity.key == desired.key, activity.pickupDate == desired.pickupDate {
                if kept == nil { kept = activity } else { removals.append(activity.id) }
            } else if activity.isPending || activity.pickupDate != today || activity.key != main {
                removals.append(activity.id)
            }
            // Annars: startad för i dag på huvudadressen. Den lever tills Utställt eller systemets tidsgräns.
        }

        guard let desired else { return removals.map { .remove(id: $0) } }
        guard let kept else { return removals.map { .remove(id: $0) } + [.start(desired)] }
        if kept.isPending {
            let sameStart = abs(kept.start.timeIntervalSince(desired.start)) < startTolerance
            if kept.content != desired.content || !sameStart {
                // En väntande aktivitet ersätts, eftersom en uppdatering inte når aviseringens text och starttid.
                return (removals + [kept.id]).map { .remove(id: $0) } + [.start(desired)]
            }
        } else if kept.content != desired.content {
            return removals.map { .remove(id: $0) } + [.update(id: kept.id, desired.content)]
        }
        return removals.map { .remove(id: $0) }
    }
}

extension PlannedLiveActivity {
    public enum StartMode: Equatable, Sendable {
        case immediately
        case scheduled(Date)
    }

    /// Hur aktiviteten ska läggas in just nu. Har starttiden hunnit passera sedan planeringen startas den direkt, så att
    /// en schemalagd start aldrig ligger i det förflutna.
    public func startMode(now: Date) -> StartMode {
        startsImmediately || start <= now ? .immediately : .scheduled(start)
    }
}

extension PickupActivityContent {
    public static let alertTitle = "Ställ ut kärlen"

    /// "måndag 9 november", eller "ca måndag 9 november".
    private var lowercasedDate: String {
        SwedishFormat.estimated(dateText.prefix(1).lowercased() + dateText.dropFirst(), estimated)
    }

    /// "Hemma: Restavfall och Matavfall töms måndag 9 november." Med "ca" när datumet är beräknat och varningen sist.
    public var alertBody: String {
        var text = "\(fractionsLine) töms \(lowercasedDate)."
        if let warning { text += " \(warning)" }
        return text
    }

    /// "Hemma · måndag 9 november".
    public var subtitle: String { "\(addressName) · \(lowercasedDate)" }

    /// "Mån 9 nov", eller "ca mån 9 nov".
    public var shortDate: String {
        estimated ? "ca " + shortDateText.lowercased() : shortDateText
    }

    /// "Mån 9", eller "ca mån 9". För Dynamic Islands kompakta läge.
    public var compactDate: String {
        shortDate.split(separator: " ").dropLast().joined(separator: " ")
    }

    /// "Hemma: Restavfall och Matavfall".
    public var fractionsLine: String {
        let names = fractions.map(\.name)
        guard let last = names.last, names.count > 1 else { return "\(addressName): \(names.first ?? "")" }
        return "\(addressName): \(names.dropLast().joined(separator: ", ")) och \(last)"
    }
}

/// Att soporna är utställda, som knappen **Utställt** utför det. Körs utanför appens process.
public enum PlacedOutAction {
    /// Sparar valet och avslutar aktiviteten. Ett skrivfel kastas inte utanför: aktiviteten avslutas ändå, och nästa planering
    /// hanterar det. Svarar med om valet sparades.
    @discardableResult
    public static func perform(store: LocalStore, entry: PlacedOut, today: DayDate, end: @Sendable () async -> Void) async -> Bool {
        let saved = (try? store.markPlacedOut(entry, today: today)) != nil
        await end()
        return saved
    }
}
