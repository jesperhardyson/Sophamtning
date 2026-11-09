import Foundation

/// Det som en rad i områdesvalet visar, som på webbens områdessida: namnet, etiketten, dagen, platserna och platser med
/// andra dagar. Saknar träffen detaljer visas dagens rad med `detail`, och inget tyder på att området saknas.
public struct AreaRowContent: Equatable, Sendable {
    /// Områdets namn, "Askön, Nyhyttan m.fl.".
    public let title: String
    /// Den lilla etiketten, "Område 1", eller `nil`.
    public let label: String?
    /// "Måndag, udda vecka". Utan detaljer är det API:ts `detail`, "Måndag, udda vecka · Område 1".
    public let day: String?
    /// Platserna på en kort rad, "Askön, Nyhyttan, Klintbo, Snickarbo m.fl.", eller `nil`.
    public let places: String?
    /// Alla platser, "Askön, Nyhyttan, … och Rutbo", för VoiceOver och bekräftelsen. `nil` utan platser.
    public let allPlaces: String?
    /// Platser i området med en annan dag, som källan skrev dem.
    public let otherDays: [String]
    /// Hur många platser området har.
    public let placeCount: Int
    /// Sant när raden kommer från områdets detaljer. Annars är det dagens rad, med `detail` i dess stil.
    public let detailed: Bool

    /// Så många platser står på den korta raden innan "m.fl.".
    public static let shortPlaceCount = 4

    public init(title: String, label: String?, day: String?, places: String?, allPlaces: String?, otherDays: [String], placeCount: Int = 0, detailed: Bool = false) {
        self.title = title
        self.label = label
        self.day = day
        self.places = places
        self.allPlaces = allPlaces
        self.otherDays = otherDays
        self.placeCount = placeCount
        self.detailed = detailed
    }

    /// Sant när den korta raden inte visar alla platser. Då går listan att fälla ut.
    public var hidesPlaces: Bool { placeCount > Self.shortPlaceCount + 1 }

    /// "Visa alla 18 platser".
    public var showAllPlacesText: String { "Visa alla \(placeCount) platser" }

    /// Knappen i bekräftelsen: "Visa alla 18 platser", och "Visa färre platser" när listan är utfälld.
    public func placesToggleText(expanded: Bool) -> String {
        expanded ? "Visa färre platser" : showAllPlacesText
    }

    public static func make(_ hit: SearchHit) -> AreaRowContent {
        let detail = hit.detail?.trimmedNonEmpty
        guard let area = hit.area, let day = area.day.trimmedNonEmpty else {
            // Inga detaljer: dagens visning, med namnet och `detail`.
            return AreaRowContent(title: hit.street, label: nil, day: detail, places: nil, allPlaces: nil, otherDays: [])
        }
        let places = area.places.compactMap { place in place.trimmedNonEmpty }
        return AreaRowContent(
            title: hit.street,
            label: area.label?.trimmedNonEmpty,
            day: day,
            places: shortPlaces(places),
            allPlaces: places.isEmpty ? nil : listText(places),
            otherDays: area.otherDays.compactMap { text in text.trimmedNonEmpty },
            placeCount: places.count,
            detailed: true
        )
    }

    /// Rubriken över raderna med andra dagar, som på webben.
    public static let otherDaysHeading = "Vissa gator har en annan hämtdag"

    /// Hela raden som en text för VoiceOver, med alla platser: "Askön, Nyhyttan m.fl., Område 1, Måndag, udda vecka.
    /// Platser: Askön, Nyhyttan och Klintbo."
    public var accessibilityLabel: String {
        let head = [title, label, day].compactMap { part in part }.joined(separator: ", ")
        let others = otherDays.isEmpty ? [] : [Self.otherDaysHeading] + otherDays
        let tail = [allPlaces.map { list in "Platser: \(list)" }].compactMap { part in part } + others
        return ([head] + tail).map { part in part.hasSuffix(".") ? part : part + "." }.joined(separator: " ")
    }

