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

    /// Texten under delen för valet i inställningarna.
    public var sectionFooter: String {
        switch self {
        case .eveningBefore:
            "Dagen före tömningen, mellan 15:00 och 23:00."
        case .sameMorning:
            "Samma dag som tömningen, mellan 05:00 och 09:00. Minst en påminnelse är på. Notiser slår du på och av per adress."
        }
    }

    /// När tiden för tömningen närmast framför redan har passerat.
    var missedText: String {
        switch self {
        case .eveningBefore: "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
        case .sameMorning: "Tömning i dag. Påminnelsen för i morse har redan passerat."
        }
    }
}
