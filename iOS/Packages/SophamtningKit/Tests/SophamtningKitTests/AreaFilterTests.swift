import Testing
import Foundation
@testable import SophamtningKit

private func hit(_ id: String, _ name: String, area: AreaDetails? = nil, detail: String? = nil) -> SearchHit {
    SearchHit(id: id, street: name, locality: "", kommun: "Avesta kommun", source: "avesta", detail: detail, selection: "area", notice: nil, areasUrl: nil, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/\(id)")!, area: area)
}

private let hits = [
    hit("1", "Askön, Nyhyttan m.fl.", area: AreaDetails(day: "Måndag, udda vecka", label: "Område 1", places: ["Askön", "Nyhyttan", "Klintbo"], searchTerms: ["trakt 1", "Åsen"])),
    hit("2", "Östra Krylbo", area: AreaDetails(day: "Tisdag, jämn vecka", label: "Område 2", places: ["Krylbo", "Café Hörnan"], searchTerms: [])),
    hit("3", "Kaplansgården, Jularbo m.fl."),
]

private func ids(_ query: String, in list: [SearchHit] = hits) -> [String] {
    AreaFilter.filter(list, query: query).map(\.id)
}

@Suite struct AreaFilterTests {
    @Test func tomtFaltGerAlla() {
        #expect(ids("") == ["1", "2", "3"])
        #expect(ids("   ") == ["1", "2", "3"])
    }

    @Test func enEnsamBokstavFiltrerarInte() {
        // Som på webben filtreras det först från 2 tecken. Trimmat räknas, så " k " är en bokstav.
        #expect(ids("k") == ["1", "2", "3"])
        #expect(ids(" k ") == ["1", "2", "3"])
        #expect(ids("kr") == ["2"])
        #expect(ids(" kr ") == ["2"])
    }

    @Test func namnetMatcharUtanSkiftlage() {
        #expect(ids("KRYLBO") == ["2"])
        #expect(ids("kaplans") == ["3"])
    }

    @Test func ordetMatcharPaBorjan() {
        #expect(ids("nyh") == ["1"])
        // Mitt i ett ord är ingen träff.
        #expect(ids("yhyttan").isEmpty)
    }

    @Test func etiketten() {
        #expect(ids("område 2") == ["2"])
        #expect(ids("omr 1") == ["1"])
    }

    @Test func dagen() {
        #expect(ids("måndag") == ["1"])
        #expect(ids("jämn vecka") == ["2"])
    }

    @Test func platserna() {
        #expect(ids("klintbo") == ["1"])
        #expect(ids("hörnan") == ["2"])
    }

    @Test func soktermerna() {
        #expect(ids("trakt 1") == ["1"])
        #expect(ids("åsen") == ["1"])
    }

    @Test func allaOrdenMasteFinnasIEttOmrade() {
        #expect(ids("krylbo tisdag") == ["2"])
        #expect(ids("krylbo måndag").isEmpty)
    }

    @Test func diakriterOverSvenskaBokstaver() {
        // é och e är samma, men å, ä och ö är egna bokstäver, som på webben.
        #expect(ids("cafe") == ["2"])
        #expect(ids("café") == ["2"])
        #expect(ids("östra") == ["2"])
        #expect(ids("ostra").isEmpty)
        #expect(ids("asen").isEmpty)
    }

    @Test func saknadeFaltMatcharBaraNamnet() {
        #expect(ids("jularbo") == ["3"])
        #expect(ids("måndag", in: [hits[2]]).isEmpty)
        #expect(ids("område", in: [hits[2]]).isEmpty)
    }

    @Test func detailAnvandsInteSomFalt() {
        let plain = [hit("9", "Fors", detail: "Torsdag · Område 9")]
        #expect(ids("torsdag", in: plain).isEmpty)
    }

    @Test func smaordenRackerInteEnsamma() {
        // "m.fl." står i många namn men ger ingen träff på egen hand.
        #expect(ids("fl").isEmpty)
        #expect(ids("och").isEmpty)
        // Ett småord bredvid ett riktigt sökord räknas inte med.
        #expect(ids("krylbo och") == ["2"])
    }

    @Test func ordningenBehalls() {
        #expect(AreaFilter.filter(hits.reversed(), query: "omr").map(\.id) == ["2", "1"])
    }

    @Test func utanTraffarArListanTom() {
        #expect(ids("zzz").isEmpty)
    }

    @Test func tecknenFarInteGoraAttNagotSaknas() {
        #expect(ids("askön,") == ["1"])
        #expect(ids("m.fl. askön") == ["1"])
    }
}
