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
    /// Hur länge efter sin starttid en aktivitet får stå som väntande innan den räknas som utebliven. Hur lång tid systemet
    /// kan dröja är okänt: en start är sedd med kort marginal, men ingen mätning finns. Därför en försiktig gräns.
    public static let overdueMargin: TimeInterval = 5 * 60

    /// Väntande trots att starttiden passerat med marginal. Den går inte att lita på, och räknas inte som en påminnelse.
    public static func isOverdue(_ activity: ExistingActivity, now: Date) -> Bool {
        activity.isPending && now > activity.start.addingTimeInterval(overdueMargin)
    }

    /// Listan utför inte sig själv i ordning: `AppModel` startar den nya före borttagningarna, så att ett fel lämnar den gamla kvar.
    ///
    /// - Parameters:
    ///   - primary: huvudadressen. `nil` betyder att den önskade aktivitetens adress gäller, och finns ingen sådan
    ///     finns ingen huvudadress. Behövs för att en pågående aktivitet ska leva kvar när ingen nästa tömning är planerad.
    ///   - canStart: falskt i bakgrunden. Då startas inget, och en väntande aktivitet för samma tömning behålls, eftersom
    ///     den annars försvinner utan ersättning.
    ///   - todayContent: dagens innehåll för huvudadressen, så att en pågående aktivitet får ny varning eller nytt namn.
    public static func actions(desired: PlannedLiveActivity?, existing: [ExistingActivity], today: DayDate, enabled: Bool, primary: AddressKey? = nil, canStart: Bool = true, now: Date = .distantPast, todayContent: PickupActivityContent? = nil) -> [LiveActivityAction] {
        guard enabled else { return existing.map { .remove(id: $0.id) } }
        let main = primary ?? desired?.key

        var removals: [String] = []
        var kept: ExistingActivity?
        var keptToday: ExistingActivity?
        // Pågående går före väntande, så att den som redan visas är den som blir kvar av en dubblett.
        let ordered = existing.filter { !$0.isPending } + existing.filter(\.isPending)
        for activity in ordered {
            if let desired, activity.key == desired.key, activity.pickupDate == desired.pickupDate {
                if kept == nil { kept = activity } else { removals.append(activity.id) }
            } else if !activity.isPending, activity.pickupDate == today, activity.key == main, keptToday == nil {
                // Startad för i dag på huvudadressen. Den lever tills Utställt eller systemets tidsgräns.
                keptToday = activity
            } else {
                removals.append(activity.id)
            }
        }

        var result: [LiveActivityAction] = []
        if let keptToday, let todayContent, keptToday.content != todayContent {
            result.append(.update(id: keptToday.id, todayContent))
        }
        guard let desired else { return removals.map { .remove(id: $0) } + result }
        guard let kept else {
            return removals.map { .remove(id: $0) } + result + (canStart ? [.start(desired)] : [])
        }
        if kept.isPending {
            let sameStart = abs(kept.start.timeIntervalSince(desired.start)) < startTolerance
            if canStart, kept.content != desired.content || !sameStart || isOverdue(kept, now: now) {
                // En väntande aktivitet ersätts, eftersom en uppdatering inte når aviseringens text och starttid.
                return (removals + [kept.id]).map { .remove(id: $0) } + result + [.start(desired)]
            }
        } else if kept.content != desired.content {
            result.append(.update(id: kept.id, desired.content))
        }
        return removals.map { .remove(id: $0) } + result
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
