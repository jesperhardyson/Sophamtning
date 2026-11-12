import Foundation

/// Texterna som följer valet mellan kvällen före och samma morgon.
extension ReminderTiming {
    /// "kvällen före" eller "samma morgon", inne i en mening.
    var phrase: String {
        switch self {
        case .eveningBefore: "kvällen före"
        case .sameMorning: "samma morgon"
        }
    }

    /// Valets namn i listan och i inställningens värde.
    public var title: String {
        switch self {
        case .eveningBefore: "Kvällen före"
        case .sameMorning: "Samma morgon"
        }
    }

    /// Texten under delen för valet i inställningarna, med den valda tiden: "Dagen före tömningen kl. 18:00."
    public func sectionFooter(minutes: Int) -> String {
        let time = SwedishFormat.clock(minutes: minutes)
        switch self {
        case .eveningBefore:
            return "Dagen före tömningen kl. \(time)."
        case .sameMorning:
            return "Samma dag som tömningen kl. \(time). Minst en påminnelse är på. Notiser slår du på och av per adress."
        }
    }

    /// Texten under listan med tider: vilka tider som går att välja.
    public var timesFooter: String {
        let first = SwedishFormat.clock(minutes: range.lowerBound)
        let last = SwedishFormat.clock(minutes: range.upperBound)
        return "Välj en tid mellan \(first) och \(last)."
    }

    /// När tiden för tömningen närmast framför redan har passerat.
    var missedText: String {
        switch self {
        case .eveningBefore: "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
        case .sameMorning: "Tömning i dag. Påminnelsen för i morse har redan passerat."
        }
    }
}
