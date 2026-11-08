import Foundation
import Testing
@testable import SophamtningKit

private func hit(_ id: String, selection: String = "address") -> SearchHit {
    SearchHit(id: id, street: "Storgatan \(id)", locality: "Örebro", kommun: "Örebro kommun", source: "orebro", detail: nil, selection: selection, notice: nil, areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/orebro/\(id)")!)
}

private func resp(_ hits: [SearchHit], failed: [String]) -> SearchResponse {
    SearchResponse(addresses: hits, failed: failed)
}

@Suite struct SearchStateTests {
    @Test func tomListaOchFailedBetyderForsokIgen() {
        #expect(SearchState.from(resp([], failed: ["uppsala"]), query: "x y") == .sourcesFailed(["uppsala"]))
    }

    @Test func traffarOchFailedVisasBada() {
        let hits = [hit("1"), hit("2")]
        #expect(SearchState.from(resp(hits, failed: ["uppsala"]), query: "storgatan") == .results(hits: hits, failed: ["uppsala"]))
    }

    @Test func traffarUtanFel() {
        let hits = [hit("1")]
        #expect(SearchState.from(resp(hits, failed: []), query: "storgatan 1") == .results(hits: hits, failed: []))
    }

    @Test func tomtOchUtanFelMedOrtGerOmradesval() {
        #expect(SearchState.from(resp([], failed: []), query: "kvarnvägen 3, avesta") == .noHits(place: "avesta"))
        #expect(SearchState.from(resp([], failed: []), query: "kvarnvägen 3") == .noHits(place: nil))
    }

    @Test func ortEfterKommatecken() {
        #expect(SearchState.place(in: "kvarnvägen 3, avesta") == "avesta")
        #expect(SearchState.place(in: "kvarnvägen, avesta") == "avesta")
        #expect(SearchState.place(in: "kvarnvägen 3,") == nil)
    }

    @Test func ortEfterHusnummer() {
        #expect(SearchState.place(in: "kvarnvägen 3 avesta") == "avesta")
        #expect(SearchState.place(in: "kvarnvägen 3 b avesta") == "avesta")
        #expect(SearchState.place(in: "kvarnvägen 3 b") == nil)
        #expect(SearchState.place(in: "kvarnvägen 3") == nil)
        #expect(SearchState.place(in: "kvarnvägen") == nil)
        #expect(SearchState.place(in: "  kvarnvägen   3   södra  avesta ") == "södra avesta")
    }

    @Test func ortkandidaterMedKommatecken() {
        #expect(SearchState.placeCandidates(in: "Bergslagsgatan, Avesta") == ["Avesta"])
    }

    @Test func ortkandidaterUtanKommatecken() {
        #expect(SearchState.placeCandidates(in: "Bergslagsgatan Avesta") == ["Bergslagsgatan Avesta", "Avesta"])
        #expect(SearchState.placeCandidates(in: "Storgatan Upplands Väsby") == ["Upplands Väsby", "Väsby"])
    }

    @Test func ortkandidaterEfterHusnummer() {
        #expect(SearchState.placeCandidates(in: "Bergslagsgatan 1 Avesta") == ["Avesta"])
        #expect(SearchState.placeCandidates(in: "Bergslagsgatan 12 B Avesta") == ["Avesta"])
    }

    @Test func ortkandidaterForBaraOrt() {
        #expect(SearchState.placeCandidates(in: "Avesta") == ["Avesta"])
        #expect(SearchState.placeCandidates(in: "Säter") == ["Säter"])
        #expect(SearchState.placeCandidates(in: "Upplands Väsby") == ["Upplands Väsby", "Väsby"])
        #expect(SearchState.placeCandidates(in: " avesta ") == ["avesta"])
    }

    @Test func ortkandidaterKraverTvaTecken() {
        #expect(SearchState.placeCandidates(in: "a").isEmpty)
        #expect(SearchState.placeCandidates(in: "").isEmpty)
        #expect(SearchState.placeCandidates(in: "Storgatan B") == ["Storgatan B"])
    }

    @Test func ortkandidaterHarHogstTvaOrd() {
        #expect(SearchState.placeCandidates(in: "Storgatan 3, Södra Avesta by").isEmpty)
        #expect(SearchState.placeCandidates(in: "Storgatan 3 Södra Avesta by").isEmpty)
        #expect(SearchState.placeCandidates(in: "Storgatan 3").isEmpty)
    }
}
