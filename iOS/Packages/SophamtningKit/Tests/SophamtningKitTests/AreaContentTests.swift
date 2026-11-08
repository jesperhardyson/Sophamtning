import Testing
import Foundation
@testable import SophamtningKit

private func areas(_ name: String) throws -> SearchResponse {
    try JSONDecoder().decode(SearchResponse.self, from: fixtureData(name))
}

private func areaHit(detail: String? = "Måndag, udda vecka · Område 1", area: AreaDetails?) -> SearchHit {
    SearchHit(id: "trakt-1", street: "Askön, Nyhyttan m.fl.", locality: "", kommun: "Avesta kommun", source: "avesta", detail: detail, selection: "area", notice: nil, areasUrl: nil, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/trakt-1")!, area: area)
}

@Suite struct AreaDecodingTests {
    @Test func detaljerOchKallorAvkodas() throws {
        let response = try areas("omraden-detaljer")
        let first = try #require(response.addresses.first?.area)
        #expect(first.day == "Måndag, udda vecka")
        #expect(first.label == "Område 1")
        #expect(first.places.prefix(2) == ["Askön", "Nyhyttan"])
        #expect(first.otherDays.isEmpty)
        #expect(first.searchTerms.contains("trakt 1"))
        #expect(response.addresses.first { $0.id == "trakt-7" }?.area?.otherDays.count == 1)
        #expect(response.sources == [AreaSource(
            id: "avesta",
            name: "Avesta Vatten och Avfall",
            explanation: "Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område.",
            help: "Osäker? Fråga Avesta Vatten på 0226-64 55 00."
        )])
    }

    @Test func aldreSvarUtanFaltenArInteEttFel() throws {
        let response = try areas("omraden")
        #expect(response.addresses.count == 10)
        #expect(response.addresses.allSatisfy { $0.area == nil })
        #expect(response.sources.isEmpty)
    }

    @Test func trasigaFaltFallerInteOmradena() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("omraden-detaljer")) as? [String: Any])
        var hits = try #require(json["addresses"] as? [[String: Any]])
        hits[0]["area"] = "trasig"
        hits[1]["area"] = ["day": 3, "label": NSNull(), "places": "Rosse", "otherDays": NSNull()]
        hits[2]["area"] = NSNull()
        json["addresses"] = hits
        json["sources"] = [["id": "avesta", "name": "Avesta", "explanation": 5, "help": NSNull()], ["name": "utan id"]]
        let response = try JSONDecoder().decode(SearchResponse.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(response.addresses.count == 10)
        #expect(response.addresses[0].area == nil)
        #expect(response.addresses[1].area == AreaDetails(day: "", label: nil, places: []))
        #expect(response.addresses[2].area == nil)
        #expect(response.sources == [AreaSource(id: "avesta", name: "Avesta", explanation: nil, help: nil)])

        json["sources"] = "trasig"
        let broken = try JSONDecoder().decode(SearchResponse.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(broken.sources.isEmpty)
        #expect(broken.addresses.count == 10)
    }
}

@Suite struct AreaRowContentTests {
    @Test func radenVisarEtikettDagOchKortaPlatser() throws {
        let hit = try #require(try areas("omraden-detaljer").addresses.first)
        let row = AreaRowContent.make(hit)
        #expect(row.title == "Askön, Nyhyttan m.fl.")
        #expect(row.label == "Område 1")
        #expect(row.day == "Måndag, udda vecka")
        #expect(row.places == "Askön, Nyhyttan, Klintbo, Snickarbo m.fl.")
        #expect(row.allPlaces?.hasPrefix("Askön, Nyhyttan, Klintbo, Snickarbo, Knallasbenning") == true)
        #expect(row.allPlaces?.hasSuffix("Högbo och Rutbo") == true)
        #expect(row.otherDays.isEmpty)
        #expect(row.detailed)
        #expect(row.hidesPlaces)
        #expect(row.showAllPlacesText == "Visa alla 18 platser")
    }

    @Test func fåPlatserVisasAllaUtanMfl() {
        let three = AreaRowContent.make(areaHit(area: AreaDetails(day: "Onsdag, udda vecka", label: "Område 3", places: ["Fors", "Nordanö", "Brogård"])))
        #expect(three.places == "Fors, Nordanö, Brogård")
        #expect(three.allPlaces == "Fors, Nordanö och Brogård")
        // En enda plats till ger ingen "m.fl.".
        let five = AreaRowContent.make(areaHit(area: AreaDetails(day: "Dag", label: nil, places: ["A", "B", "C", "D", "E"])))
        #expect(five.places == "A, B, C, D, E")
        #expect(!five.hidesPlaces)
        let six = AreaRowContent.make(areaHit(area: AreaDetails(day: "Dag", label: nil, places: ["A", "B", "C", "D", "E", "F"])))
        #expect(six.places == "A, B, C, D m.fl.")
    }

