import Foundation
import Testing
import SophamtningKit

/// Källan som ansvarar för hämtningen: avkodningen av `contact` i `/kallor` och länkarna i kortet och på Datakällor.
@Suite struct SourceContactTests {
    private func decode(_ contact: String?) throws -> Source {
        let field = contact.map { #", "contact": \#($0)"# } ?? ""
        let json = #"{"id": "uppsala", "name": "Uppsala Vatten", "url": "https://www.uppsalavatten.se", "kommuner": [{"code": "0380", "name": "Uppsala kommun"}], "testData": false\#(field)}"#
        return try JSONDecoder().decode(Source.self, from: Data(json.utf8))
    }

    private let full = #"{"phone": {"number": "+46187279400", "display": "018-727 94 00"}, "email": "kundservice@uppsalavatten.se", "page": "https://www.uppsalavatten.se/kontakt", "checkedAt": "2026-11-07", "checkedUrl": "https://www.uppsalavatten.se/kontakt"}"#

    // MARK: Avkodning

    @Test func utanFaltetFinnsIngenKontakt() throws {
        #expect(try decode(nil).contact == nil)
    }

    @Test func nullGerIngenKontakt() throws {
        #expect(try decode("null").contact == nil)
    }

    @Test func allaDelarAvkodas() throws {
        let contact = try #require(try decode(full).contact)
        #expect(contact.phone == SourceContact.Phone(number: "+46187279400", display: "018-727 94 00"))
        #expect(contact.email == "kundservice@uppsalavatten.se")
        #expect(contact.page == URL(string: "https://www.uppsalavatten.se/kontakt"))
        #expect(contact.checkedAt == DayDate("2026-11-07"))
        #expect(contact.checkedUrl == URL(string: "https://www.uppsalavatten.se/kontakt"))
    }

    @Test func enskildaDelarKanVaraNull() throws {
        let contact = try #require(try decode(#"{"phone": null, "email": "kundservice@uppsalavatten.se", "page": null, "checkedAt": null, "checkedUrl": null}"#).contact)
        #expect(contact.phone == nil)
        #expect(contact.email == "kundservice@uppsalavatten.se")
        #expect(contact.page == nil)
        #expect(contact.checkedAt == nil)
        let partPhone = try #require(try decode(#"{"phone": {"number": "+46187279400", "display": null}}"#).contact)
        #expect(partPhone.phone == SourceContact.Phone(number: "+46187279400", display: nil))
    }

    @Test func trasigKontaktFallerInteKallan() throws {
        #expect(try decode(#""ring oss""#).contact == nil)
        let contact = try #require(try decode(#"{"phone": "018-727 94 00", "email": 12, "page": "https://www.uppsalavatten.se/kontakt"}"#).contact)
        #expect(contact.phone == nil)
        #expect(contact.email == nil)
        #expect(contact.page != nil)
    }

    @Test func kontaktenSparasOchLasesIgen() throws {
        let source = try decode(full)
        let again = try JSONDecoder().decode(Source.self, from: JSONEncoder().encode(source))
        #expect(again == source)
    }

    // MARK: Länkar

    @Test func webbplatsOchKommunensInformationIOrdning() throws {
        let links = SourceLink.links(for: try decode(nil), kommunInfo: URL(string: "https://www.uppsala.se/avfall"))
        #expect(links.map(\.title) == ["Webbplats", "Kommunens information"])
        #expect(links.map(\.kind) == [.website, .kommunInfo])
        #expect(links.allSatisfy { $0.webLink != nil })
    }

    @Test func kontaktenVisasMedRingMejlOchKontaktsida() throws {
        let links = SourceLink.links(for: try decode(full), kommunInfo: nil)
        #expect(links.map(\.kind) == [.website, .phone, .email, .contactPage])
        #expect(links.map(\.title) == ["Webbplats", "018-727 94 00", "kundservice@uppsalavatten.se", "Kontaktsida"])
        #expect(links.map(\.icon) == ["globe", "phone", "envelope", "link"])
        #expect(links[1].url == URL(string: "tel:+46187279400"))
        #expect(links[1].webLink == nil)
        #expect(links[2].url == URL(string: "mailto:kundservice@uppsalavatten.se"))
        #expect(links[3].webLink?.url == URL(string: "https://www.uppsalavatten.se/kontakt"))
        #expect(links[1].accessibilityLabel == "Ring 018-727 94 00")
        #expect(links[2].accessibilityLabel == "Mejla kundservice@uppsalavatten.se")
    }

    @Test func baraTelefonenStarIAccentfargOchWebbsidorFarPil() throws {
        let links = SourceLink.links(for: try decode(full), kommunInfo: URL(string: "https://www.uppsala.se/avfall"))
        #expect(links.map(\.kind) == [.website, .kommunInfo, .phone, .email, .contactPage])
        // Telefonnumret är det man oftast vill använda, så det står i accentfärg. Resten står i vanlig textfärg.
        #expect(links.map(\.isPrimaryAction) == [false, false, true, false, false])
        // Sidor som öppnas i appens webbvy får en pil, som rader i iOS listor. Telefon och e-post öppnas av iOS.
        #expect(links.map(\.showsChevron) == [true, true, false, false, true])
    }

    @Test func telefonUtanVisningsformVisarNumret() throws {
        let links = SourceLink.links(for: try decode(#"{"phone": {"number": "+46187279400", "display": null}}"#), kommunInfo: nil)
        #expect(links.last?.title == "+46187279400")
    }

    @Test func detSomSaknasVisasInte() throws {
        // Ingen källa, ingen sida för kommunen, trasiga adresser och telefon utan nummer.
        #expect(SourceLink.links(for: nil, kommunInfo: nil).isEmpty)
        let http = Source(id: "x", name: "X", url: URL(string: "http://example.com")!, kommuner: [], testData: false,
                          contact: SourceContact(phone: SourceContact.Phone(number: nil, display: "018-727 94 00"), email: "inte en adress", page: URL(string: "http://example.com/kontakt")))
        #expect(SourceLink.links(for: http, kommunInfo: URL(string: "http://example.com/avfall")).isEmpty)
    }

    // MARK: Datakällor

    @Test func kommunernaKallanTacker() {
        let source = Source(id: "x", name: "X", url: URL(string: "https://example.com")!, kommuner: [Kommun(code: "1", name: "Avesta kommun"), Kommun(code: "2", name: "Hedemora kommun"), Kommun(code: "3", name: "Säters kommun")], testData: false)
        #expect(source.kommunerText == "Avesta kommun, Hedemora kommun och Säters kommun")
        let one = Source(id: "y", name: "Y", url: URL(string: "https://example.com")!, kommuner: [Kommun(code: "0980", name: "Region Gotland")], testData: false)
        #expect(one.kommunerText == "Region Gotland")
    }
}