    /// Den korta raden. Fler än en plats till än vad som får plats ger "m.fl.", så att "m.fl." aldrig står för en enda.
    static func shortPlaces(_ places: [String]) -> String? {
        guard !places.isEmpty else { return nil }
        guard places.count > shortPlaceCount + 1 else { return places.joined(separator: ", ") }
        return places.prefix(shortPlaceCount).joined(separator: ", ") + " m.fl."
    }

    /// "Askön, Nyhyttan och Klintbo".
    static func listText(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " och " + items[items.count - 1]
    }
}

/// Källans förklaring överst i områdesvalet. Texterna visas som källan skrev dem.
public struct AreaSourceNote: Equatable, Sendable, Identifiable {
    public let id: String
    /// Källans namn, som bara behövs när flera källor svarade.
    public let name: String
    public let explanation: String?
    /// Hjälpraden, där ett telefonnummer går att trycka på.
    public let help: AttributedString?

    /// En förklaring per källa som har något att säga. Utan källor blir listan tom, och då visas dagens meddelande.
    public static func notes(_ sources: [AreaSource]) -> [AreaSourceNote] {
        var seen = Set<String>()
        return sources.compactMap { source in
            guard seen.insert(source.id).inserted else { return nil }
            let explanation = source.explanation?.trimmedNonEmpty
            let help = source.help?.trimmedNonEmpty
            guard explanation != nil || help != nil else { return nil }
            return AreaSourceNote(id: source.id, name: source.name, explanation: explanation, help: help.map { text in linkingPhoneNumbers(text) })
        }
    }

    /// Texten med varje telefonnummer som en `tel:`-länk. Hittas inget nummer är texten oförändrad.
    public static func linkingPhoneNumbers(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else { return result }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let number = match.phoneNumber, let url = telURL(number),
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            result[lower..<upper].link = url
        }
        return result
    }

    /// "0226-64 55 00" blir `tel:0226645500`. Ett plustecken först behålls.
    static func telURL(_ number: String) -> URL? {
        let digits = number.filter { character in character.isASCII && character.isNumber }
        guard digits.count >= 5 else { return nil }
        let plus = number.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
        return URL(string: "tel:\(plus)\(digits)")
    }
}

/// Det som varningskortet överst i områdesvalet visar. Källans `explanation` står ordagrant, sedan en mening om att fel
/// område kan göra att man missar tömningen, och sist källans hjälprad. Saknas `explanation` visas `notice` i dess ställe,
/// så att varningen aldrig försvinner, och finns ingen text alls står ändå rubriken och konsekvensen. När `explanation` finns visas inte `notice` här, utan i bekräftelsearket.
public struct AreaWarning: Equatable, Sendable {
    /// En text i kortet. Källans namn behövs bara när flera källor svarade.
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let text: String
    }

    /// Hjälpraden, där telefonnumret går att trycka på.
    public struct Help: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let text: AttributedString
    }

    public static let title = "Du väljer området själv"
    public static let consequence = "Väljer du fel område kan du missa din tömning."

    /// Källans förklaring, eller `notice` när ingen källa har någon förklaring.
    public let explanations: [Entry]
    public let helps: [Help]

    /// Kortet finns alltid: saknas förklaring, `notice` och hjälprad står bara rubriken och meningen om missad tömning.
    public static func make(notice: String?, notes: [AreaSourceNote]) -> AreaWarning {
        let named = notes.count > 1
        var explanations = notes.compactMap { note -> Entry? in
            note.explanation.map { text in Entry(id: note.id, name: named ? note.name : nil, text: text) }
        }
        if explanations.isEmpty, let notice = notice?.trimmedNonEmpty {
            explanations = [Entry(id: "notice", name: nil, text: notice)]
        }
        let helps = notes.compactMap { note -> Help? in
            note.help.map { text in Help(id: note.id, name: named ? note.name : nil, text: text) }
        }
        return AreaWarning(explanations: explanations, helps: helps)
    }

    /// Om meningen om missad tömning ska stå för sig. Den utelämnas när en förklaring (till exempel `notice` som
    /// reservtext) redan innehåller den, så att den inte står två gånger.
    public var showsConsequence: Bool {
        !explanations.contains { entry in entry.text.contains(Self.consequence) }
    }
}
