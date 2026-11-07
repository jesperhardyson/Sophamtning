import Foundation

/// Vad "Hitta område med senaste tömningen" visar.
public enum AreaFinderState: Equatable, Sendable {
    case idle
    case searching
    /// Exakt ett område hade hämtning den dagen.
    case match(SearchHit)
    /// Flera områden. Inget väljs automatiskt.
    case multiple([SearchHit])
    /// Schemat täcker dagen, men inget område hade hämtning.
    case noPickup
    /// Schemat täcker inte dagen.
    case outsideSchedule
    /// Det gick inte att avgöra, och det säger inget om området.
    case failed

    /// Träffar visas alltid, även när en källa inte svarade. Utan träffar räknas bara ett fullständigt svar
    /// med bedömt datum som "ingen hämtning" eller "utanför schemat". Allt annat är `failed`.
    public static func from(_ response: SearchResponse) -> AreaFinderState {
        switch response.addresses.count {
        case 0:
            guard response.failed.isEmpty, let covered = response.dateCovered else { return .failed }
            return covered ? .noPickup : .outsideSchedule
        case 1:
            return .match(response.addresses[0])
        default:
            return .multiple(response.addresses)
        }
    }

    /// Sant när minst ett område hittades. Då, och bara då, vibrerar arket.
    public var foundAreas: Bool {
        switch self {
        case .match, .multiple: true
        case .idle, .searching, .noPickup, .outsideSchedule, .failed: false
        }
    }
}

/// Texterna om tömningarna. Datum utan veckodag.
public enum AreaFinderText {
    /// Visas när en träff kommer fram trots att en källa inte svarade.
    public static let partialNotice = "En källa svarade inte, så fler områden kan finnas."

    /// Kommunens namn behövs i listan först när träffarna gäller mer än en kommun.
    public static func showsKommun(_ hits: [SearchHit]) -> Bool {
        Set(hits.map(\.kommun)).count > 1
    }

    private static let question = "Stämmer det? En försenad tömning kan ge fel område."

    /// Kontrolltexten för en enskild träff.
    public static func check(_ pickups: Pickups?, today: DayDate) -> String {
        [dates(pickups, today: today, verb: true), question].compactMap { $0 }.joined(separator: " ")
    }

    /// Kortare text för raderna i listan med flera träffar. `nil` utan datum.
    public static func summary(_ pickups: Pickups?, today: DayDate) -> String? {
        dates(pickups, today: today, verb: false)
    }

    /// "Tömningar 13 okt och 27 okt. Nästa är 10 nov." Passerat nästa datum heter "Nästa var".
    private static func dates(_ pickups: Pickups?, today: DayDate, verb: Bool) -> String? {
        guard let pickups else { return nil }
        var parts: [String] = []
        if let previous = previousSentence(pickups.previous) { parts.append(previous) }
        if let next = pickups.next {
            let lead = next < today ? "Nästa var" : (verb ? "Nästa är" : "Nästa")
            parts.append("\(lead) \(SwedishFormat.dayMonth(next)).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func previousSentence(_ days: [DayDate]) -> String? {
        let texts = days.map(SwedishFormat.dayMonth)
        switch texts.count {
        case 0: return nil
        case 1: return "Tömning \(texts[0])."
        default: return "Tömningar \(texts.dropLast().joined(separator: ", ")) och \(texts[texts.count - 1])."
        }
    }
}