    @Test func andraDagarVisasNarDeFinns() throws {
        let hit = try #require(try areas("omraden-detaljer").addresses.first { $0.id == "trakt-7" })
        let row = AreaRowContent.make(hit)
        #expect(row.otherDays == ["Till exempel Stallgatan och Storbogatan (måndag, udda vecka) och Bodgatan (onsdag, jämn vecka)."])
        #expect(row.accessibilityLabel.hasSuffix("Vissa gator har en annan hämtdag. Till exempel Stallgatan och Storbogatan (måndag, udda vecka) och Bodgatan (onsdag, jämn vecka)."))
    }

    @Test func utanDetaljerVisasDagensRad() {
        let row = AreaRowContent.make(areaHit(area: nil))
        #expect(row == AreaRowContent(title: "Askön, Nyhyttan m.fl.", label: nil, day: "Måndag, udda vecka · Område 1", places: nil, allPlaces: nil, otherDays: []))
        // En tom dag räknas som saknade detaljer, så att raden aldrig blir tom.
        let empty = AreaRowContent.make(areaHit(area: AreaDetails(day: "  ", label: "Område 1", places: ["Askön"])))
        #expect(empty.day == "Måndag, udda vecka · Område 1")
        #expect(empty.label == nil)
    }

    @Test func tomEtikettOchTommaPlatserVisasInte() {
        let row = AreaRowContent.make(areaHit(area: AreaDetails(day: "Fredag", label: " ", places: [" ", ""], otherDays: [""])))
        #expect(row.label == nil)
        #expect(row.places == nil)
        #expect(row.allPlaces == nil)
        #expect(row.otherDays.isEmpty)
    }

    @Test func voiceOverLaserAllaPlatser() {
        let row = AreaRowContent.make(areaHit(area: AreaDetails(day: "Måndag, udda vecka", label: "Område 1", places: ["A", "B", "C", "D", "E", "F"])))
        #expect(row.accessibilityLabel == "Askön, Nyhyttan m.fl., Område 1, Måndag, udda vecka. Platser: A, B, C, D, E och F.")
        let plain = AreaRowContent.make(areaHit(area: nil))
        #expect(plain.accessibilityLabel == "Askön, Nyhyttan m.fl., Måndag, udda vecka · Område 1.")
    }
}

@Suite struct AreaSourceNoteTests {
    @Test func forklaringOchHjalpradMedTelefonlank() throws {
        let notes = AreaSourceNote.notes(try areas("omraden-detaljer").sources)
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.explanation == "Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område.")
        let help = try #require(note.help)
        // Texten står som källan skrev den.
        #expect(String(help.characters) == "Osäker? Fråga Avesta Vatten på 0226-64 55 00.")
        let links = help.runs.compactMap { run in run.link.map { url in (url, String(help[run.range].characters)) } }
        #expect(links.count == 1)
        #expect(links.first?.0 == URL(string: "tel:0226645500"))
        #expect(links.first?.1 == "0226-64 55 00")
    }

    @Test func utanNummerArTextenOforandrad() {
        let help = AreaSourceNote.linkingPhoneNumbers("Fråga kommunen.")
        #expect(String(help.characters) == "Fråga kommunen.")
        #expect(help.runs.allSatisfy { $0.link == nil })
    }

    @Test func tommaKallorGerIngenForklaring() {
        #expect(AreaSourceNote.notes([]).isEmpty)
        #expect(AreaSourceNote.notes([AreaSource(id: "a", name: "A", explanation: " ", help: nil)]).isEmpty)
        let twice = AreaSourceNote.notes([AreaSource(id: "a", name: "A", explanation: "X", help: nil), AreaSource(id: "a", name: "A", explanation: "X", help: nil)])
        #expect(twice.count == 1)
        #expect(twice.first?.help == nil)
    }

    @Test func telLankBehallerPlus() {
        #expect(AreaSourceNote.telURL("+46 226-64 55 00") == URL(string: "tel:+46226645500"))
        #expect(AreaSourceNote.telURL("12") == nil)
    }
}
