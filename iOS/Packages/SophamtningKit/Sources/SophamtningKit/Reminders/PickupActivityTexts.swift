import Foundation

/// Aktivitetens texter. De använder datum, aldrig "i morgon", eftersom innehållet inte uppdateras under natten.
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

    /// "Restavfall, Matavfall och Glas".
    public var fractionNames: String {
        let names = fractions.map(\.name)
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) och \(last)"
    }

    /// "Hemma: Restavfall och Matavfall".
    public var fractionsLine: String { "\(addressName): \(fractionNames)" }

    /// Fraktionerna som små chips på högst två rader. Alla får plats, och ingen döljs. Upp till tre ryms på en rad.
    public var fractionRows: [[ActivityFraction]] {
        guard fractions.count > 3 else { return fractions.isEmpty ? [] : [fractions] }
        let first = (fractions.count + 1) / 2
        return [Array(fractions.prefix(first)), Array(fractions.dropFirst(first))]
    }

    /// Fraktionerna går före varningen. Tar de två rader får varningen en, och kapas hellre än att något annat försvinner.
    public var warningLineLimit: Int {
        fractionRows.count > 1 ? 1 : 2
    }
}
