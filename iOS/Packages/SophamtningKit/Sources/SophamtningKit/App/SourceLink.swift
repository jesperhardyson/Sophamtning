import Foundation

/// En länk i kortet "Ansvarar för hämtningen" och på sidan Datakällor. Bara det som har ett giltigt värde visas.
public struct SourceLink: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Källans webbplats, i appens webbvy.
        case website
        /// Adressens sida hos kommunen eller bolaget (`links.web`), i appens webbvy.
        case kommunInfo
        /// Ett tryck ringer.
        case phone
        /// Ett tryck öppnar ett nytt mejl.
        case email
        /// Källans kontaktsida, i appens webbvy.
        case contactPage
        /// Adressens schema i Kalender (`webcal://`). iOS frågar om prenumeration.
        case calendar
    }

    public let kind: Kind
    /// "Webbplats", "018-727 94 00" eller "kundservice@uppsalavatten.se".
    public let title: String
    public let url: URL

    public var id: Kind { kind }

    /// SF Symbol: jordglob, byggnad, telefon, kuvert och länk.
    public var icon: String {
        switch kind {
        case .website: "globe"
        case .kommunInfo: "building.columns"
        case .phone: "phone"
        case .email: "envelope"
        case .contactPage: "link"
        case .calendar: "calendar.badge.plus"
        }
    }

    /// Länkar som öppnas i appens webbvy. Telefon och e-post öppnas av iOS.
    /// Telefonnumret står i accentfärg, eftersom det oftast är det man vill använda. Övriga länkar står i vanlig textfärg.
    public var isPrimaryAction: Bool { kind == .phone }

    /// Sidor som öppnas i appens webbvy får en pil, som rader i iOS listor. Telefon och e-post öppnas av iOS.
    public var showsChevron: Bool { webLink != nil }

    public var webLink: WebLink? {
        switch kind {
        case .website, .kommunInfo, .contactPage: WebLink(url: url)
        case .phone, .email, .calendar: nil
        }
    }

    /// Det VoiceOver läser: vad som händer, och numret eller adressen.
    public var accessibilityLabel: String {
        switch kind {
        case .phone: "Ring \(title)"
        case .email: "Mejla \(title)"
        case .website, .kommunInfo, .contactPage, .calendar: title
        }
    }

    /// Webbplats, kommunens information och kontakten, i den ordningen. `kommunInfo` saknas på Datakällor.
    /// Kalendern står först, när adressen har en `links.ics`. Den saknas på Datakällor.
    public static func links(for source: Source?, kommunInfo: URL?, calendar: URL? = nil) -> [SourceLink] {
        var links: [SourceLink] = []
        if let calendar {
            links.append(SourceLink(kind: .calendar, title: "Lägg till i Kalender", url: calendar))
        }
        if let url = source?.url, WebLink(url: url) != nil {
            links.append(SourceLink(kind: .website, title: "Webbplats", url: url))
        }
        if let url = kommunInfo, WebLink(url: url) != nil {
            links.append(SourceLink(kind: .kommunInfo, title: "Kommunens information", url: url))
        }
        let contact = source?.contact
        if let phone = contact?.phone, let link = phoneLink(phone) { links.append(link) }
        if let email = contact?.email, let link = emailLink(email) { links.append(link) }
        if let page = contact?.page, WebLink(url: page) != nil {
            links.append(SourceLink(kind: .contactPage, title: "Kontaktsida", url: page))
        }
        return links
    }

    /// `tel:` med numret, bara plus och siffror. Utan nummer går det inte att ringa, och raden visas inte.
    private static func phoneLink(_ phone: SourceContact.Phone) -> SourceLink? {
        let number = (phone.number ?? "").filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        guard number.contains(where: \.isNumber), let url = URL(string: "tel:\(number)") else { return nil }
        let shown = phone.display?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SourceLink(kind: .phone, title: shown.isEmpty ? number : shown, url: url)
    }

    private static func emailLink(_ email: String) -> SourceLink? {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !address.contains(where: \.isWhitespace),
              let url = URL(string: "mailto:\(address)") else { return nil }
        return SourceLink(kind: .email, title: address, url: url)
    }
}
