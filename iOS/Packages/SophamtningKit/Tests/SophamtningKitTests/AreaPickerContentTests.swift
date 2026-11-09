import Foundation
import Testing
@testable import SophamtningKit

private func hit(_ id: String, _ name: String, places: [String] = []) -> SearchHit {
    SearchHit(id: id, street: name, locality: "", kommun: "Avesta kommun", source: "avesta", detail: nil, selection: "area", notice: nil, areasUrl: nil, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/\(id)")!, area: AreaDetails(day: "Måndag, udda vecka", label: nil, places: places))
}

private let hits = [
    hit("1", "Askön, Nyhyttan m.fl.", places: ["Askön", "Nyhyttan", "Klintbo"]),
    hit("2", "Kaplansgården, Jularbo m.fl."),
]

/// Områdesvalet: varningen, raden Hitta område och texten när inget matchar.
@Suite struct AreaPickerContentTests {
    @Test func tomtFaltVisarVarningenOchHittaOmradeForst() {
        let content = AreaPickerContent.make(hits, query: "", hasFinder: true)
        #expect(content.hits.map(\.id) == ["1", "2"])
        #expect(content.showsWarning)
        #expect(content.showsFinderFirst)
        #expect(content.emptyText == nil)
        #expect(!content.showsFinderWhenEmpty)
    }

    @Test func enEnsamBokstavArIngenSokning() {
        let content = AreaPickerContent.make(hits, query: " k ", hasFinder: true)
        #expect(content.hits.count == 2)
        #expect(content.showsWarning)
        #expect(content.showsFinderFirst)
    }

    @Test func underSokningVisasBaraTraffarna() {
        // En plats som bara står i listan över platser hittar rätt område.
        let content = AreaPickerContent.make(hits, query: "klintbo", hasFinder: true)
        #expect(content.hits.map(\.id) == ["1"])
        #expect(!content.showsWarning)
        #expect(!content.showsFinderFirst)
        #expect(content.emptyText == nil)
    }

    @Test func ingaTraffarGerTextOchHittaOmradeSomVagVidare() {
        let content = AreaPickerContent.make(hits, query: " zzz ", hasFinder: true)
        #expect(content.hits.isEmpty)
        #expect(content.emptyText == "Inga områden matchar ”zzz”.")
        #expect(content.showsFinderWhenEmpty)
        #expect(!content.showsFinderFirst)
        #expect(!content.showsWarning)
    }

    @Test func utanOrtFinnsIngenHittaOmrade() {
        #expect(!AreaPickerContent.make(hits, query: "", hasFinder: false).showsFinderFirst)
        #expect(!AreaPickerContent.make(hits, query: "zzz", hasFinder: false).showsFinderWhenEmpty)
    }
}
