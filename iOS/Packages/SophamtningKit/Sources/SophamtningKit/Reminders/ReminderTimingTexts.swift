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

    /// Reglagets namn på huvudkortet, i adressvyn och i snabbmenyn.
    public var toggleTitle: String { "Påminn mig \(phrase)" }

    /// VoiceOvers åtgärd för samma reglage.
    public func actionTitle(isOn: Bool) -> String {
        "\(isOn ? "Stäng av" : "Slå på") påminnelse \(phrase)"
    }

    /// Värdet på raden Påminnelse i inställningarna: "Kvällen före, 18:00".
    public func settingsValue(minutes: Int) -> String {
        "\(title), \(SwedishFormat.clock(minutes: minutes))"
    }

    /// Texten under listan med tider.
    public var settingsFooter: String {
        switch self {
        case .eveningBefore:
            "Påminnelsen kommer kvällen före, mellan 15:00 och 23:00. En Live Activity försvinner senast 12 timmar efter starten, så en sen tid håller den kvar längre på morgonen. Notiser väljer du per adress."
        case .sameMorning:
            "Påminnelsen kommer samma morgon som tömningen, mellan 05:00 och 09:00. En Live Activity syns tills du trycker Utställt, eller i högst 12 timmar. Notiser väljer du per adress."
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
