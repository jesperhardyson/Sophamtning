import Foundation
import Testing
@testable import SophamtningKit

@Suite struct KommunCheckerTests {
    let index: PlaceIndex

    init() throws {
        index = try PlaceIndex.bundled()
    }

    /// Kommunnamn som källorna använder när de skiljer sig från ortlistan.
    static let sourceNames = ["0980": "Gotlands kommun"]

    /// `covered` är kommunkod till källans id.
    func sources(_ covered: [String: String]) -> [Source] {
        var byId: [String: [Kommun]] = [:]
        var order: [String] = []
        for (code, id) in covered.sorted(by: { $0.key < $1.key }) {
            if byId[id] == nil { order.append(id) }
            byId[id, default: []].append(Kommun(code: code, name: Self.sourceNames[code] ?? index.kommunName(code) ?? code))
        }
        return order.map { Source(id: $0, name: $0, url: URL(string: "https://example.com/\($0)")!, kommuner: byId[$0]!, testData: false) }
    }

    func check(_ q: String, covered: [String: String]) -> KommunAnswer {
        KommunChecker.check(q, index: index, sources: sources(covered))
    }

    func isCovered(_ a: KommunAnswer) -> Bool {
        if case .covered = a { return true }
        return false
    }

    func row(_ code: String, _ name: String, _ sourceId: String? = nil) -> KommunRow {
        KommunRow(code: code, name: name, sourceId: sourceId)
    }

    @Test func tomText() {
        #expect(check("  ", covered: [:]) == .empty)
        #expect(check("k", covered: [:]) == .empty)
        #expect(check(" k ", covered: [:]) == .empty)
    }

    @Test func kommunnamnGarForeOrt() {
        guard case .covered(let row, nil) = check("stockholm", covered: ["0180": "stockholm-kalla"]) else { Issue.record(); return }
        #expect(row.name == "Stockholms kommun")
    }

    @Test func moraGallerKommunenInteOrten() {
        // Orten Mora finns också i Säter och Eskilstuna, men kommunnamnet går först.
        let a = check("mora", covered: ["2062": "mora-kalla"])
        #expect(a == .covered(row("2062", "Mora kommun", "mora-kalla"), viaPlace: nil))
        #expect(check("mora", covered: [:]) == .notYet(row("2062", "Mora kommun")))
    }

    @Test func medOchUtanKommunOchGenitiv() {
        for q in ["örebro", "Örebro kommun", "orebro", "ÖREBROS", "  Örebros kommun "] {
            #expect(isCovered(check(q, covered: ["1880": "orebro"])), "\(q)")
        }
    }

