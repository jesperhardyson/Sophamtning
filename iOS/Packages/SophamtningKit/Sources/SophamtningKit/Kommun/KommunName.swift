import Foundation

/// "Avesta kommun" blir "Avesta". Namn utan ordet "kommun" lämnas som de är.
/// Bara för det som skickas till API:t, till exempel `/omraden?plats=`. Det som visas använder `kommunDisplayName`.
public func shortKommunName(_ name: String) -> String {
    name.hasSuffix(" kommun") ? String(name.dropLast(" kommun".count)) : name
}

/// Kommunen som den visas: hela namnet från API:t, "Säters kommun". Samma överallt där kommunen står i appen.
public func kommunDisplayName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Sant när kommunens namn bara upprepar orten: "Uppsala kommun" och "Uppsala", "Säters kommun" och "Säter",
/// "Stockholms kommun" och "Stockholm", "Falu kommun" och "Falun". Utan hänsyn till skiftläge.
public func kommunRepeatsLocality(_ kommun: String, locality: String) -> Bool {
    let short = shortKommunName(kommunDisplayName(kommun))
    let place = locality.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !short.isEmpty, !place.isEmpty else { return false }
    let swedish = Locale(identifier: "sv_SE")
    let same = { (candidate: String) in
        short.compare(candidate, options: .caseInsensitive, locale: swedish) == .orderedSame
    }
    // Orten, orten i genitiv och Falun, vars kommun heter Falu.
    if same(place) || same(place + "s") { return true }
    return same("Falu") && place.compare("Falun", options: .caseInsensitive, locale: swedish) == .orderedSame
}
