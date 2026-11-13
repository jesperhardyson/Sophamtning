import Foundation

/// Texterna under korten Notiser, Live Activity och Huvudadress i Inställningar, och under adresserna på sidan Notiser.
public enum ReminderSettingsTexts {
    /// Adresserna i hemskärmens ordning: huvudadressen först, sedan de andra som de sparades.
    public static func homeOrder(_ addresses: [SavedAddress]) -> [SavedAddress] {
        addresses.filter(\.isPrimary) + addresses.filter { !$0.isPrimary }
    }

    /// Under kortet Notiser: vilka adresser som får notiser, i hemskärmens ordning.
    public static func notificationsFooter(addresses: [String]) -> String {
        guard let last = addresses.last else { return "Ingen adress har notiser på. Slå på Påminn mig i adressen." }
        let names = addresses.count == 1 ? last : addresses.dropLast().joined(separator: ", ") + " och " + last
        return "Gäller \(names). Slå på eller av i varje adress."
    }

    /// Under kortet Live Activity, när det finns en huvudadress.
    public static func liveActivityFooter(primary: String) -> String {
        "Visas för huvudadressen, \(primary)."
    }

    /// Under kortet Huvudadress.
    public static let primaryFooter = "Används av Live Activity, widgetar och Siri."

    /// Under adresserna på sidan Notiser.
    public static let addressesFooter = "Samma som Påminn mig i varje adress. Stäng av alla för att inte få några notiser."
}