    @Test func ortITackKommun() {
        #expect(check("krylbo", covered: ["2084": "avesta"]) ==
            .covered(KommunRow(code: "2084", name: "Avesta kommun", sourceId: "avesta"), viaPlace: "Krylbo"))
    }

    @Test func ortStavningenKommerFranListan() {
        guard case .covered(_, let via) = check("KRYLBO", covered: ["2084": "avesta"]) else { Issue.record(); return }
        #expect(via == "Krylbo")
    }

    @Test func ortIOtackKommunGerNotYetMedRad() {
        #expect(check("krylbo", covered: [:]) == .notYet(row("2084", "Avesta kommun")))
    }

    @Test func inteAn() {
        #expect(check("järfälla", covered: [:]) == .notYet(row("0123", "Järfälla kommun")))
    }

    @Test func ortIFleraKommuner() {
        guard case .multiple("Almvik", let rows) = check("almvik", covered: ["0181": "telge"]) else { Issue.record(); return }
        #expect(rows.count == 2)
        #expect(rows.first { $0.code == "0181" }?.sourceId == "telge")
        #expect(rows.first { $0.code != "0181" }?.sourceId == nil)
    }

    @Test func forstaKallanVinnerNarFleraTackerSammaKommun() {
        let url = URL(string: "https://example.com")!
        let k = [Kommun(code: "1880", name: "Örebro kommun")]
        let list = [
            Source(id: "a", name: "A", url: url, kommuner: k, testData: false),
            Source(id: "b", name: "B", url: url, kommuner: k, testData: false),
        ]
        #expect(KommunChecker.check("örebro", index: index, sources: list) ==
            .covered(row("1880", "Örebro kommun", "a"), viaPlace: nil))
    }

    @Test func forslagKortastForstHogstFem() {
        #expect(check("kry", covered: [:]) == .suggestions(["Krylbo"]))
        guard case .suggestions(let s) = check("sk", covered: [:]) else { Issue.record("förväntade förslag"); return }
        #expect(s.count == 5)
        #expect(s.map(\.count) == s.map(\.count).sorted())
        #expect(s.allSatisfy { $0.lowercased().hasPrefix("sk") })
    }

    @Test func okandPlats() {
        #expect(check("xyzby", covered: [:]) == .unknown)
    }

    @Test func utanKallistaAldrigFinnsInte() {
        let i = index
        #expect(KommunChecker.check("järfälla", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("krylbo", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("almvik", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("kry", index: i, sources: nil) == .suggestions(["Krylbo"]))
        #expect(KommunChecker.check("xyzby", index: i, sources: nil) == .unknown)
        #expect(KommunChecker.check(" ", index: i, sources: nil) == .empty)
    }

    @Test func tomKallistaArInteDetSammaSomSaknad() {
        #expect(KommunChecker.check("järfälla", index: index, sources: []) == .notYet(row("0123", "Järfälla kommun")))
    }

    func codes(_ a: KommunAnswer) -> [String] {
        switch a {
        case .covered(let r, _), .notYet(let r): [r.code]
        case .multiple(_, let rows): rows.map(\.code).sorted()
        default: []
        }
    }

    @Test func gotlandHittasMedOchUtanRegionOchKommun() {
        for q in ["gotland", "Gotlands kommun", "region gotland", "Region Gotland"] {
            #expect(check(q, covered: ["0980": "gotland"]) ==
                .covered(row("0980", "Gotlands kommun", "gotland"), viaPlace: nil), "\(q)")
            #expect(check(q, covered: [:]) == .notYet(row("0980", "Region Gotland")), "\(q)")
        }
    }

    @Test func haboUtanPrickarGerHaboOchHabo() {
        guard case .multiple("habo", let rows) = check("habo", covered: [:]) else { Issue.record(); return }
        #expect(rows.map(\.code).sorted() == ["0305", "0643"])
    }

    @Test func haboMedPrickarGerBaraHabo() {
        #expect(check("håbo", covered: [:]) == .notYet(row("0305", "Håbo kommun")))
        #expect(check("Håbo kommun", covered: [:]) == .notYet(row("0305", "Håbo kommun")))
    }

    @Test func marstaUtanPrickarGerBadaMarstaOchMarsta() {
        guard case .multiple("marsta", let rows) = check("marsta", covered: [:]) else { Issue.record(); return }
        #expect(rows.map(\.code).sorted() == ["0191", "0380"])
    }

    @Test func marstaMedPrickarGerBaraMarsta() {
        #expect(check("märsta", covered: [:]) == .notYet(row("0191", "Sigtuna kommun")))
    }

    @Test func albyOchAlbyGerAllaKommuner() {
        guard case .multiple("alby", let rows) = check("alby", covered: [:]) else { Issue.record(); return }
        let alby = Set(codes(check("alby", covered: [:])))
        #expect(alby.count == rows.count)
        let a = index.place(matching: "Alby")?.codes ?? []
        let b = index.place(matching: "Älby")?.codes ?? []
        #expect(Set(a + b) == alby)
        #expect(!b.isEmpty && !a.isEmpty)
    }

    @Test func forslagOmfattarKommuner() {
        #expect(check("hudd", covered: [:]) == .suggestions(["Huddinge", "Huddunge"]))
        guard case .suggestions(let s) = check("nac", covered: [:]) else { Issue.record(); return }
        #expect(s.first == "Nacka")
        #expect(s.count <= 5)
        #expect(Set(s).count == s.count)
        guard case .suggestions(let g) = check("gotl", covered: [:]) else { Issue.record(); return }
        #expect(g.contains("Gotland"))
    }

    @Test func dataMatcharFilen() throws {
        let i = try PlaceIndex.bundled()
        #expect(i.kommunCount == 290)
        #expect(i.placeCount == 6524)
    }

    @Test func egetIndexUtanFil() {
        let i = PlaceIndex(kommuner: ["0001": "Testby kommun"], orter: ["Lilla": ["0001"]])
        #expect(KommunChecker.check("lilla", index: i, sources: []) == .notYet(row("0001", "Testby kommun")))
    }
}
