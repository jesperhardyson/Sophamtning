import Foundation
import Testing
@testable import SophamtningKit

@Suite struct KommunCheckerTests {
    static let index: PlaceIndex = {
        do { return try PlaceIndex.bundled() } catch { fatalError("Ortlistan kunde inte läsas: \(error)") }
    }()

    /// `covered` är kommunkod till källans id.
    func sources(_ covered: [String: String]) -> [Source] {
        var byId: [String: [Kommun]] = [:]
        var order: [String] = []
        for (code, id) in covered.sorted(by: { $0.key < $1.key }) {
            if byId[id] == nil { order.append(id) }
            byId[id, default: []].append(Kommun(code: code, name: Self.index.kommunName(code) ?? code))
        }
        return order.map { Source(id: $0, name: $0, url: URL(string: "https://example.com/\($0)")!, kommuner: byId[$0]!, testData: false) }
    }

    func check(_ q: String, covered: [String: String]) -> KommunAnswer {
        KommunChecker.check(q, index: Self.index, sources: sources(covered))
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
        #expect(KommunChecker.check("örebro", index: Self.index, sources: list) ==
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
        let i = Self.index
        #expect(KommunChecker.check("järfälla", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("krylbo", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("almvik", index: i, sources: nil) == .unavailable)
        #expect(KommunChecker.check("kry", index: i, sources: nil) == .suggestions(["Krylbo"]))
        #expect(KommunChecker.check("xyzby", index: i, sources: nil) == .unknown)
        #expect(KommunChecker.check(" ", index: i, sources: nil) == .empty)
    }

    @Test func tomKallistaArInteDetSammaSomSaknad() {
        #expect(KommunChecker.check("järfälla", index: Self.index, sources: []) == .notYet(row("0123", "Järfälla kommun")))
    }

    @Test func habeoOchHaboSkiljsPaStavning() {
        #expect(check("habo", covered: [:]) == .notYet(row("0643", "Habo kommun")))
        #expect(check("håbo", covered: [:]) == .notYet(row("0305", "Håbo kommun")))
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
